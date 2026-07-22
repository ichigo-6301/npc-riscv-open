// SPDX-License-Identifier: MIT
// Deterministic headless DPI memory service shared by the three public NPC
// profiles.  It intentionally has no dependency on NEMU, AM, board UI,
// readline, disassembly, or file-backed tracing.

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <fstream>
#include <string>
#include <unordered_map>

namespace {

constexpr unsigned kChannels = 2;
constexpr unsigned kTaggedCapacity = 2;
constexpr unsigned kPairCapacity = 8;
constexpr uint32_t kRtcLow = 0xa0000048u;
constexpr uint32_t kRtcHigh = 0xa000004cu;
constexpr uint32_t kSerialPort = 0xa00003f8u;

enum HaltReason : int {
  kHaltNone = 0,
  kHaltEbreak = 1,
  kHaltTohostPass = 2,
  kHaltIllegalInstruction = 3,
  kHaltTohostFail = 4,
  kHaltProtocolError = 5,
};

struct BasicRequest {
  bool busy = false;
  bool write = false;
  uint32_t addr = 0;
  int len = 4;
  uint32_t data = 0;
  unsigned delay_left = 0;
};

struct PairRequest {
  uint32_t addr = 0;
  unsigned delay_left = 0;
};

struct TaggedRequest {
  bool busy = false;
  bool write = false;
  int client = 0;
  int slot = 0;
  uint32_t generation = 0;
  uint32_t epoch = 0;
  uint32_t addr = 0;
  int len = 4;
  uint32_t data = 0;
  uint64_t ready_tick = 0;
  uint64_t sequence = 0;
  bool error = false;
};

struct TaggedChannel {
  std::array<TaggedRequest, kTaggedCapacity> entries{};
  uint64_t next_sequence = 0;
};

std::unordered_map<uint32_t, uint8_t> g_mem;
std::array<BasicRequest, kChannels> g_basic{};
std::array<std::deque<PairRequest>, kChannels> g_pairs{};
std::array<TaggedChannel, kChannels> g_tagged{};
uint64_t g_tick = 0;
uint32_t g_base = 0x80000000u;
uint32_t g_limit = 0x90000000u;
uint32_t g_tohost = 0;
std::array<unsigned, kChannels> g_channel_latency{{1u, 1u}};
unsigned g_memory_latency = 1;
bool g_explicit_config = false;
bool g_halted = false;
int g_halt_reason = kHaltNone;
uint32_t g_halt_pc = 0;
uint32_t g_halt_instr = 0;
bool g_protocol_error = false;

uint32_t env_u32(const char *name, uint32_t fallback) {
  const char *s = std::getenv(name);
  if (!s || !*s) return fallback;
  char *end = nullptr;
  const unsigned long value = std::strtoul(s, &end, 0);
  return (end && *end == '\0') ? static_cast<uint32_t>(value) : fallback;
}

bool channel_legal(int channel) {
  return channel >= 0 && static_cast<unsigned>(channel) < kChannels;
}

bool length_legal(int len) { return len == 1 || len == 2 || len == 4; }

bool in_pmem(uint32_t addr, int len) {
  if (len <= 0) return false;
  const uint64_t begin = addr;
  const uint64_t end = begin + static_cast<unsigned>(len);
  return begin >= g_base && end <= g_limit;
}

void set_halt(int reason, uint32_t pc, uint32_t instr) {
  if (g_halted) return;
  g_halted = true;
  g_halt_reason = reason;
  g_halt_pc = pc;
  g_halt_instr = instr;
}

void protocol_fail(const char *message) {
  if (!g_protocol_error) {
    std::fprintf(stderr, "public memory protocol error: %s\n", message);
  }
  g_protocol_error = true;
  set_halt(kHaltProtocolError, 0, 0);
}

uint8_t read_byte(uint32_t addr) {
  const auto it = g_mem.find(addr);
  return it == g_mem.end() ? 0 : it->second;
}

void write_byte(uint32_t addr, uint8_t value) { g_mem[addr] = value; }

uint32_t read_pmem(uint32_t addr, int len) {
  if (!in_pmem(addr, len)) return 0;
  uint32_t value = 0;
  for (int i = 0; i < len; ++i) {
    value |= uint32_t(read_byte(addr + static_cast<uint32_t>(i))) << (8 * i);
  }
  return value;
}

void write_pmem(uint32_t addr, int len, uint32_t value) {
  if (!in_pmem(addr, len)) return;
  for (int i = 0; i < len; ++i) {
    write_byte(addr + static_cast<uint32_t>(i),
               static_cast<uint8_t>(value >> (8 * i)));
  }
}

uint32_t read_access(uint32_t addr, int len) {
  if (in_pmem(addr, len)) return read_pmem(addr, len);
  if (addr == kRtcLow) return static_cast<uint32_t>(g_tick);
  if (addr == kRtcHigh) return static_cast<uint32_t>(g_tick >> 32);
  return 0;
}

void write_access(uint32_t addr, int len, uint32_t value) {
  if (g_tohost != 0 && addr == g_tohost && len == 4) {
    if (value == 1) {
      set_halt(kHaltTohostPass, addr, value);
    } else if ((value & 1u) != 0) {
      set_halt(kHaltTohostFail, addr, value);
    }
  }
  if (in_pmem(addr, len)) {
    write_pmem(addr, len, value);
    return;
  }
  if (addr == kSerialPort && (len == 1 || len == 4)) {
    std::putchar(static_cast<int>(value & 0xffu));
    std::fflush(stdout);
  }
}

unsigned latency_for(int channel) {
  return channel_legal(channel) ? g_channel_latency[static_cast<unsigned>(channel)]
                                : g_memory_latency;
}

unsigned tagged_busy_count(const TaggedChannel &channel) {
  unsigned count = 0;
  for (const auto &entry : channel.entries) count += entry.busy ? 1u : 0u;
  return count;
}

bool tagged_token_legal(int client, int slot) {
  if (client < 0 || client >= 4 || slot < 0 || slot >= 2) return false;
  return client != 3 || slot == 0;
}

bool same_token(const TaggedRequest &entry, int client, int slot,
                uint32_t generation, uint32_t epoch) {
  return entry.busy && entry.client == client && entry.slot == slot &&
         entry.generation == generation && entry.epoch == epoch;
}

TaggedRequest *oldest_ready(TaggedChannel &channel) {
  TaggedRequest *selected = nullptr;
  for (auto &entry : channel.entries) {
    if (!entry.busy || entry.ready_tick > g_tick) continue;
    if (!selected || entry.sequence < selected->sequence) selected = &entry;
  }
  return selected;
}

}  // namespace

extern "C" void npc_mem_configure(uint32_t ifetch_latency,
                                  uint32_t lsu_latency,
                                  uint32_t memory_latency) {
  g_channel_latency[0] = ifetch_latency;
  g_channel_latency[1] = lsu_latency;
  g_memory_latency = memory_latency;
  g_explicit_config = true;
}

extern "C" void npc_mem_reset(void) {
  g_mem.clear();
  g_basic = {};
  g_pairs = {};
  g_tagged = {};
  g_tick = 0;
  g_halted = false;
  g_halt_reason = kHaltNone;
  g_halt_pc = 0;
  g_halt_instr = 0;
  g_protocol_error = false;
  if (!g_explicit_config) {
    g_memory_latency = env_u32("NPC_PUBLIC_MEM_LATENCY", 1);
    g_channel_latency[0] =
        env_u32("NPC_PUBLIC_IFETCH_LATENCY", g_memory_latency);
    g_channel_latency[1] =
        env_u32("NPC_PUBLIC_LSU_LATENCY", g_memory_latency);
  }
  g_base = env_u32("NPC_PUBLIC_MEM_BASE", 0x80000000u);
  g_limit = env_u32("NPC_PUBLIC_MEM_LIMIT", 0x90000000u);
  g_tohost = env_u32("NPC_PUBLIC_TOHOST", 0);
  if (g_limit <= g_base) protocol_fail("memory limit must exceed base");
}

extern "C" void npc_mem_tick(void) { ++g_tick; }

extern "C" int npc_mem_load(const char *path) {
  if (!path || !*path) return 0;
  std::ifstream input(path, std::ios::binary);
  if (!input) return -1;
  const std::string name(path);
  const bool textual_hex = name.size() >= 4 &&
      (name.substr(name.size() - 4) == ".hex" ||
       name.substr(name.size() - 4) == ".mem");
  if (textual_hex) {
    input.close();
    std::ifstream text(path);
    std::string token;
    uint32_t addr = g_base;
    while (text >> token) {
      if (token.empty()) continue;
      if (token[0] == '#') {
        std::string ignored;
        std::getline(text, ignored);
        continue;
      }
      if (token[0] == '@') {
        addr = static_cast<uint32_t>(
            std::strtoul(token.c_str() + 1, nullptr, 16));
        continue;
      }
      const uint32_t word = static_cast<uint32_t>(
          std::strtoul(token.c_str(), nullptr, 16));
      if (!in_pmem(addr, 4)) return -2;
      write_pmem(addr, 4, word);
      addr += 4;
    }
    return 0;
  }
  uint32_t addr = g_base;
  char byte = 0;
  while (input.get(byte)) {
    if (!in_pmem(addr, 1)) return -2;
    write_byte(addr++, static_cast<uint8_t>(byte));
  }
  return 0;
}

extern "C" uint32_t pmem_read(uint32_t addr, int len) {
  if (!length_legal(len)) {
    protocol_fail("pmem_read length is not 1, 2, or 4");
    return 0;
  }
  return read_access(addr, len);
}

extern "C" void pmem_write(uint32_t addr, int len, uint32_t data) {
  if (!length_legal(len)) {
    protocol_fail("pmem_write length is not 1, 2, or 4");
    return;
  }
  write_access(addr, len, data);
}

extern "C" void dpi_pmem_req(int channel, int is_write, uint32_t addr,
                              int len, uint32_t data) {
  if (!channel_legal(channel) || !length_legal(len)) {
    protocol_fail("invalid untagged request channel or length");
    return;
  }
  auto &request = g_basic[static_cast<unsigned>(channel)];
  if (request.busy) {
    protocol_fail("duplicate untagged request while channel is busy");
    return;
  }
  request.busy = true;
  request.write = is_write != 0;
  request.addr = addr;
  request.len = len;
  request.data = data >> ((addr & 3u) * 8u);
  request.delay_left = latency_for(channel);
}

extern "C" int dpi_pmem_resp(int channel, uint32_t *data) {
  if (!channel_legal(channel) || data == nullptr) {
    protocol_fail("invalid untagged response channel or output pointer");
    return 0;
  }
  auto &request = g_basic[static_cast<unsigned>(channel)];
  *data = 0;
  if (!request.busy) return 0;
  if (request.delay_left > 0) {
    --request.delay_left;
    return 0;
  }
  if (request.write) {
    write_access(request.addr, request.len, request.data);
  } else {
    *data = read_access(request.addr, request.len)
            << ((request.addr & 3u) * 8u);
  }
  request.busy = false;
  return 1;
}

extern "C" void dpi_pmem_pair_req(int channel, uint32_t addr) {
  if (!channel_legal(channel) || (addr & 7u) != 0) {
    protocol_fail("invalid pair request channel or alignment");
    return;
  }
  auto &queue = g_pairs[static_cast<unsigned>(channel)];
  if (queue.size() >= kPairCapacity) {
    protocol_fail("pair request queue overflow");
    return;
  }
  queue.push_back(PairRequest{addr, latency_for(channel)});
}

extern "C" int dpi_pmem_pair_resp(int channel, uint64_t *data) {
  if (!channel_legal(channel) || data == nullptr) {
    protocol_fail("invalid pair response channel or output pointer");
    return 0;
  }
  auto &queue = g_pairs[static_cast<unsigned>(channel)];
  *data = 0;
  if (queue.empty()) return 0;
  for (auto &request : queue) {
    if (request.delay_left > 0) --request.delay_left;
  }
  if (queue.front().delay_left > 0) return 0;
  const uint32_t addr = queue.front().addr;
  queue.pop_front();
  const uint64_t lo = read_access(addr, 4);
  const uint64_t hi = read_access(addr + 4u, 4);
  *data = lo | (hi << 32);
  return 1;
}

extern "C" void dpi_pmem_tagged_req(
    int channel, int client, int slot, uint32_t generation, uint32_t epoch,
    int is_write, uint32_t addr, int len, uint32_t data) {
  if (!channel_legal(channel) || !length_legal(len) ||
      !tagged_token_legal(client, slot)) {
    protocol_fail("invalid tagged request channel, token, or length");
    return;
  }
  auto &state = g_tagged[static_cast<unsigned>(channel)];
  if (tagged_busy_count(state) >= kTaggedCapacity) {
    protocol_fail("tagged request queue overflow");
    return;
  }
  TaggedRequest *target = nullptr;
  for (auto &entry : state.entries) {
    if (same_token(entry, client, slot, generation, epoch)) {
      protocol_fail("duplicate tagged request token");
      return;
    }
    if (!entry.busy && target == nullptr) target = &entry;
  }
  if (target == nullptr) {
    protocol_fail("no free tagged request entry");
    return;
  }
  const uint64_t sequence = state.next_sequence++;
  target->busy = true;
  target->write = is_write != 0;
  target->client = client;
  target->slot = slot;
  target->generation = generation;
  target->epoch = epoch;
  target->addr = addr;
  target->len = len;
  target->data = data >> ((addr & 3u) * 8u);
  target->ready_tick = g_tick + latency_for(channel) + 1u;
  target->sequence = sequence;
  target->error = false;
}

extern "C" int dpi_pmem_tagged_resp(
    int channel, int *client, int *slot, uint32_t *generation,
    uint32_t *epoch, uint32_t *data, int *error) {
  if (!channel_legal(channel) || client == nullptr || slot == nullptr ||
      generation == nullptr || epoch == nullptr || data == nullptr ||
      error == nullptr) {
    protocol_fail("invalid tagged response arguments");
    return 0;
  }
  *client = 0;
  *slot = 0;
  *generation = 0;
  *epoch = 0;
  *data = 0;
  *error = 0;
  auto &state = g_tagged[static_cast<unsigned>(channel)];
  TaggedRequest *request = oldest_ready(state);
  if (request == nullptr) return 0;
  if (request->write) {
    write_access(request->addr, request->len, request->data);
    *data = request->data;
  } else {
    *data = read_access(request->addr, request->len)
            << ((request->addr & 3u) * 8u);
  }
  *client = request->client;
  *slot = request->slot;
  *generation = request->generation;
  *epoch = request->epoch;
  *error = request->error ? 1 : 0;
  request->busy = false;
  return 1;
}

extern "C" void ftrace_print(unsigned char, int, unsigned char, uint32_t,
                             uint32_t, uint32_t) {}
extern "C" void ideal_cache_record_dcache(uint32_t, int, int) {}
extern "C" void rvtest_check_store(uint32_t addr, int len, uint32_t data) {
  if (g_tohost != 0 && addr == g_tohost && len == 4) {
    write_access(addr, len, data);
  }
}
extern "C" void npc_trap_stub(uint32_t, uint32_t, uint32_t, uint32_t) {}
extern "C" unsigned char semihosting_ebreak_match(uint32_t) { return 0; }
extern "C" void csr_undefine(uint32_t, uint32_t, uint32_t) {}

extern "C" void ebreak(uint32_t pc, uint32_t instr) {
  set_halt(kHaltEbreak, pc, instr);
}

extern "C" void inster_undefine(uint32_t pc, uint32_t instr) {
  set_halt(kHaltIllegalInstruction, pc, instr);
}

extern "C" int npc_mem_halted(void) { return g_halted ? 1 : 0; }
extern "C" uint32_t npc_mem_halt_reason(void) {
  return static_cast<uint32_t>(g_halt_reason);
}
extern "C" int npc_mem_protocol_error(void) {
  return g_protocol_error ? 1 : 0;
}
extern "C" uint32_t npc_mem_halt_pc(void) { return g_halt_pc; }
extern "C" uint32_t npc_mem_halt_instr(void) { return g_halt_instr; }
