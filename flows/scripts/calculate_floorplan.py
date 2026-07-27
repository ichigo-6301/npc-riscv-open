#!/usr/bin/env python3
"""Calculate a site-snapped square Nangate45 register-expanded floorplan."""

import argparse
import json
import math
from pathlib import Path
from typing import List


SITE_WIDTH_UM = 0.19
SITE_HEIGHT_UM = 1.40
MARGIN_X_UM = 20.14
MARGIN_Y_UM = 22.40


def ceil_grid(value: float, grid: float) -> float:
    return math.ceil((value - 1e-12) / grid) * grid


def calculate(dc_area: float, *, utilization: float = 0.30,
              area_margin: float = 1.25) -> dict:
    if dc_area <= 0:
        raise ValueError("DC mapped area must be positive")
    if not 0 < utilization < 1:
        raise ValueError("utilization must be between zero and one")
    if area_margin < 1:
        raise ValueError("area margin must be at least one")
    core_area = dc_area * area_margin / utilization
    nominal_side = math.sqrt(core_area)
    core_width = ceil_grid(nominal_side, SITE_WIDTH_UM)
    core_height = ceil_grid(nominal_side, SITE_HEIGHT_UM)
    core_x0 = MARGIN_X_UM
    core_y0 = MARGIN_Y_UM
    core_x1 = core_x0 + core_width
    core_y1 = core_y0 + core_height
    die_x1 = ceil_grid(core_x1 + MARGIN_X_UM, SITE_WIDTH_UM)
    die_y1 = ceil_grid(core_y1 + MARGIN_Y_UM, SITE_HEIGHT_UM)
    return {
        "dc_mapped_area_um2": dc_area,
        "area_margin": area_margin,
        "planning_utilization": utilization,
        "computed_core_area_um2": core_width * core_height,
        "computed_utilization": dc_area / (core_width * core_height),
        "site_um": [SITE_WIDTH_UM, SITE_HEIGHT_UM],
        "die_area": [0.0, 0.0, die_x1, die_y1],
        "core_area": [core_x0, core_y0, core_x1, core_y1],
        "place_density": 0.55,
    }


def format_box(values: List[float]) -> str:
    return " ".join(f"{value:.3f}" for value in values)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dc-area", required=True, type=float)
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()
    result = calculate(args.dc_area)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print("DIE_AREA=" + format_box(result["die_area"]))
    print("CORE_AREA=" + format_box(result["core_area"]))
    print("PLACE_DENSITY={:.2f}".format(result["place_density"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
