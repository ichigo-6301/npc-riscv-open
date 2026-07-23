// SPDX-License-Identifier: MIT
//
// Public ABI adapter for a profile-matched NEMU reference.  NEMU itself is
// deliberately not part of this repository (it is Mulan PSL-2.0); this file
// only uses its documented difftest symbol ABI and loads the profile-local raw
// shared object produced by prepare_nemu_difftest.py.

#include "../include/profile_abi.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <filesystem>
#include <fstream>
#include <limits>
#include <string>
#include <unistd.h>

#ifndef NPC_NEMU_PROFILE_ID
#define NPC_NEMU_PROFILE_ID "unknown"
#endif
#ifndef NPC_NEMU_RAW_BASENAME
#define NPC_NEMU_RAW_BASENAME "nemu-ref.so"
#endif
#ifndef NPC_NEMU_SOURCE_COMMIT
#define NPC_NEMU_SOURCE_COMMIT "unknown"
#endif
#ifndef NPC_NEMU_TREE_SHA256
#define NPC_NEMU_TREE_SHA256 "unknown"
#endif
#ifndef NPC_NEMU_ENABLE_A
#define NPC_NEMU_ENABLE_A 0
#endif
#ifndef NPC_NEMU_ENABLE_S
#define NPC_NEMU_ENABLE_S 0
#endif
#ifndef NPC_NEMU_ENABLE_SV32
#define NPC_NEMU_ENABLE_SV32 0
#endif
#ifndef NPC_NEMU_DEBUG_SENTINEL
#define NPC_NEMU_DEBUG_SENTINEL 0
#endif

namespace {

constexpr uint32_t kToDut = 0;
constexpr uint32_t kToRef = 1;
constexpr uint32_t kResetVector = 0x80000000u;
constexpr uint32_t kPmemLimit = 0x90000000u;
constexpr uint32_t kEbreak = 0x00100073u;
constexpr size_t kOpaqueCpuStateBytes = 4096;
constexpr uint32_t kAxiTimerBase = 0xa0000000u;
constexpr uint32_t kAxiTimerSize = 0x20u;
constexpr uint32_t kRtcBase = 0xa0000048u;
constexpr uint32_t kRtcSize = 8u;
constexpr uint32_t kSerialBase = 0xa00003f8u;
constexpr uint32_t kSerialSize = 4u;
constexpr uint32_t kUartLiteBase = 0xa0010000u;
constexpr uint32_t kUartLiteSize = 0x10u;

using RefMemcpy = void (*)(uint32_t, void *, size_t, bool);
using RefRegcpy = void (*)(void *, bool);
using RefExec = void (*)(uint64_t);
using RefInit = void (*)(int);

struct Reference {
  void *handle = nullptr;
  RefMemcpy memcpy = nullptr;
  RefRegcpy regcpy = nullptr;
  RefExec exec = nullptr;
  RefInit init = nullptr;
  std::array<uint8_t, kOpaqueCpuStateBytes> state{};
  bool ready = false;
  uint64_t next_ordinal = 1;
  bool slot0_pending = false;
  // The frozen OoO debug shadow deliberately seeds registers with their index
  // as a bring-up sentinel.  The reference must start from the same state:
  // software may legally observe an otherwise unspecified reset value before
  // writing that register, so merely suppressing comparisons is insufficient.
  std::array<bool, 32> initialized{};
  std::filesystem::path module_dir;
  std::string image_path;
  uint64_t mmio_skips = 0;
};

Reference g_ref;

bool instruction_writes_rd(uint32_t instr, uint32_t *rd_out) {
  const uint32_t opcode = instr & 0x7fu;
  const uint32_t rd = (instr >> 7) & 0x1fu;
  bool writes = false;
  switch (opcode) {
    case 0x03u:  // loads
    case 0x13u:  // OP-IMM
    case 0x17u:  // AUIPC
    case 0x33u:  // OP / M extension
    case 0x37u:  // LUI
    case 0x67u:  // JALR
    case 0x6fu:  // JAL
    case 0x73u:  // CSR reads/writes (rd is still architectural output)
    case 0x2fu:  // A extension
      writes = opcode != 0x73u || ((instr >> 12) & 0x7u) != 0;
      break;
    default:
      break;
  }
  if (writes && rd != 0 && rd_out) *rd_out = rd;
  return writes && rd != 0;
}

template <typename T>
T symbol(void *handle, const char *name) {
  return reinterpret_cast<T>(dlsym(handle, name));
}

void report(const char *kind, const std::string &detail) {
  std::fprintf(stderr, "public NEMU difftest: %s: %s\n", kind,
               detail.c_str());
}

bool valid_range(uint32_t address, size_t length) {
  const uint64_t begin = address;
  const uint64_t end = begin + length;
  return begin >= kResetVector && end <= kPmemLimit && end >= begin;
}

uint32_t state_word(size_t index) {
  uint32_t value = 0;
  const size_t offset = index * sizeof(value);
  if (offset + sizeof(value) > g_ref.state.size()) return 0;
  std::memcpy(&value, g_ref.state.data() + offset, sizeof(value));
  return value;
}

void set_state_word(size_t index, uint32_t value) {
  const size_t offset = index * sizeof(value);
  if (offset + sizeof(value) <= g_ref.state.size()) {
    std::memcpy(g_ref.state.data() + offset, &value, sizeof(value));
  }
}

int32_t sign_extend_12(uint32_t value) {
  return static_cast<int32_t>(value << 20) >> 20;
}

bool known_mmio_address(uint32_t address) {
  const auto in_range = [address](uint32_t base, uint32_t size) {
    return address >= base && address < base + size;
  };
  return in_range(kAxiTimerBase, kAxiTimerSize) ||
         in_range(kRtcBase, kRtcSize) ||
         in_range(kSerialBase, kSerialSize) ||
         in_range(kUartLiteBase, kUartLiteSize);
}

bool decode_known_mmio(uint32_t instr, uint32_t *address) {
  const uint32_t opcode = instr & 0x7fu;
  const uint32_t rs1 = (instr >> 15) & 0x1fu;
  int32_t immediate = 0;
  if (opcode == 0x03u) {
    immediate = static_cast<int32_t>(instr) >> 20;
  } else if (opcode == 0x23u) {
    const uint32_t raw = ((instr >> 7) & 0x1fu) |
                         (((instr >> 25) & 0x7fu) << 5);
    immediate = sign_extend_12(raw);
  } else {
    return false;
  }
  const uint32_t effective = state_word(rs1) + static_cast<uint32_t>(immediate);
  if (!known_mmio_address(effective)) return false;
  if (address) *address = effective;
  return true;
}

bool single_issue_profile() {
  const std::string profile(NPC_NEMU_PROFILE_ID);
  return profile == "rv32im_single_perf" || profile == "rv32ima_sv32_linux";
}

void sync_reference_from_dut(uint32_t next_pc, const uint32_t gpr[32]) {
  for (size_t i = 0; i < 32; ++i) set_state_word(i, gpr[i]);
  set_state_word(32, next_pc);
  g_ref.regcpy(g_ref.state.data(), kToRef != 0);
}

bool load_word(uint32_t address, uint32_t word) {
  if (!valid_range(address, sizeof(word))) {
    report("image", "word is outside the public PMEM range");
    return false;
  }
  // The public runtime and the supported host ABI are little-endian, as is
  // RV32 NEMU.  Passing the word object preserves the exact byte order.
  g_ref.memcpy(address, &word, sizeof(word), true);
  return true;
}

bool load_image(const std::string &path) {
  if (path.empty()) {
    report("init", "image path is empty");
    return false;
  }
  const std::filesystem::path image(path);
  std::ifstream probe(image, std::ios::binary);
  if (!probe) {
    report("image", "cannot open " + image.string());
    return false;
  }
  const std::string suffix = image.extension().string();
  if (suffix == ".hex" || suffix == ".mem") {
    probe.close();
    std::ifstream text(image);
    std::string token;
    uint32_t address = kResetVector;
    while (text >> token) {
      if (token.empty()) continue;
      if (token[0] == '#') {
        std::string ignored;
        std::getline(text, ignored);
        continue;
      }
      if (token[0] == '@') {
        char *end = nullptr;
        const unsigned long parsed = std::strtoul(token.c_str() + 1, &end, 16);
        if (end == token.c_str() + 1 || *end != '\0' || parsed > 0xfffffffful) {
          report("image", "invalid @ address " + token);
          return false;
        }
        address = static_cast<uint32_t>(parsed);
        continue;
      }
      char *end = nullptr;
      const unsigned long parsed = std::strtoul(token.c_str(), &end, 16);
      if (end == token.c_str() || *end != '\0' || parsed > 0xfffffffful) {
        report("image", "invalid hex word " + token);
        return false;
      }
      if (!load_word(address, static_cast<uint32_t>(parsed))) return false;
      if (address > std::numeric_limits<uint32_t>::max() - 4u) return false;
      address += 4u;
    }
    return true;
  }

  uint32_t address = kResetVector;
  std::array<uint8_t, 4096> buffer{};
  while (probe) {
    probe.read(reinterpret_cast<char *>(buffer.data()), buffer.size());
    const std::streamsize count = probe.gcount();
    if (count <= 0) break;
    if (!valid_range(address, static_cast<size_t>(count))) {
      report("image", "binary image exceeds public PMEM range");
      return false;
    }
    g_ref.memcpy(address, buffer.data(), static_cast<size_t>(count), true);
    if (address > std::numeric_limits<uint32_t>::max() -
                      static_cast<uint32_t>(count)) {
      return false;
    }
    address += static_cast<uint32_t>(count);
  }
  return true;
}

bool compare_state(uint32_t arch_pc, const uint32_t gpr[32], uint32_t next_pc,
                   bool compare_arch_state) {
  const uint32_t ref_pc = state_word(32);
  if (ref_pc != next_pc) {
    std::fprintf(stderr,
                 "public NEMU difftest: PC mismatch ref=0x%08x dut_next=0x%08x\n",
                 ref_pc, next_pc);
    return false;
  }
  if (!compare_arch_state) return true;
  if (arch_pc != ref_pc) {
    std::fprintf(stderr,
                 "public NEMU difftest: architectural PC mismatch ref=0x%08x "
                 "dut=0x%08x\n",
                 ref_pc, arch_pc);
    return false;
  }
  for (size_t i = 0; i < 32; ++i) {
    if (!g_ref.initialized[i]) continue;
    const uint32_t ref_value = state_word(i);
    if (ref_value != gpr[i]) {
      std::fprintf(stderr,
                   "public NEMU difftest: GPR mismatch x%zu ref=0x%08x "
                   "dut=0x%08x\n",
                   i, ref_value, gpr[i]);
      return false;
    }
  }
  return true;
}

bool step_reference(uint64_t ordinal, uint32_t slot, uint32_t pc,
                    uint32_t instr, uint32_t next_pc, uint32_t arch_pc,
                    const uint32_t gpr[32], bool architectural_state_valid) {
  if (!g_ref.ready || !g_ref.memcpy || !g_ref.regcpy || !g_ref.exec) {
    report("step", "reference is not initialized");
    return false;
  }
  if (ordinal != g_ref.next_ordinal || slot > 1) {
    report("step", "non-contiguous commit ordinal or invalid slot");
    return false;
  }
  if (slot == 0) g_ref.slot0_pending = true;
  if (slot == 1 && !g_ref.slot0_pending) {
    report("step", "slot 1 arrived without slot 0");
    return false;
  }
  ++g_ref.next_ordinal;

  const uint32_t ref_pc_before = state_word(32);
  const bool debug = std::getenv("NPC_NEMU_DIFFTEST_DEBUG") != nullptr;
  if (debug) {
    std::fprintf(stderr,
                 "[nemu-difftest] pre ordinal=%llu slot=%u pc=0x%08x "
                 "instr=0x%08x next=0x%08x refpc=0x%08x refx1=0x%08x "
                 "dutx1=0x%08x\n",
                 static_cast<unsigned long long>(ordinal), slot, pc, instr,
                 next_pc, ref_pc_before, state_word(1), gpr[1]);
  }
  if (ref_pc_before != pc) {
    std::fprintf(stderr,
                 "public NEMU difftest: pre-step PC mismatch ordinal=%llu "
                 "ref=0x%08x dut=0x%08x\n",
                 static_cast<unsigned long long>(ordinal), ref_pc_before, pc);
    return false;
  }

  uint32_t ref_instr = 0;
  if (!valid_range(pc, sizeof(ref_instr))) {
    report("step", "commit PC is outside public PMEM");
    return false;
  }
  g_ref.memcpy(pc, &ref_instr, sizeof(ref_instr), false);
  if (ref_instr != instr) {
    std::fprintf(stderr,
                 "public NEMU difftest: instruction mismatch ordinal=%llu "
                 "pc=0x%08x ref=0x%08x dut=0x%08x\n",
                 static_cast<unsigned long long>(ordinal), pc, ref_instr,
                 instr);
    return false;
  }

  // Public profiles terminate on a committed ebreak.  The NEMU references
  // are configured for architectural ebreak traps, while the public wrapper
  // intentionally has no trap image; treating this terminal packet as an
  // exit event keeps the comparison precise without inventing a trap handler.
  if (instr == kEbreak) {
    if (slot == 1) g_ref.slot0_pending = false;
    return true;
  }

  uint32_t mmio_address = 0;
  if (single_issue_profile() && decode_known_mmio(instr, &mmio_address)) {
    if (slot != 0 || !architectural_state_valid) {
      report("mmio", "known MMIO commit lacks an unambiguous architectural state");
      return false;
    }
    sync_reference_from_dut(next_pc, gpr);
    ++g_ref.mmio_skips;
    g_ref.slot0_pending = false;
    if (debug) {
      std::fprintf(stderr,
                   "[nemu-difftest] mmio-skip ordinal=%llu pc=0x%08x "
                   "addr=0x%08x\n",
                   static_cast<unsigned long long>(ordinal), pc, mmio_address);
    }
    return true;
  }

  g_ref.exec(1);
  g_ref.state.fill(0);
  g_ref.regcpy(g_ref.state.data(), false);
  if (debug) {
    std::fprintf(stderr,
                 "[nemu-difftest] post ordinal=%llu refpc=0x%08x "
                 "refx1=0x%08x refx16=0x%08x dutpc=0x%08x dutx1=0x%08x "
                 "dutx16=0x%08x\n",
                 static_cast<unsigned long long>(ordinal), state_word(32),
                 state_word(1), state_word(16), arch_pc, gpr[1], gpr[16]);
  }
  uint32_t rd = 0;
  (void)instruction_writes_rd(instr, &rd);
  if (rd != 0) g_ref.initialized[rd] = true;
  const bool ok = compare_state(arch_pc, gpr, next_pc,
                                architectural_state_valid);
  if (slot == 1) g_ref.slot0_pending = false;
  return ok;
}

std::filesystem::path module_directory() {
  Dl_info info{};
  if (dladdr(reinterpret_cast<void *>(&module_directory), &info) == 0 ||
      !info.dli_fname) {
    return {};
  }
  return std::filesystem::absolute(info.dli_fname).parent_path();
}

void close_reference() {
  if (g_ref.ready) {
    std::printf("PUBLIC_DIFFTEST_SUMMARY profile=%s mmio_skips=%llu\n",
                NPC_NEMU_PROFILE_ID,
                static_cast<unsigned long long>(g_ref.mmio_skips));
  }
  g_ref.ready = false;
  if (g_ref.handle) dlclose(g_ref.handle);
  g_ref = Reference{};
}

int initialize(uint32_t abi_version, const char *profile_id,
               const char *image_path, uint32_t reset_vector) {
  if (abi_version != npc_public::kProfileAbiVersionWithImage ||
      !profile_id || std::string(profile_id) != NPC_NEMU_PROFILE_ID) {
    report("init", "ABI/profile identity rejected");
    return 1;
  }
  if (reset_vector != kResetVector || !image_path || !*image_path) {
    report("init", "reset vector or image is not supported");
    return 1;
  }

  g_ref.module_dir = module_directory();
  if (g_ref.module_dir.empty()) {
    report("init", "cannot locate adapter module directory");
    return 1;
  }
  const std::filesystem::path raw =
      g_ref.module_dir / NPC_NEMU_RAW_BASENAME;
  if (!std::filesystem::is_regular_file(raw)) {
    report("init", "profile-local raw NEMU is missing: " + raw.string());
    return 1;
  }

  setenv("NEMU_TOHOST_ENABLE", "0", 1);
  setenv("NEMU_RISCV_A_EXT", NPC_NEMU_ENABLE_A ? "1" : "0", 1);
  setenv("NEMU_RISCV_S_EXT", NPC_NEMU_ENABLE_S ? "1" : "0", 1);
  setenv("NEMU_RISCV_SV32", NPC_NEMU_ENABLE_SV32 ? "1" : "0", 1);

  g_ref.handle = dlopen(raw.c_str(), RTLD_NOW | RTLD_LOCAL);
  if (!g_ref.handle) {
    report("init", "cannot load raw NEMU: " + std::string(dlerror()));
    close_reference();
    return 1;
  }
  g_ref.memcpy = symbol<RefMemcpy>(g_ref.handle, "difftest_memcpy");
  g_ref.regcpy = symbol<RefRegcpy>(g_ref.handle, "difftest_regcpy");
  g_ref.exec = symbol<RefExec>(g_ref.handle, "difftest_exec");
  g_ref.init = symbol<RefInit>(g_ref.handle, "difftest_init");
  if (!g_ref.memcpy || !g_ref.regcpy || !g_ref.exec || !g_ref.init) {
    report("init", "raw NEMU lacks one or more standard difftest symbols");
    close_reference();
    return 1;
  }

  char old_cwd[4096] = {};
  const bool have_cwd = getcwd(old_cwd, sizeof(old_cwd)) != nullptr;
  if (chdir(g_ref.module_dir.c_str()) != 0) {
    report("init", "cannot enter profile-local runtime directory");
    close_reference();
    return 1;
  }
  g_ref.init(0);
  if (have_cwd && chdir(old_cwd) != 0) {
    report("init", "warning: could not restore caller working directory");
  }
  // Older NEMU revisions touch an empty mtrace.log during init even when
  // CONFIG_MTRACE is disabled.  Remove that compatibility artifact so a
  // strict run does not accumulate trace files.
  std::error_code remove_error;
  std::filesystem::remove(g_ref.module_dir / "mtrace.log", remove_error);
  std::filesystem::remove(g_ref.module_dir / "dtrace.log", remove_error);

  g_ref.state.fill(0);
  g_ref.regcpy(g_ref.state.data(), false);
  if (NPC_NEMU_DEBUG_SENTINEL) {
    for (size_t index = 1; index < 32; ++index) {
      set_state_word(index, static_cast<uint32_t>(index));
    }
    set_state_word(32, kResetVector);
    g_ref.regcpy(g_ref.state.data(), kToRef != 0);
  }
  g_ref.initialized.fill(true);
  if (state_word(32) != kResetVector) {
    report("init", "raw NEMU reset PC does not match 0x80000000");
    close_reference();
    return 1;
  }
  g_ref.image_path = image_path;
  if (!load_image(g_ref.image_path)) {
    close_reference();
    return 1;
  }
  g_ref.ready = true;
  return 0;
}

}  // namespace

extern "C" __attribute__((visibility("default"))) int
npc_public_difftest_init_v2(uint32_t abi_version, const char *profile_id,
                            const char *image_path, uint32_t reset_vector) {
  close_reference();
  return initialize(abi_version, profile_id, image_path, reset_vector);
}

extern "C" __attribute__((visibility("default"))) int
npc_public_difftest_init(uint32_t, const char *) {
  // A v1 caller has no image hand-off and cannot be made strict.  Refuse it
  // rather than silently comparing a reference loaded with the wrong image.
  report("init", "v1 ABI has no image hand-off; use the v2 entry point");
  return 1;
}

extern "C" __attribute__((visibility("default"))) int
npc_public_difftest_step(uint64_t ordinal, uint32_t slot, uint32_t pc,
                         uint32_t instr, uint32_t next_pc, uint32_t arch_pc,
                         const uint32_t gpr[32],
                         uint32_t architectural_state_valid) {
  return step_reference(ordinal, slot, pc, instr, next_pc, arch_pc, gpr,
                        architectural_state_valid != 0)
             ? 0
             : 1;
}

extern "C" __attribute__((visibility("default"))) void
npc_public_difftest_fini() {
  close_reference();
}
