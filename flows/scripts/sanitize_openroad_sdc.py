#!/usr/bin/env python3
"""Create a PrimeTime-compatible SDC and assert its routed clock period."""

import argparse
import re
from pathlib import Path
from typing import List


def sanitize(input_path: Path, output_path: Path, expected_period_ns: float) -> float:
    kept: List[str] = []
    removed = 0
    for line in input_path.read_text(encoding="ascii").splitlines(keepends=True):
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
    actual_literal = match.group(1)
    actual = float(actual_literal)
    # ORFS write_sdc emits four fractional digits. Accept only the rounding
    # interval implied by that representation, then restore the exact contract
    # period for PrimeTime instead of propagating the rounded value.
    fractional_digits = len(actual_literal.partition(".")[2])
    quantization_tolerance = min(
        5.0e-5 + 1.0e-12,
        0.5 * (10.0 ** -fractional_digits) + 1.0e-12,
    )
    if abs(actual - expected_period_ns) > quantization_tolerance:
        raise SystemExit(
            f"routed SDC period mismatch: expected {expected_period_ns}, got {actual}")
    normalized_clock = re.sub(
        r"(-period\s+)([0-9]+(?:\.[0-9]*)?)",
        rf"\g<1>{expected_period_ns:.9f}",
        clock_lines[0],
        count=1,
    )
    text = text.replace(clock_lines[0], normalized_clock, 1)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(text, encoding="ascii")
    print(
        "ROUTED_SDC_SANITIZE_PASS "
        f"source_period_ns={actual:.9f} normalized_period_ns={expected_period_ns:.9f}"
    )
    return actual


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--expected-period-ns", required=True, type=float)
    args = parser.parse_args()
    sanitize(args.input, args.output, args.expected_period_ns)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
