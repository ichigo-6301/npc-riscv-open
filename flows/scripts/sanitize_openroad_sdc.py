#!/usr/bin/env python3
"""Create a PrimeTime-compatible SDC and assert its routed clock period."""

import argparse
import re
from pathlib import Path
from typing import List


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--expected-period-ns", required=True, type=float)
    args = parser.parse_args()
    kept: List[str] = []
    removed = 0
    for line in args.input.read_text(encoding="ascii").splitlines(keepends=True):
        if line.strip().startswith("current_design "):
            removed += 1
            continue
        kept.append(line)
    if removed != 1:
        raise SystemExit(f"expected one OpenROAD current_design statement, found {removed}")
    text = "".join(kept)
    clock_lines = [line for line in text.splitlines() if "create_clock" in line]
    if len(clock_lines) != 1:
        raise SystemExit(f"expected one routed create_clock statement, found {len(clock_lines)}")
    match = re.search(r"-period\s+([0-9]+(?:\.[0-9]*)?)", clock_lines[0])
    if match is None:
        raise SystemExit("routed create_clock lacks a numeric period")
    actual = float(match.group(1))
    if abs(actual - args.expected_period_ns) > 1e-5:
        raise SystemExit(
            f"routed SDC period mismatch: expected {args.expected_period_ns}, got {actual}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(text, encoding="ascii")
    print(f"ROUTED_SDC_SANITIZE_PASS period_ns={actual:.9f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
