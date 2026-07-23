#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace npc_public {

struct BenchmarkMarker {
  uint32_t pc = 0;
  uint32_t instr = 0;
};

struct BenchmarkEpisode {
  uint64_t start_cycle = 0;
  uint64_t start_ordinal = 0;
  uint64_t stop_cycle = 0;
  uint64_t stop_ordinal = 0;
};

class BenchmarkTracker {
 public:
  BenchmarkTracker(BenchmarkMarker start, BenchmarkMarker stop)
      : start_(start), stop_(stop) {}

  bool observe(uint64_t cycle, uint64_t ordinal, uint32_t pc,
               uint32_t instr) {
    if (pc == start_.pc) {
      if (instr != start_.instr) return fail("start marker instruction mismatch");
      if (active_) return fail("start marker repeated before stop marker");
      current_.start_cycle = cycle;
      current_.start_ordinal = ordinal;
      active_ = true;
    }
    if (pc == stop_.pc) {
      if (instr != stop_.instr) return fail("stop marker instruction mismatch");
      if (!active_) return fail("stop marker observed without active start");
      if (cycle < current_.start_cycle || ordinal <= current_.start_ordinal) {
        return fail("benchmark marker interval is not positive");
      }
      current_.stop_cycle = cycle;
      current_.stop_ordinal = ordinal;
      episodes_.push_back(current_);
      current_ = {};
      active_ = false;
    }
    return error_.empty();
  }

  bool finalize() {
    if (!error_.empty()) return false;
    if (active_) return fail("benchmark ended with an open marker interval");
    if (episodes_.empty()) return fail("benchmark completed without markers");
    return true;
  }

  const std::vector<BenchmarkEpisode> &episodes() const { return episodes_; }
  const std::string &error() const { return error_; }

 private:
  bool fail(const char *message) {
    if (error_.empty()) error_ = message;
    return false;
  }

  BenchmarkMarker start_{};
  BenchmarkMarker stop_{};
  BenchmarkEpisode current_{};
  bool active_ = false;
  std::vector<BenchmarkEpisode> episodes_{};
  std::string error_{};
};

}  // namespace npc_public
