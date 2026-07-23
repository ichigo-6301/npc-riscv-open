// Common Verilator harness.  Every public profile wrapper exposes this small
// headless ABI, so the runner does not need profile-specific C++ code.

#include "Vnpc_public_sim_top.h"
#include "benchmark_tracker.hpp"
#include "profile_abi.hpp"
#include "verilated.h"
#if VM_TRACE
#include "verilated_vcd_c.h"
#endif

#include <dlfcn.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <memory>
#include <string>

extern "C" void npc_mem_reset(void);
extern "C" void npc_mem_tick(void);
extern "C" void npc_mem_configure(uint32_t ifetch_latency,
                                    uint32_t lsu_latency,
                                    uint32_t memory_latency);
extern "C" int npc_mem_load(const char *path);
extern "C" int npc_mem_halted(void);
extern "C" uint32_t npc_mem_halt_pc(void);
extern "C" uint32_t npc_mem_halt_instr(void);
extern "C" int npc_mem_halt_reason(void);

namespace {
struct Options {
  std::string profile = "unknown";
  std::string image;
  std::string difftest;
  uint64_t watchdog = 1000000;
  uint64_t reset_cycles = 8;
  uint32_t ifetch_latency = 2;
  uint32_t lsu_latency = 3;
  uint32_t memory_latency = 2;
  bool verbose = false;
  std::string benchmark_name;
  std::string benchmark_variant;
  std::string benchmark_image_sha256;
  std::string benchmark_config_sha256;
  uint64_t benchmark_iterations = 0;
  npc_public::BenchmarkMarker benchmark_start{};
  npc_public::BenchmarkMarker benchmark_stop{};
};

uint32_t env_latency(const char *name, uint32_t fallback) {
  const char *raw = std::getenv(name);
  if (!raw || !*raw) return fallback;
  char *end = nullptr;
  const unsigned long value = std::strtoul(raw, &end, 0);
  return (end && *end == '\0') ? static_cast<uint32_t>(value) : fallback;
}

bool consume_value(int &i, int argc, char **argv, const char *name,
                   std::string *out) {
  const std::string arg(argv[i]);
  const std::string prefix = std::string(name) + "=";
  if (arg.rfind(prefix, 0) == 0) {
    *out = arg.substr(prefix.size());
    return true;
  }
  if (arg == name && i + 1 < argc) {
    *out = argv[++i];
    return true;
  }
  return false;
}

Options parse_options(int argc, char **argv) {
  Options options;
  options.ifetch_latency = env_latency("NPC_PUBLIC_IFETCH_LATENCY", 2);
  options.lsu_latency = env_latency("NPC_PUBLIC_LSU_LATENCY", 3);
  options.memory_latency = env_latency("NPC_PUBLIC_MEM_LATENCY", 2);
  for (int i = 1; i < argc; ++i) {
    std::string value;
    if (consume_value(i, argc, argv, "--profile", &value)) {
      options.profile = value;
    } else if (consume_value(i, argc, argv, "--image", &value)) {
      options.image = value;
    } else if (consume_value(i, argc, argv, "--difftest-so", &value)) {
      options.difftest = value;
    } else if (consume_value(i, argc, argv, "--watchdog", &value)) {
      options.watchdog = std::strtoull(value.c_str(), nullptr, 0);
    } else if (consume_value(i, argc, argv, "--reset-cycles", &value)) {
      options.reset_cycles = std::strtoull(value.c_str(), nullptr, 0);
    } else if (consume_value(i, argc, argv, "--ifetch-latency", &value)) {
      options.ifetch_latency = static_cast<uint32_t>(
          std::strtoul(value.c_str(), nullptr, 0));
    } else if (consume_value(i, argc, argv, "--lsu-latency", &value)) {
      options.lsu_latency = static_cast<uint32_t>(
          std::strtoul(value.c_str(), nullptr, 0));
    } else if (consume_value(i, argc, argv, "--memory-latency", &value)) {
      options.memory_latency = static_cast<uint32_t>(
          std::strtoul(value.c_str(), nullptr, 0));
    } else if (consume_value(i, argc, argv, "--benchmark-name", &value)) {
      options.benchmark_name = value;
    } else if (consume_value(i, argc, argv, "--benchmark-variant", &value)) {
      options.benchmark_variant = value;
    } else if (consume_value(i, argc, argv, "--benchmark-iterations", &value)) {
      options.benchmark_iterations = std::strtoull(value.c_str(), nullptr, 0);
    } else if (consume_value(i, argc, argv, "--benchmark-start-pc", &value)) {
      options.benchmark_start.pc =
          static_cast<uint32_t>(std::strtoul(value.c_str(), nullptr, 0));
    } else if (consume_value(i, argc, argv, "--benchmark-start-instr", &value)) {
      options.benchmark_start.instr =
          static_cast<uint32_t>(std::strtoul(value.c_str(), nullptr, 0));
    } else if (consume_value(i, argc, argv, "--benchmark-stop-pc", &value)) {
      options.benchmark_stop.pc =
          static_cast<uint32_t>(std::strtoul(value.c_str(), nullptr, 0));
    } else if (consume_value(i, argc, argv, "--benchmark-stop-instr", &value)) {
      options.benchmark_stop.instr =
          static_cast<uint32_t>(std::strtoul(value.c_str(), nullptr, 0));
    } else if (consume_value(i, argc, argv, "--benchmark-image-sha256", &value)) {
      options.benchmark_image_sha256 = value;
    } else if (consume_value(i, argc, argv, "--benchmark-config-sha256", &value)) {
      options.benchmark_config_sha256 = value;
    } else if (std::strcmp(argv[i], "--verbose") == 0) {
      options.verbose = true;
    }
  }
  return options;
}

void capture_arch_state(Vnpc_public_sim_top *top, uint32_t *arch_pc,
                        uint32_t gpr[32]) {
  for (uint32_t index = 0; index < 32; ++index) {
    top->debug_arch_idx = index;
    top->eval();
    gpr[index] = top->debug_arch_gpr;
  }
  *arch_pc = top->debug_arch_pc;
  top->debug_arch_idx = 0;
  top->eval();
}

struct Difftest {
  void *handle = nullptr;
  npc_public::DifftestInit init = nullptr;
  npc_public::DifftestInitWithImage init_with_image = nullptr;
  npc_public::DifftestStep step = nullptr;
  npc_public::DifftestFini fini = nullptr;
  bool initialized = false;

  bool open(const std::string &path, const std::string &profile,
            const std::string &image) {
    handle = dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
      std::fprintf(stderr, "public runtime: cannot load difftest '%s': %s\n",
                   path.c_str(), dlerror());
      return false;
    }
    init = reinterpret_cast<npc_public::DifftestInit>(
        dlsym(handle, npc_public::kDifftestInitSymbol));
    init_with_image = reinterpret_cast<npc_public::DifftestInitWithImage>(
        dlsym(handle, npc_public::kDifftestInitWithImageSymbol));
    step = reinterpret_cast<npc_public::DifftestStep>(
        dlsym(handle, npc_public::kDifftestStepSymbol));
    fini = reinterpret_cast<npc_public::DifftestFini>(
        dlsym(handle, npc_public::kDifftestFiniSymbol));
    if ((!init && !init_with_image) || !step || !fini) {
      std::fprintf(stderr,
                   "public runtime: difftest '%s' lacks public ABI symbols "
                   "(%s or %s/%s/%s); refusing load-only execution\n",
                   path.c_str(), npc_public::kDifftestInitSymbol,
                   npc_public::kDifftestInitWithImageSymbol,
                   npc_public::kDifftestStepSymbol,
                   npc_public::kDifftestFiniSymbol);
      close();
      return false;
    }
    const int init_status = init_with_image
                                ? init_with_image(
                                      npc_public::kProfileAbiVersionWithImage,
                                      profile.c_str(), image.c_str(),
                                      0x80000000u)
                                : init(npc_public::kProfileAbiVersion,
                                       profile.c_str());
    if (init_status != 0) {
      std::fprintf(stderr, "public runtime: difftest init rejected profile %s\n",
                   profile.c_str());
      close();
      return false;
    }
    initialized = true;
    return true;
  }

  void close() {
    if (initialized && fini) fini();
    initialized = false;
    fini = nullptr;
    init = nullptr;
    init_with_image = nullptr;
    step = nullptr;
    if (handle) dlclose(handle);
    handle = nullptr;
  }
};
}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  const Options options = parse_options(argc, argv);
  const bool benchmark_enabled = !options.benchmark_name.empty();
  if (benchmark_enabled &&
      (options.benchmark_variant.empty() || options.benchmark_iterations == 0 ||
       options.benchmark_start.pc == 0 || options.benchmark_start.instr == 0 ||
       options.benchmark_stop.pc == 0 || options.benchmark_stop.instr == 0 ||
       options.benchmark_image_sha256.empty() ||
       options.benchmark_config_sha256.empty())) {
    std::fprintf(stderr, "public runtime: incomplete benchmark contract\n");
    return 2;
  }
  std::unique_ptr<npc_public::BenchmarkTracker> benchmark;
  if (benchmark_enabled) {
    benchmark = std::make_unique<npc_public::BenchmarkTracker>(
        options.benchmark_start, options.benchmark_stop);
  }

  Difftest difftest;
  if (!options.difftest.empty() &&
      !difftest.open(options.difftest, options.profile, options.image)) {
    return 2;
  }

  npc_mem_configure(options.ifetch_latency, options.lsu_latency,
                    options.memory_latency);
  npc_mem_reset();
  if (!options.image.empty() && npc_mem_load(options.image.c_str()) != 0) {
    std::fprintf(stderr, "public runtime: failed to load image '%s'\n",
                 options.image.c_str());
    difftest.close();
    return 3;
  }

  auto *top = new Vnpc_public_sim_top;
  top->debug_arch_idx = 0;
  std::ofstream itrace;
  const char *itrace_enabled = std::getenv("NPC_OPEN_ITRACE");
  if (itrace_enabled && std::strcmp(itrace_enabled, "1") == 0) {
    const char *itrace_path = std::getenv("NPC_OPEN_ITRACE_PATH");
    if (!itrace_path || !*itrace_path) {
      std::fprintf(stderr, "public runtime: itrace enabled without output path\n");
      difftest.close();
      delete top;
      return 2;
    }
    itrace.open(itrace_path, std::ios::out | std::ios::trunc);
    if (!itrace) {
      std::fprintf(stderr, "public runtime: cannot open itrace '%s'\n", itrace_path);
      difftest.close();
      delete top;
      return 2;
    }
  }
#if VM_TRACE
  VerilatedVcdC *trace = nullptr;
  const char *trace_path = std::getenv("NPC_PUBLIC_VCD");
  if (trace_path && *trace_path) {
    Verilated::traceEverOn(true);
    trace = new VerilatedVcdC;
    top->trace(trace, 99);
    trace->open(trace_path);
  }
#endif

  top->clk = 0;
  top->rst_n = 0;
  for (uint64_t cycle = 0; cycle < options.reset_cycles; ++cycle) {
    npc_mem_tick();
    top->clk = 0;
    top->eval();
    top->clk = 1;
    top->eval();
#if VM_TRACE
    if (trace) trace->dump(cycle * 2 + 1);
#endif
  }
  top->rst_n = 1;

  uint64_t commits = 0;
  uint64_t commits2 = 0;
  uint64_t difftest_ordinal = 0;
  bool benchmark_observe_ok = true;
  uint64_t cycle = 0;
  for (; cycle < options.watchdog && !Verilated::gotFinish(); ++cycle) {
    npc_mem_tick();
    top->clk = 0;
    top->eval();
#if VM_TRACE
    if (trace) trace->dump((options.reset_cycles + cycle) * 2);
#endif
    top->clk = 1;
    top->eval();
#if VM_TRACE
    if (trace) trace->dump((options.reset_cycles + cycle) * 2 + 1);
#endif

    uint32_t arch_pc = 0;
    uint32_t gpr[32] = {};
    if (difftest.step && (top->commit_valid || top->commit1_valid)) {
      capture_arch_state(top, &arch_pc, gpr);
    }

    if (top->commit_valid) {
      ++commits;
      ++difftest_ordinal;
      if (benchmark && benchmark_observe_ok) {
        benchmark_observe_ok = benchmark->observe(
            cycle, difftest_ordinal, top->commit_pc, top->commit_instr);
      }
      if (difftest.step && difftest.step(difftest_ordinal, 0, top->commit_pc,
                                         top->commit_instr, top->commit_nextpc,
                                         arch_pc, gpr,
                                         top->commit1_valid ? 0u : 1u) != 0) {
        std::fprintf(stderr, "public runtime: difftest mismatch at ordinal %llu slot 0\n",
                     static_cast<unsigned long long>(difftest_ordinal));
        difftest.close();
        delete top;
#if VM_TRACE
        if (trace) {
          trace->close();
          delete trace;
        }
#endif
        return 125;
      }
      if (itrace) {
        itrace << "ordinal=" << difftest_ordinal << " slot=0 pc=0x" << std::hex
               << top->commit_pc << " instr=0x" << top->commit_instr
               << " nextpc=0x" << top->commit_nextpc << std::dec << '\n';
      }
      if (options.verbose)
        std::printf("commit %llu pc=0x%08x instr=0x%08x\n",
                    static_cast<unsigned long long>(commits), top->commit_pc,
                    top->commit_instr);
    }
    if (top->commit1_valid) {
      ++commits2;
      ++difftest_ordinal;
      if (benchmark && benchmark_observe_ok) {
        benchmark_observe_ok = benchmark->observe(
            cycle, difftest_ordinal, top->commit1_pc, top->commit1_instr);
      }
      if (difftest.step && difftest.step(difftest_ordinal, 1,
                                         top->commit1_pc, top->commit1_instr,
                                         top->commit1_nextpc, arch_pc, gpr,
                                         1u) != 0) {
        std::fprintf(stderr, "public runtime: difftest mismatch at slot 1\n");
        difftest.close();
        delete top;
#if VM_TRACE
        if (trace) {
          trace->close();
          delete trace;
        }
#endif
        return 125;
      }
      if (itrace) {
        itrace << "ordinal=" << difftest_ordinal << " slot=1 pc=0x" << std::hex
               << top->commit1_pc << " instr=0x" << top->commit1_instr
               << " nextpc=0x" << top->commit1_nextpc << std::dec << '\n';
      }
    }
    if (top->halt_valid || npc_mem_halted()) break;
  }

  if (cycle >= options.watchdog) {
    std::fprintf(stderr, "public runtime: watchdog expired at %llu cycles\n",
                 static_cast<unsigned long long>(options.watchdog));
    difftest.close();
    delete top;
#if VM_TRACE
    if (trace) {
      trace->close();
      delete trace;
    }
#endif
    return 124;
  }

  const uint32_t halt_pc = npc_mem_halted() ? npc_mem_halt_pc() : top->halt_pc;
  const uint32_t halt_instr =
      npc_mem_halted() ? npc_mem_halt_instr() : top->halt_instr;
  const uint32_t halt_reason = npc_mem_halted()
                                   ? static_cast<uint32_t>(npc_mem_halt_reason())
                                   : top->halt_reason;
  const bool halt_pass = halt_reason == npc_public::kHaltEbreak ||
                         halt_reason == npc_public::kHaltTohostPass;
  std::printf("PUBLIC_SIM_%s cycles=%llu commit=%llu commit2=%llu halt_pc=0x%08x halt_instr=0x%08x halt_reason=%u\n",
              halt_pass ? "PASS" : "FAIL",
              static_cast<unsigned long long>(cycle),
              static_cast<unsigned long long>(commits),
              static_cast<unsigned long long>(commits2),
              halt_pc, halt_instr, halt_reason);

  bool benchmark_pass = true;
  if (benchmark) {
    benchmark_pass = benchmark_observe_ok && benchmark->finalize();
    if (!benchmark_pass) {
      std::fprintf(stderr, "PUBLIC_BENCHMARK_FAIL name=%s reason=%s\n",
                   options.benchmark_name.c_str(), benchmark->error().c_str());
    } else {
      const auto &episodes = benchmark->episodes();
      for (size_t index = 0; index < episodes.size(); ++index) {
        const auto &episode = episodes[index];
        const uint64_t timed_cycles =
            episode.stop_cycle - episode.start_cycle;
        const uint64_t timed_instructions =
            episode.stop_ordinal - episode.start_ordinal;
        std::printf(
            "PUBLIC_BENCHMARK_EPISODE name=%s variant=%s index=%zu selected=%u "
            "start_cycle=%llu start_ordinal=%llu stop_cycle=%llu "
            "stop_ordinal=%llu timed_cycles=%llu timed_instructions=%llu\n",
            options.benchmark_name.c_str(), options.benchmark_variant.c_str(),
            index, index + 1 == episodes.size() ? 1u : 0u,
            static_cast<unsigned long long>(episode.start_cycle),
            static_cast<unsigned long long>(episode.start_ordinal),
            static_cast<unsigned long long>(episode.stop_cycle),
            static_cast<unsigned long long>(episode.stop_ordinal),
            static_cast<unsigned long long>(timed_cycles),
            static_cast<unsigned long long>(timed_instructions));
      }
      const size_t selected = episodes.size() - 1;
      const auto &episode = episodes[selected];
      const uint64_t total_instructions = commits + commits2;
      const uint64_t timed_cycles = episode.stop_cycle - episode.start_cycle;
      const uint64_t timed_instructions =
          episode.stop_ordinal - episode.start_ordinal;
      const uint64_t pre_cycles = episode.start_cycle;
      const uint64_t post_cycles = cycle - episode.stop_cycle;
      const uint64_t pre_instructions = episode.start_ordinal;
      const uint64_t post_instructions =
          total_instructions - episode.stop_ordinal;
      const double timed_cpi =
          static_cast<double>(timed_cycles) / timed_instructions;
      const double whole_cpi =
          static_cast<double>(cycle) / total_instructions;
      const double coremark_per_mhz =
          static_cast<double>(options.benchmark_iterations) * 1000000.0 /
          timed_cycles;
      std::printf(
          "PUBLIC_BENCHMARK name=%s variant=%s selected_episode=%zu episodes=%zu "
          "iterations=%llu whole_cycles=%llu whole_instructions=%llu "
          "whole_cpi=%.9f pre_cycles=%llu pre_instructions=%llu "
          "timed_cycles=%llu timed_instructions=%llu timed_cpi=%.9f "
          "post_cycles=%llu post_instructions=%llu coremark_per_mhz=%.9f "
          "image_sha256=%s config_sha256=%s\n",
          options.benchmark_name.c_str(), options.benchmark_variant.c_str(),
          selected, episodes.size(),
          static_cast<unsigned long long>(options.benchmark_iterations),
          static_cast<unsigned long long>(cycle),
          static_cast<unsigned long long>(total_instructions), whole_cpi,
          static_cast<unsigned long long>(pre_cycles),
          static_cast<unsigned long long>(pre_instructions),
          static_cast<unsigned long long>(timed_cycles),
          static_cast<unsigned long long>(timed_instructions), timed_cpi,
          static_cast<unsigned long long>(post_cycles),
          static_cast<unsigned long long>(post_instructions), coremark_per_mhz,
          options.benchmark_image_sha256.c_str(),
          options.benchmark_config_sha256.c_str());
    }
  }

#if VM_TRACE
  if (trace) {
    trace->close();
    delete trace;
  }
#endif
  difftest.close();
  delete top;
  if (!halt_pass) return 126;
  return benchmark_pass ? 0 : 127;
}
