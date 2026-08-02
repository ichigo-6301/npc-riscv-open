#!/usr/bin/env python3
"""Snap OpenRAM routing geometry to a declared manufacturing grid."""

import argparse
import hashlib
import re
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from typing import Tuple


NUMBER = re.compile(r"(?<![A-Za-z0-9_])[-+]?\d+(?:\.\d+)?(?![A-Za-z0-9_])")
GEOMETRY_KEYWORDS = {"RECT", "POLYGON"}


def snap(value: str, grid: Decimal) -> str:
    number = Decimal(value)
    snapped = (number / grid).quantize(Decimal("1"), rounding=ROUND_HALF_UP) * grid
    rendered = format(snapped.normalize(), "f")
    return "0" if rendered in ("-0", "+0") else rendered


def normalize(text: str, grid: Decimal) -> Tuple[str, int]:
    changed = 0
    output = []
    for line in text.splitlines(keepends=True):
        keyword = line.lstrip().split(None, 1)[0] if line.strip() else ""
        if keyword in GEOMETRY_KEYWORDS:
            updated = NUMBER.sub(lambda match: snap(match.group(0), grid), line)
            changed += int(updated != line)
            line = updated
        output.append(line)
    return "".join(output), changed


def assert_on_grid(text: str, grid: Decimal) -> None:
    for number, line in enumerate(text.splitlines(), 1):
        keyword = line.lstrip().split(None, 1)[0] if line.strip() else ""
        if keyword not in GEOMETRY_KEYWORDS:
            continue
        for match in NUMBER.finditer(line):
            value = Decimal(match.group(0))
            if value % grid != 0:
                raise ValueError(f"line {number} remains off-grid: {value}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--grid-microns", default="0.005")
    args = parser.parse_args()
    grid = Decimal(args.grid_microns)
    if grid <= 0:
        raise SystemExit("grid must be positive")
    normalized, changed = normalize(args.input.read_text(encoding="ascii"), grid)
    assert_on_grid(normalized, grid)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(normalized, encoding="ascii")
    digest = hashlib.sha256(args.output.read_bytes()).hexdigest()
    print("normalized_lef input={} output={} changed_lines={} grid_um={} sha256={}".format(
        args.input, args.output, changed, grid, digest))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
