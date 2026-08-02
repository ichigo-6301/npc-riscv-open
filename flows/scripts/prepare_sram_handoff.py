#!/usr/bin/env python3
"""Create an immutable D8 handoff from audited physical and timing views."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys

from normalize_openram_lef import assert_on_grid, normalize
from decimal import Decimal


REQUIRED_SUFFIXES = ("v", "lib", "lef", "gds")
REQUIRED_PINS = {
    "npc_icache_data_1r1w_512x32": (
        "clk0", "csb0", "addr0", "din0", "clk1", "csb1", "addr1", "dout1",
    ),
    "npc_dcache_data_1r1w_512x32_b8": (
        "clk0", "csb0", "wmask0", "addr0", "din0", "clk1", "csb1", "addr1", "dout1",
    ),
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON top level must be an object: {path}")
    return value


def parse_liberty_overrides(values: list[str], macro_names: set[str]) -> dict[str, Path]:
    result = {}
    for value in values:
        name, separator, raw_path = value.partition("=")
        if not separator or not name or not raw_path:
            raise ValueError(f"invalid Liberty override, expected NAME=PATH: {value}")
        if name not in macro_names:
            raise ValueError(f"unknown Liberty override macro: {name}")
        if name in result:
            raise ValueError(f"duplicate Liberty override macro: {name}")
        result[name] = Path(raw_path).expanduser().resolve()
    if set(result) != macro_names:
        missing = ",".join(sorted(macro_names - set(result)))
        raise ValueError(f"Liberty overrides must cover every macro; missing={missing or 'none'}")
    return result


def liberty_numbers(text: str, attribute: str) -> list[float]:
    pattern = rf"\b{re.escape(attribute)}\s*:\s*([0-9.eE+-]+)\s*;"
    return [float(value) for value in re.findall(pattern, text)]


def audit_liberty_override(name: str, path: Path, expected: dict, grid: dict) -> None:
    if not path.is_file() or sha256_file(path) != expected["timing_view_sha256"]:
        raise ValueError(f"{name}: timing Liberty SHA256 mismatch")
    text = path.read_text(encoding="utf-8", errors="replace")
    if re.search(rf"\bcell\s*\(\s*{re.escape(name)}\s*\)", text) is None:
        raise ValueError(f"{name}: timing Liberty cell identity mismatch")
    unit_match = re.search(r'\btime_unit\s*:\s*"([^"]+)"\s*;', text)
    if unit_match is None or unit_match.group(1) != grid["time_unit"]:
        raise ValueError(f"{name}: timing Liberty time unit mismatch")
    voltage = liberty_numbers(text, "nom_voltage")
    temperature = liberty_numbers(text, "nom_temperature")
    if not voltage or abs(voltage[0] - float(grid["voltage_v"])) > 1e-9:
        raise ValueError(f"{name}: timing Liberty voltage mismatch")
    if not temperature or abs(temperature[0] - float(grid["temperature_c"])) > 1e-9:
        raise ValueError(f"{name}: timing Liberty temperature mismatch")
    period_values = [
        float(value)
        for value in re.findall(
            r'timing_type\s*:\s*"minimum_period"\s*;.{0,512}?values\s*\(\s*"([0-9.eE+-]+)',
            text, flags=re.DOTALL)
    ]
    if not period_values or abs(max(period_values) - float(expected["minimum_period_ns"])) > 1e-9:
        raise ValueError(f"{name}: timing Liberty minimum period mismatch")
    capacitance = liberty_numbers(text, "max_capacitance")
    transition = liberty_numbers(text, "max_transition")
    if not capacitance or max(capacitance) + 1e-12 < float(grid["max_capacitance_f"]):
        raise ValueError(f"{name}: timing Liberty capacitance grid is too narrow")
    if not transition or max(transition) + 1e-12 < float(grid["max_transition_ns"]):
        raise ValueError(f"{name}: timing Liberty slew grid is too narrow")


def audit_text_views(name: str, verilog: Path, liberty: Path, lef: Path) -> None:
    texts = {
        "verilog": verilog.read_text(encoding="utf-8", errors="replace"),
        "liberty": liberty.read_text(encoding="utf-8", errors="replace"),
        "lef": lef.read_text(encoding="utf-8", errors="replace"),
    }
    patterns = {
        "verilog": rf"\bmodule\s+{re.escape(name)}\b",
        "liberty": rf"\bcell\s*\(\s*{re.escape(name)}\s*\)",
        "lef": rf"\bMACRO\s+{re.escape(name)}\b",
    }
    for role, pattern in patterns.items():
        if re.search(pattern, texts[role]) is None:
            raise ValueError(f"{name}: {role} cell identity mismatch")
    for pin in REQUIRED_PINS[name]:
        if re.search(rf"\b{re.escape(pin)}\b", texts["verilog"]) is None:
            raise ValueError(f"{name}: Verilog view lacks {pin}")
        if re.search(rf"\b(?:pin|bus)\s*\(\s*{re.escape(pin)}\s*\)", texts["liberty"]) is None:
            raise ValueError(f"{name}: Liberty view lacks {pin}")
        lef_pin = rf"\bPIN\s+{re.escape(pin)}(?:\[|\b)"
        if re.search(lef_pin, texts["lef"]) is None:
            raise ValueError(f"{name}: LEF view lacks {pin}")
    for required in ("time_unit", "setup_rising", "hold_rising", "minimum_period"):
        if required not in texts["liberty"]:
            raise ValueError(f"{name}: Liberty view lacks {required}")


def make_read_only(root: Path) -> None:
    for path in sorted(root.rglob("*"), reverse=True):
        if path.is_file():
            path.chmod(stat.S_IRUSR | stat.S_IRGRP | stat.S_IROTH)
        elif path.is_dir():
            path.chmod(stat.S_IRUSR | stat.S_IXUSR | stat.S_IRGRP | stat.S_IXGRP |
                       stat.S_IROTH | stat.S_IXOTH)
    root.chmod(stat.S_IRUSR | stat.S_IXUSR | stat.S_IRGRP | stat.S_IXGRP |
               stat.S_IROTH | stat.S_IXOTH)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--d6-canonical-root", required=True, type=Path)
    parser.add_argument("--matrix", type=Path)
    parser.add_argument(
        "--liberty-override", action="append", default=[], metavar="NAME=PATH",
        help="audited timing Liberty; all macros must be specified",
    )
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    matrix_path = args.matrix or root / "flows/asic/profiles/register_expanded.json"
    matrix = load_json(matrix_path)
    sram = matrix["memory_modes"]["sram"]
    grid = sram["liberty_override"]
    if not grid.get("analytical_delay"):
        raise ValueError("D8 Liberty override must remain explicitly analytical")
    overrides = parse_liberty_overrides(args.liberty_override, set(sram["macros"]))
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        raise ValueError(f"refusing to overwrite non-empty handoff: {output}")
    output.mkdir(parents=True, exist_ok=True)
    records = {}
    for name, expected in sorted(sram["macros"].items()):
        canonical = (args.d6_canonical_root / name).resolve()
        canonical_manifest = load_json(canonical / "canonical_manifest.json")
        if canonical_manifest.get("macro") != name or not canonical_manifest.get("reproducible"):
            raise ValueError(f"{name}: D6 canonical identity or reproducibility failed")
        views = canonical / "reproducibility/run1/views"
        view_names = canonical_manifest["view_files"]
        original_dir = output / "original" / name
        derived_dir = output / "derived" / name
        original_dir.mkdir(parents=True)
        derived_dir.mkdir(parents=True)
        files = {}
        for suffix in REQUIRED_SUFFIXES:
            source = views / view_names["." + suffix]
            expected_hash = expected["original_view_sha256"][suffix]
            if not source.is_file() or sha256_file(source) != expected_hash:
                raise ValueError(f"{name}: original {suffix} SHA256 mismatch")
            destination = original_dir / source.name
            shutil.copy2(source, destination)
            files[suffix] = {
                "path": destination.relative_to(output).as_posix(),
                "sha256": sha256_file(destination),
                "bytes": destination.stat().st_size,
            }
        canonical_lib = files.pop("lib")
        files["canonical_lib"] = canonical_lib
        timing_source = overrides[name]
        audit_liberty_override(name, timing_source, expected, grid)
        timing_dir = output / "timing" / name
        timing_dir.mkdir(parents=True)
        timing_destination = timing_dir / timing_source.name
        shutil.copy2(timing_source, timing_destination)
        files["lib"] = {
            "path": timing_destination.relative_to(output).as_posix(),
            "sha256": sha256_file(timing_destination),
            "bytes": timing_destination.stat().st_size,
        }
        audit_text_views(name, original_dir / view_names[".v"],
                         timing_destination, original_dir / view_names[".lef"])
        normalized_path = derived_dir / (name + "_grid5nm.lef")
        normalized, changed = normalize(
            (original_dir / view_names[".lef"]).read_text(encoding="ascii"), Decimal("0.005"))
        assert_on_grid(normalized, Decimal("0.005"))
        normalized_path.write_text(normalized, encoding="ascii")
        files["normalized_lef"] = {
            "path": normalized_path.relative_to(output).as_posix(),
            "sha256": sha256_file(normalized_path),
            "bytes": normalized_path.stat().st_size,
            "grid_um": 0.005,
            "changed_lines": changed,
        }
        records[name] = {
            "expected_instances": expected["expected_instances"],
            "geometry_um": [expected["width_um"], expected["height_um"]],
            "minimum_period_ns": expected["minimum_period_ns"],
            "physical_view_source": "d6-canonical",
            "timing_view_source": grid["revision"],
            "files": files,
        }
    manifest = {
        "schema": "npc-riscv-open/d8-sram-handoff-v2",
        "memory_mode": "sram",
        "openram_commit": sram["openram_commit"],
        "characterization": sram["characterization"],
        "liberty_override": grid,
        "generated_pvt": sram["generated_pvt"],
        "standard_cell_pvt": sram["standard_cell_pvt"],
        "macro_count": sram["expected_macro_count"],
        "macros": records,
    }
    manifest_path = output / "handoff_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    sums = []
    for path in sorted(output.rglob("*")):
        if path.is_file() and path.name != "SHA256SUMS":
            sums.append(f"{sha256_file(path)}  {path.relative_to(output).as_posix()}")
    (output / "SHA256SUMS").write_text("\n".join(sums) + "\n", encoding="ascii")
    make_read_only(output)
    print(f"D8_SRAM_HANDOFF_PASS manifest={manifest_path} macros={len(records)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"prepare_sram_handoff: error: {error}", file=sys.stderr)
        raise SystemExit(2)
