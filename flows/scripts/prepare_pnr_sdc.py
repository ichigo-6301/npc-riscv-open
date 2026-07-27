#!/usr/bin/env python3
"""Retarget one mapped SDC clock while preserving the DC handoff constraints."""

import argparse
import re
from pathlib import Path


PERIOD_RE = re.compile(r"(?P<prefix>-period\s+)(?P<value>[0-9]+(?:\.[0-9]*)?)")


def retarget(text: str, period_ns: float) -> str:
    clock_lines = [line for line in text.splitlines() if "create_clock" in line]
    if len(clock_lines) != 1:
        raise ValueError(f"expected exactly one create_clock statement, found {len(clock_lines)}")
    if len(PERIOD_RE.findall(clock_lines[0])) != 1:
        raise ValueError("create_clock must contain exactly one numeric -period")
    replacement = PERIOD_RE.sub(
        lambda match: match.group("prefix") + f"{period_ns:.9f}",
        clock_lines[0], count=1,
    )
    lines = text.splitlines(keepends=True)
    replaced = False
    for index, line in enumerate(lines):
        if "create_clock" in line:
            ending = "\n" if line.endswith("\n") else ""
            lines[index] = replacement + ending
            replaced = True
            break
    if not replaced:
        raise ValueError("create_clock replacement failed")
    return "".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--frequency-mhz", required=True, type=float)
    args = parser.parse_args()
    if args.frequency_mhz <= 0:
        raise SystemExit("frequency must be positive")
    result = retarget(args.input.read_text(encoding="ascii"), 1000.0 / args.frequency_mhz)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(result, encoding="ascii")
    print("PNR_SDC_RETARGET_PASS frequency_mhz={} period_ns={:.9f}".format(
        args.frequency_mhz, 1000.0 / args.frequency_mhz))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
