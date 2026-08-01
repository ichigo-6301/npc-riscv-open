#!/usr/bin/env python3
"""Generate and stale-check evidence-bound NPC showcase SVG assets."""

from __future__ import annotations

import argparse
from decimal import Decimal, ROUND_HALF_UP
import hashlib
from html import escape
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


DATA_PATH = "evidence/data/showcase.json"
PROVENANCE_PATH = "evidence/data/showcase_assets.json"
IMPLEMENTATION_SCHEMA = "npc-riscv-open/nangate45-backend-evidence-v1"
SHOWCASE_SCHEMA = "npc-riscv-open/showcase-data-v1"
PROFILE_IDS = (
    "rv32im_single_perf",
    "rv32ima_sv32_linux",
    "rv32im_ooo_4k",
)
POINT_IDS = (
    "rv32im_single_perf.registers",
    "rv32im_single_perf.sram",
    "rv32ima_sv32_linux.registers",
    "rv32ima_sv32_linux.sram",
)
HISTORICAL_EVIDENCE_IDS = (
    "linux_coremark_history_public",
    "linux_boot_history_public",
    "ooo_historical_optimization_public",
    "single_xc7z100_history_public",
)


def read_object(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError("invalid JSON {}: {}".format(path, error)) from error
    if not isinstance(value, dict):
        raise ValueError("{} must contain a JSON object".format(path))
    return value


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def canonical_json(value: dict) -> str:
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=True) + "\n"


def rounded(value: float, digits: int = 1) -> str:
    quantum = Decimal(1).scaleb(-digits)
    result = Decimal(str(value)).quantize(quantum, rounding=ROUND_HALF_UP)
    return format(result, "f")


def bar_width(value: float, maximum: float, width: int) -> int:
    return int(
        (Decimal(str(value)) * Decimal(width) / Decimal(str(maximum))).quantize(
            Decimal("1"), rounding=ROUND_HALF_UP
        )
    )


def validate_xml(name: str, content: str) -> None:
    try:
        root = ET.fromstring(content)
    except ET.ParseError as error:
        raise ValueError("invalid SVG {}: {}".format(name, error)) from error
    if root.attrib.get("viewBox") is None:
        raise ValueError("{} has no viewBox".format(name))
    children = {child.tag.rsplit("}", 1)[-1] for child in root}
    for required in ("title", "desc"):
        if required not in children:
            raise ValueError("{} has no {}".format(name, required))


def validate_data(root: Path, data: dict) -> dict:
    if data.get("schema") != SHOWCASE_SCHEMA:
        raise ValueError("showcase data schema mismatch")
    profiles = data.get("profiles")
    if not isinstance(profiles, list) or tuple(item.get("id") for item in profiles) != PROFILE_IDS:
        raise ValueError("showcase data must contain the ordered three-Profile portfolio")
    points = data.get("closure_points")
    if not isinstance(points, list) or tuple(item.get("id") for item in points) != POINT_IDS:
        raise ValueError("showcase data must contain the ordered four fixed points")
    source = data.get("implementation_evidence")
    if not isinstance(source, dict) or not source.get("path"):
        raise ValueError("showcase data has no implementation evidence source")
    evidence_path = root / str(source["path"])
    evidence = read_object(evidence_path)
    if evidence.get("schema") != IMPLEMENTATION_SCHEMA:
        raise ValueError("implementation evidence schema mismatch")
    actual_hash = sha256_file(evidence_path)
    if source.get("sha256") != actual_hash:
        raise ValueError(
            "implementation evidence SHA256 drift: expected={} actual={}".format(
                source.get("sha256"), actual_hash
            )
        )
    evidence_points = evidence.get("closure_points", {})
    historical = data.get("historical_evidence")
    if not isinstance(historical, list) or tuple(item.get("id") for item in historical) != HISTORICAL_EVIDENCE_IDS:
        raise ValueError("showcase data must contain the ordered historical evidence set")
    for item in historical:
        historical_path = root / str(item.get("path", ""))
        if not historical_path.is_file():
            raise ValueError("historical evidence path missing for {}".format(item.get("id")))
        actual = sha256_file(historical_path)
        if item.get("sha256") != actual:
            raise ValueError("historical evidence SHA256 drift for {}".format(item.get("id")))
    for profile in profiles:
        if not isinstance(profile.get("history_note"), str) or not profile["history_note"]:
            raise ValueError("showcase profile history note missing for {}".format(profile.get("id")))
    for point in points:
        point_id = point["id"]
        evidence_point = evidence_points.get(point_id)
        if not isinstance(evidence_point, dict):
            raise ValueError("implementation evidence lacks {}".format(point_id))
        expected = {
            "dc_mhz": evidence_point.get("frequency", {}).get("dc_mhz"),
            "postroute_mhz": evidence_point.get("frequency", {}).get("postroute_mhz"),
            "standard_cell_area_mm2": evidence_point.get("area", {}).get(
                "standard_cell_area_mm2"
            ),
            "core_area_mm2": evidence_point.get("area", {}).get("core_area_mm2"),
            "macro_count": evidence_point.get("identity", {}).get("macro_count"),
            "claim_ids": evidence_point.get("claim_ids"),
        }
        for field, value in expected.items():
            if point.get(field) != value:
                raise ValueError("showcase drift for {}.{}".format(point_id, field))
    return evidence


def status_style(status: str) -> tuple[str, str, str]:
    if status == "verified_fixed_point":
        return "VERIFIED", "#0f766e", "#ccfbf1"
    if status == "planned":
        return "PLANNED", "#92400e", "#fef3c7"
    raise ValueError("unsupported backend status {}".format(status))


def profile_portfolio_svg(data: dict) -> str:
    cards = []
    x_positions = (42, 414, 786)
    accent_colors = ("#0f766e", "#2563eb", "#c2410c")
    for index, profile in enumerate(data["profiles"]):
        x = x_positions[index]
        accent = accent_colors[index]
        registers_label, registers_fg, registers_bg = status_style(
            profile["backend"]["registers"]
        )
        sram_label, sram_fg, sram_bg = status_style(profile["backend"]["sram"])
        active_note = profile["history_note"]
        cards.append(
            """  <g transform="translate({x} 126)">
    <rect width="330" height="342" rx="6" fill="#ffffff" stroke="#d1d5db"/>
    <rect width="330" height="7" rx="3" fill="{accent}"/>
    <text x="24" y="52" class="card-title">{short_name}</text>
    <text x="24" y="79" class="isa">{isa}</text>
    <text x="24" y="108" class="body">{microarchitecture}</text>
    <line x1="24" y1="130" x2="306" y2="130" class="rule"/>
    <text x="24" y="159" class="meta">CANONICAL TOP</text>
    <text x="306" y="159" text-anchor="end" class="mono">{top}</text>
    <text x="24" y="202" class="row-label">Register-expanded</text>
    <rect x="214" y="180" width="92" height="29" rx="4" fill="{registers_bg}"/>
    <text x="260" y="200" text-anchor="middle" class="status" fill="{registers_fg}">{registers_label}</text>
    <text x="24" y="246" class="row-label">SRAM-macro</text>
    <rect x="214" y="224" width="92" height="29" rx="4" fill="{sram_bg}"/>
    <text x="260" y="244" text-anchor="middle" class="status" fill="{sram_fg}">{sram_label}</text>
    <line x1="24" y1="276" x2="306" y2="276" class="rule"/>
    <text x="24" y="306" class="note">{active_note}</text>
    <text x="24" y="329" class="muted">foundry signoff not claimed</text>
  </g>""".format(
                x=x,
                accent=accent,
                short_name=escape(str(profile["short_name"])),
                isa=escape(str(profile["isa"])),
                microarchitecture=escape(str(profile["microarchitecture"])),
                top=escape(str(profile["top"])),
                registers_label=registers_label,
                registers_fg=registers_fg,
                registers_bg=registers_bg,
                sram_label=sram_label,
                sram_fg=sram_fg,
                sram_bg=sram_bg,
                active_note=escape(active_note),
            )
        )
    return """<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="560" viewBox="0 0 1200 560" role="img" aria-labelledby="title desc">
  <title id="title">NPC RISC-V profile portfolio</title>
  <desc id="desc">Three source-locked CPU profiles and their register-expanded and SRAM-macro backend maturity. Single and Linux have verified fixed-frequency academic points; out-of-order backend work is planned.</desc>
  <style>
    text{{font-family:Arial,sans-serif;letter-spacing:0}} .title{{font-size:32px;font-weight:700;fill:#111827}}
    .subtitle{{font-size:17px;fill:#4b5563}} .card-title{{font-size:27px;font-weight:700;fill:#111827}}
    .isa{{font-size:17px;font-weight:700;fill:#374151}} .body{{font-size:15px;fill:#4b5563}}
    .meta{{font-size:12px;font-weight:700;fill:#6b7280}} .mono{{font:700 14px monospace;fill:#111827}}
    .row-label{{font-size:16px;font-weight:700;fill:#1f2937}} .status{{font-size:12px;font-weight:700}}
    .note{{font-size:15px;font-weight:700;fill:#374151}} .muted{{font-size:14px;fill:#6b7280}}
    .rule{{stroke:#e5e7eb;stroke-width:1}}
  </style>
  <rect width="1200" height="560" fill="#f6f7f8"/>
  <text x="42" y="52" class="title">NPC RISC-V profile portfolio</text>
  <text x="42" y="82" class="subtitle">Three source-locked profiles / two memory bindings / evidence-bound maturity</text>
{cards}
  <rect x="42" y="497" width="1116" height="38" rx="5" fill="#111827"/>
  <text x="600" y="522" text-anchor="middle" font-family="Arial,sans-serif" font-size="14" fill="#f9fafb">Verified means a fixed Nangate45 academic closure point, not Fmax, full electrical closure, foundry signoff, or silicon.</text>
</svg>
""".format(cards="\n".join(cards))


def closure_points_svg(data: dict) -> str:
    rows = []
    frequency_width = 390
    area_width = 300
    for index, point in enumerate(data["closure_points"]):
        y = 164 + index * 114
        dc_width = bar_width(point["dc_mhz"], 650, frequency_width)
        post_width = bar_width(point["postroute_mhz"], 650, frequency_width)
        core_width = bar_width(point["core_area_mm2"], 3.0, area_width)
        cell_width = bar_width(point["standard_cell_area_mm2"], 3.0, area_width)
        core_text_inside = core_width > 180
        memory_note = "{} macros".format(point["macro_count"]) if point["macro_count"] else "0 macros"
        rows.append(
            """  <g transform="translate(0 {y})">
    <line x1="42" y1="-18" x2="1158" y2="-18" class="row-rule"/>
    <text x="42" y="17" class="row-title">{label}</text>
    <text x="42" y="42" class="row-meta">{memory_note}</text>
    <rect x="284" y="-1" width="{frequency_width}" height="15" rx="3" fill="#e5e7eb"/>
    <rect x="284" y="-1" width="{dc_width}" height="15" rx="3" fill="#d97706"/>
    <text x="{dc_text_x}" y="11" class="bar-value">DC {dc_mhz} MHz</text>
    <rect x="284" y="27" width="{frequency_width}" height="15" rx="3" fill="#e5e7eb"/>
    <rect x="284" y="27" width="{post_width}" height="15" rx="3" fill="#0f766e"/>
    <text x="{post_text_x}" y="39" class="bar-value">P&amp;R/PT {postroute_mhz} MHz</text>
    <rect x="800" y="-1" width="{area_width}" height="15" rx="3" fill="#e5e7eb"/>
    <rect x="800" y="-1" width="{core_width}" height="15" rx="3" fill="#475569"/>
    <text x="{core_text_x}" y="11" text-anchor="{core_text_anchor}" class="{core_text_class}">core {core_area} mm2</text>
    <rect x="800" y="27" width="{area_width}" height="15" rx="3" fill="#e5e7eb"/>
    <rect x="800" y="27" width="{cell_width}" height="15" rx="3" fill="#be123c"/>
    <text x="{cell_text_x}" y="39" class="bar-value">std-cell {cell_area} mm2</text>
  </g>""".format(
                y=y,
                label=escape(str(point["label"])),
                memory_note=memory_note,
                frequency_width=frequency_width,
                area_width=area_width,
                dc_width=dc_width,
                post_width=post_width,
                core_width=core_width,
                cell_width=cell_width,
                dc_text_x=292 + min(dc_width, frequency_width - 8),
                post_text_x=292 + min(post_width, frequency_width - 8),
                core_text_x=(800 + core_width - 8) if core_text_inside else (808 + core_width),
                core_text_anchor="end" if core_text_inside else "start",
                core_text_class="bar-value-light" if core_text_inside else "bar-value",
                cell_text_x=808 + min(cell_width, area_width - 8),
                dc_mhz=point["dc_mhz"],
                postroute_mhz=point["postroute_mhz"],
                core_area=rounded(point["core_area_mm2"], 6).rstrip("0").rstrip("."),
                cell_area=rounded(point["standard_cell_area_mm2"], 6).rstrip("0").rstrip("."),
            )
        )
    return """<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="690" viewBox="0 0 1200 690" role="img" aria-labelledby="title desc">
  <title id="title">Nangate45 academic fixed-frequency closure points</title>
  <desc id="desc">Design Compiler and matching post-route PrimeTime frequencies plus core and standard-cell area for Single and Linux register-expanded and SRAM-macro fixed points.</desc>
  <style>
    text{{font-family:Arial,sans-serif;letter-spacing:0}} .title{{font-size:31px;font-weight:700;fill:#111827}}
    .subtitle{{font-size:16px;fill:#4b5563}} .section{{font-size:13px;font-weight:700;fill:#6b7280}}
    .row-title{{font-size:18px;font-weight:700;fill:#111827}} .row-meta{{font-size:14px;fill:#6b7280}}
    .bar-value{{font-size:13px;font-weight:700;fill:#111827}} .bar-value-light{{font-size:13px;font-weight:700;fill:#ffffff}} .row-rule{{stroke:#d1d5db;stroke-width:1}}
    .foot{{font-size:13px;fill:#374151}}
  </style>
  <rect width="1200" height="690" fill="#f8fafc"/>
  <text x="42" y="48" class="title">Nangate45 academic fixed-frequency closure points</text>
  <text x="42" y="76" class="subtitle">Source-matched mapped netlist -> OpenROAD route -> OpenRCX SPEF -> PrimeTime setup/hold</text>
  <rect x="42" y="98" width="1116" height="38" rx="5" fill="#ffffff" stroke="#d1d5db"/>
  <rect x="62" y="111" width="14" height="14" rx="2" fill="#d97706"/><text x="84" y="123" class="section">DC setup-closed</text>
  <rect x="220" y="111" width="14" height="14" rx="2" fill="#0f766e"/><text x="242" y="123" class="section">post-route/PT setup + hold</text>
  <rect x="477" y="111" width="14" height="14" rx="2" fill="#475569"/><text x="499" y="123" class="section">core footprint</text>
  <rect x="644" y="111" width="14" height="14" rx="2" fill="#be123c"/><text x="666" y="123" class="section">standard-cell design area</text>
  <text x="284" y="153" class="section">FREQUENCY / 0-650 MHz</text>
  <text x="800" y="153" class="section">AREA / 0-3.0 mm2</text>
{rows}
  <line x1="42" y1="610" x2="1158" y2="610" class="row-rule"/>
  <text x="42" y="638" class="foot">Fixed points, not Fmax. Route DRC, antenna, and unrouted counts are zero; internal extracted setup/hold passes.</text>
  <text x="42" y="662" class="foot">SRAM uses analytical OpenRAM FreePDK45 TT/1.0 V/25 C views with Nangate45 typical/1.1 V/25 C cells; macro signoff is open.</text>
</svg>
""".format(rows="\n".join(rows))


def expected_assets(data: dict) -> dict[str, str]:
    assets = {
        "docs/assets/profile_portfolio.svg": profile_portfolio_svg(data),
        "docs/assets/nangate45_closure_points.svg": closure_points_svg(data),
    }
    for name, content in assets.items():
        validate_xml(name, content)
    return assets


def provenance(root: Path, data: dict, assets: dict[str, str]) -> dict:
    script = Path(__file__).resolve()
    script_relative = script.relative_to(root).as_posix()
    data_path = root / DATA_PATH
    source = data["implementation_evidence"]
    specs = {item["path"]: item for item in data["assets"]}
    records = []
    for path, content in assets.items():
        spec = specs.get(path)
        if spec is None:
            raise ValueError("showcase asset spec is missing for {}".format(path))
        payload = content.encode("utf-8")
        records.append(
            {
                "id": spec["id"],
                "path": path,
                "type": "generated_svg",
                "sha256": sha256_bytes(payload),
                "size_bytes": len(payload),
                "title": spec["title"],
                "units": spec["units"],
                "configuration": spec["configuration"],
                "claim_ids": spec["claim_ids"],
                "caveat": data["caption_boundary"],
            }
        )
    return {
        "schema": "npc-riscv-open/showcase-asset-provenance-v1",
        "generated_at": data["generated_at"],
        "generator": {
            "path": script_relative,
            "sha256": sha256_file(script),
            "command": "python3 flows/scripts/generate_showcase_assets.py --write",
            "parameters": {
                "mode": "write",
                "asset_count": len(records),
            },
            "tool_versions": {
                "python": data["generator_runtime"],
            },
            "compatibility": data["generator_compatibility"],
        },
        "source_evidence": [
            {
                "id": "npc_showcase_data_public",
                "path": DATA_PATH,
                "sha256": sha256_file(data_path),
            },
            {
                "id": source["id"],
                "path": source["path"],
                "sha256": source["sha256"],
            },
        ] + [
            {
                "id": item["id"],
                "path": item["path"],
                "sha256": item["sha256"],
            }
            for item in data["historical_evidence"]
        ],
        "assets": records,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="public repository or npc/open root",
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true", help="write generated assets")
    mode.add_argument("--check", action="store_true", help="fail on stale assets")
    args = parser.parse_args()

    root = args.root.resolve()
    try:
        data = read_object(root / DATA_PATH)
        validate_data(root, data)
        assets = expected_assets(data)
        expected_provenance = canonical_json(provenance(root, data, assets))
    except ValueError as error:
        print("showcase-assets: {}".format(error), file=sys.stderr)
        return 1

    expected = dict(assets)
    expected[PROVENANCE_PATH] = expected_provenance
    if args.write:
        for relative, content in expected.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
            print("showcase-assets: wrote {}".format(relative))
    else:
        stale = []
        for relative, content in expected.items():
            path = root / relative
            if not path.is_file() or path.read_text(encoding="utf-8") != content:
                stale.append(relative)
        if stale:
            print(
                "showcase-assets: stale or missing: {}".format(", ".join(stale)),
                file=sys.stderr,
            )
            print(
                "run: python3 flows/scripts/generate_showcase_assets.py --write",
                file=sys.stderr,
            )
            return 1
    print("showcase-assets: PASS generated=2 provenance=1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
