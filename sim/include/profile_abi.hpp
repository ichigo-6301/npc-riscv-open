#pragma once

// Stable, profile-neutral ABI constants used by public smoke tooling.  The
// Verilog wrappers expose the same signal names; this header documents the
// packet shape without importing any private NEMU or workbench headers.

#include <cstdint>

namespace npc_public {
inline constexpr uint32_t kProfileAbiVersion = 1;
inline constexpr uint32_t kProfileAbiVersionWithImage = 2;
inline constexpr unsigned kMaxCommitPackets = 2;

enum HaltReason : uint32_t {
  kHaltNone = 0,
  kHaltEbreak = 1,
  kHaltTohostPass = 2,
  kHaltIllegalInstruction = 3,
  kHaltTohostFail = 4,
  kHaltMemoryProtocol = 5,
};

// Optional external-reference adapter ABI.  A shared object passed through
// --difftest-so must export step/fini and either the legacy v1 init or the v2
// image-aware init; the runner refuses a library that merely dlopens
// successfully.  The bundled NEMU adapter uses v2 so it can load the exact
// DUT image and reject profile/reset mismatches.  On a dual-commit cycle, slot
// 0 is reported with architectural_state_valid=0 and slot 1 carries the final
// post-cycle architectural snapshot.
using DifftestInit = int (*)(uint32_t abi_version, const char *profile_id);
// Version 2 passes the exact image and reset address to the adapter.  This is
// intentionally additive: older third-party adapters implementing the v1
// entry point remain loadable, while the bundled NEMU adapter can fail closed
// if it cannot initialize the same image as the DUT.
using DifftestInitWithImage = int (*)(uint32_t abi_version,
                                      const char *profile_id,
                                      const char *image_path,
                                      uint32_t reset_vector);
// For a dual-retire cycle, both calls receive the architectural snapshot after
// the complete cycle; `slot` and `ordinal` preserve packet order so an adapter
// can execute one or two reference instructions before comparing that state.
using DifftestStep = int (*)(uint64_t ordinal, uint32_t slot,
                             uint32_t pc, uint32_t instr, uint32_t next_pc,
                             uint32_t arch_pc, const uint32_t gpr[32],
                             uint32_t architectural_state_valid);
using DifftestFini = void (*)();

inline constexpr const char *kDifftestInitSymbol = "npc_public_difftest_init";
inline constexpr const char *kDifftestInitWithImageSymbol =
    "npc_public_difftest_init_v2";
inline constexpr const char *kDifftestStepSymbol = "npc_public_difftest_step";
inline constexpr const char *kDifftestFiniSymbol = "npc_public_difftest_fini";

struct CommitPacket {
  bool valid = false;
  uint32_t pc = 0;
  uint32_t instr = 0;
  uint32_t next_pc = 0;
};
}  // namespace npc_public
