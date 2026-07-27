#!/usr/bin/env python3
"""Fail-closed controller for the D7 register-expanded ASIC flow."""

import argparse
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
from typing import Dict, Iterable, List, Optional, Tuple

from calculate_floorplan import calculate, format_box
from compare_a3_dc import run as compare_a3_dc
from prepare_pnr_sdc import retarget
from summarize_dc import parse_run
from summarize_pnr import parse_run as parse_pnr_run
from summarize_sta import parse_run as parse_sta_run


PROFILES = ("rv32im_single_perf", "rv32ima_sv32_linux", "rv32im_ooo_4k")
MANIFEST_REL = Path("flows/asic/profiles/register_expanded.json")
SOURCE_MANIFEST_REL = Path("provenance/source_allowlist.json")
CONFIG_PROFILE_SYMBOLS = {
    "CONFIG_NPC_PROFILE_RV32IM_SINGLE_PERF": "rv32im_single_perf",
    "CONFIG_NPC_PROFILE_RV32IMA_SV32_LINUX": "rv32ima_sv32_linux",
    "CONFIG_NPC_PROFILE_RV32IM_OOO_4K": "rv32im_ooo_4k",
}
FORBIDDEN_DEFINES = ("NPC_USE_DPI", "NPC_DPI_")


class AsicError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_json(value: object) -> str:
    return hashlib.sha256(
        (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()
    ).hexdigest()


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise AsicError(f"invalid JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise AsicError(f"JSON top level must be an object: {path}")
    return value


def parse_config(path: Path) -> Dict[str, str]:
    if not path.is_file():
        raise AsicError(f"missing {path}; select an ASIC defconfig first")
    values: Dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("# CONFIG_") and line.endswith(" is not set"):
            values[line[2:-11]] = "n"
        elif line.startswith("CONFIG_") and "=" in line:
            key, value = line.split("=", 1)
            values[key] = value.strip().strip('"')
    return values


def selected_profile(config: Dict[str, str]) -> str:
    selected = [profile for symbol, profile in CONFIG_PROFILE_SYMBOLS.items()
                if config.get(symbol) == "y"]
    if len(selected) != 1:
        raise AsicError(f"expected exactly one selected Profile, found {selected}")
    if config.get("CONFIG_NPC_PROFILE_ID") != selected[0]:
        raise AsicError("CONFIG_NPC_PROFILE_ID disagrees with the selected Profile")
    if config.get("CONFIG_NPC_ASIC_REGISTER_EXPANDED") != "y":
        raise AsicError("select a checked-in *_asic_defconfig before running ASIC stages")
    return selected[0]


def source_record(root: Path, profile: str) -> dict:
    manifest = load_json(root / SOURCE_MANIFEST_REL)
    records = [record for record in manifest.get("profiles", [])
               if isinstance(record, dict) and record.get("profile_id") == profile]
    if len(records) != 1:
        raise AsicError(f"source allowlist must contain one {profile} record")
    return records[0]


def safe_root_path(root: Path, relative: str) -> Path:
    path = (root / relative).resolve()
    try:
        path.relative_to(root)
    except ValueError as error:
        raise AsicError(f"path escapes public root: {relative}") from error
    return path


def read_filelist(root: Path, path: Path) -> Tuple[List[str], List[str], List[Path]]:
    includes: List[str] = []
    defines: List[str] = []
    sources: List[Path] = []
    if not path.is_file():
        raise AsicError(f"missing ASIC filelist: {path}")
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("//", 1)[0].strip()
        if not line:
            continue
        if line.startswith("+incdir+"):
            for item in line[len("+incdir+"):].split("+"):
                directory = safe_root_path(root, item)
                if not directory.is_dir():
                    raise AsicError(f"missing ASIC include directory: {item}")
                includes.append(item)
        elif line.startswith("+define+"):
            defines.append(line[len("+define+"):])
        elif line.startswith("+"):
            raise AsicError(f"unsupported ASIC filelist directive: {line}")
        else:
            source = safe_root_path(root, line)
            if not source.is_file():
                raise AsicError(f"missing ASIC source: {line}")
            sources.append(source)
    if not sources:
        raise AsicError("ASIC filelist contains no RTL")
    return includes, defines, sources


def resolve_mode(profile: str, source_commit: str, profile_data: dict,
                 requested: str) -> Tuple[str, Optional[Path]]:
    if profile != "rv32im_ooo_4k":
        if requested not in ("auto", "default"):
            raise AsicError(f"--ooo-mode is invalid for {profile}")
        expected = str(profile_data.get("source_commit", ""))
        if source_commit != expected:
            raise AsicError(f"source lock drift for {profile}: {source_commit} != {expected}")
        return "default", None
    variants = profile_data.get("source_variants", {})
    variant = variants.get(source_commit) if isinstance(variants, dict) else None
    if not isinstance(variant, dict):
        raise AsicError(f"unsupported OoO source commit for D7: {source_commit}")
    mode = str(variant.get("default_mode")) if requested == "auto" else requested
    allowed = variant.get("allowed_modes", [])
    if mode not in allowed:
        raise AsicError(f"OoO mode {mode} is not allowed for source {source_commit}")
    parameter_files = profile_data.get("elaboration_parameter_files", {})
    relative = parameter_files.get(mode) if isinstance(parameter_files, dict) else None
    if not relative:
        raise AsicError(f"missing parameter lock for OoO mode {mode}")
    return mode, Path(str(relative))


def check_parameter_lock(path: Path, mode: str) -> None:
    text = path.read_text(encoding="utf-8")
    if mode == "legacy":
        for required in ("TARGET_LINE_ENTRY_COUNT=512", "TARGET_LINE_WAY_COUNT=1",
                         "DATA_LINE_COUNT=1024", "DATA_LINE_WAY_COUNT=1"):
            if required not in text:
                raise AsicError(f"OoO production parameter lock lacks {required}")
    elif mode in ("a3_split_off", "a3"):
        if "rv32im_ooo_4k_legacy.tcl" not in text:
            raise AsicError(f"{mode} must inherit the complete legacy parameter lock")
        expected = {
            "a3_split_off": ("STABLE_ENTRY_IQ_ENABLE=0", "IQ_SPLIT_PAYLOAD_READ_ENABLE=0",
                             "ROB_INDEXED_SERVICE_LEVEL=0"),
            "a3": ("STABLE_ENTRY_IQ_ENABLE=1", "IQ_SPLIT_PAYLOAD_READ_ENABLE=1",
                   "ROB_INDEXED_SERVICE_LEVEL=1"),
        }[mode]
        for required in expected:
            if required not in text:
                raise AsicError(f"{mode} parameter lock lacks {required}")


def build_contract(root: Path, config_path: Path, requested_mode: str) -> dict:
    config = parse_config(config_path)
    profile = selected_profile(config)
    matrix = load_json(root / MANIFEST_REL)
    if matrix.get("schema") != "npc-riscv-open/asic-register-expanded-v1":
        raise AsicError("ASIC matrix schema mismatch")
    profile_data = matrix.get("profiles", {}).get(profile)
    if not isinstance(profile_data, dict):
        raise AsicError(f"ASIC matrix lacks {profile}")
    source = source_record(root, profile)
    source_commit = str(source.get("source_commit", ""))
    if re.fullmatch(r"[0-9a-f]{40}", source_commit) is None:
        raise AsicError("source allowlist has no fixed commit")
    mode, parameter_relative = resolve_mode(
        profile, source_commit, profile_data, requested_mode.replace("-", "_"))
    filelist = safe_root_path(root, str(profile_data["filelist"]))
    includes, defines, sources = read_filelist(root, filelist)
    if "NPC_ASIC" not in defines:
        raise AsicError("ASIC filelist must define NPC_ASIC")
    forbidden = [define for define in defines
                 if any(define == prefix or define.startswith(prefix) for prefix in FORBIDDEN_DEFINES)]
    if forbidden:
        raise AsicError("DPI defines are forbidden in ASIC filelists: " + ",".join(forbidden))
    if any("wrappers/" in path.as_posix() for path in sources):
        raise AsicError("simulation wrapper leaked into ASIC filelist")
    top = str(profile_data["top"])
    top_pattern = re.compile(r"\bmodule\s+" + re.escape(top) + r"\b")
    top_sources = [path for path in sources if top_pattern.search(path.read_text(errors="ignore"))]
    if len(top_sources) != 1:
        raise AsicError(f"ASIC source set must declare top {top} exactly once")
    top_text = top_sources[0].read_text(encoding="utf-8", errors="replace")
    expected_ports = {
        "rv32im_single_perf": ("ibus_axi_araddr", "ibus_axi_rdata", "dbus_axi_awaddr", "dbus_axi_rdata"),
        "rv32ima_sv32_linux": ("ibus_axi_araddr", "ibus_axi_rdata", "dbus_axi_awaddr", "dbus_axi_rdata"),
        "rv32im_ooo_4k": ("if_req_valid_o", "if_rsp_valid_i", "fetch_pte_req_valid_o",
                           "mem_req_valid_o", "mem_rsp_valid_i"),
    }[profile]
    missing_ports = [name for name in expected_ports if re.search(r"\b" + name + r"\b", top_text) is None]
    if missing_ports:
        raise AsicError("ASIC external-memory interface lacks " + ",".join(missing_ports))
    parameter_file: Optional[Path] = None
    if parameter_relative is not None:
        parameter_file = safe_root_path(root, parameter_relative.as_posix())
        if not parameter_file.is_file():
            raise AsicError(f"missing OoO parameter lock: {parameter_relative}")
        check_parameter_lock(parameter_file, mode)
    source_hash = sha256_json({
        "source_commit": source_commit,
        "entries": [(entry.get("destination"), entry.get("sha256"))
                    for entry in source.get("entries", [])],
    })
    config_hash = sha256_json({
        "profile": profile,
        "mode": mode,
        "filelist_sha256": sha256_file(filelist),
        "parameter_sha256": sha256_file(parameter_file) if parameter_file else None,
        "constraint_sha256": sha256_file(root / "flows/asic/constraints/internal_clock.sdc"),
        "defines": defines,
        "filelist_source_sha256": [(path.relative_to(root).as_posix(), sha256_file(path))
                                   for path in sources],
    })
    return {
        "profile": profile,
        "mode": mode,
        "source_commit": source_commit,
        "source_set_sha256": source_hash,
        "config_sha256": config_hash,
        "top": top,
        "clock_port": str(profile_data["clock_port"]),
        "reset_port": str(profile_data["reset_port"]),
        "filelist": filelist,
        "parameter_file": parameter_file,
        "frequencies_mhz": [int(value) for value in profile_data["dc_frequencies_mhz"]],
        "matrix": matrix,
        "defines": defines,
        "sources": sources,
        "includes": includes,
    }


def utc_id() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def split_tool(value: str) -> List[str]:
    result = shlex.split(value)
    if not result:
        raise AsicError("empty tool command")
    return result


def require_tool(value: str) -> List[str]:
    command = split_tool(value)
    if shutil.which(command[0]) is None and not Path(command[0]).is_file():
        raise AsicError(f"tool executable not found: {command[0]}")
    return command


def require_hash(path: Path, expected: str, role: str) -> None:
    if not path.is_file():
        raise AsicError(f"missing {role}: {path}")
    actual = sha256_file(path)
    if actual != expected:
        raise AsicError(f"{role} SHA256 mismatch: {actual} != {expected}")


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def parse_frequency_list(raw: str, defaults: Iterable[int]) -> List[int]:
    if not raw:
        return list(defaults)
    values = [int(item) for item in raw.split(",") if item]
    if not values or any(value <= 0 for value in values) or len(set(values)) != len(values):
        raise AsicError("frequencies must be unique positive comma-separated MHz values")
    return values


def dc_matrix(root: Path, config_path: Path, args: argparse.Namespace) -> int:
    contract = build_contract(root, config_path, args.ooo_mode)
    frequencies = parse_frequency_list(args.frequencies, contract["frequencies_mhz"])
    build_root = Path(args.build_root).resolve() if args.build_root else root / "build/asic"
    run_id = args.run_id or utc_id()
    matrix_root = build_root / contract["profile"] / contract["mode"] / "dc" / run_id
    tool_value = os.environ.get("NPC_ASIC_DC_SHELL", "dc_shell")
    commands = [
        [*split_tool(tool_value), "-f", str(root / "flows/asic/dc/run.tcl")]
        for _ in frequencies
    ]
    print("ASIC_DC_MATRIX profile={} mode={} source={} run_id={}".format(
        contract["profile"], contract["mode"], contract["source_commit"], run_id))
    for frequency, command in zip(frequencies, commands):
        print("dc_{}mhz: {}".format(frequency, " ".join(shlex.quote(item) for item in command)))
    if args.dry_run:
        print("ASIC_DC_MATRIX_DRY_RUN_PASS")
        return 0

    tool = require_tool(tool_value)
    liberty = Path(os.environ.get("NPC_ASIC_STDCELL_LIBERTY", "")).expanduser().resolve()
    database = Path(os.environ.get("NPC_ASIC_STDCELL_DB", "")).expanduser().resolve()
    setup = Path(os.environ.get(
        "NPC_ASIC_DC_SETUP", root / "flows/local/asic/dc_setup.tcl")).resolve()
    library_data = contract["matrix"]["libraries"]
    require_hash(liberty, str(library_data["liberty_sha256"]), "Nangate45 Liberty")
    require_hash(database, str(library_data["db_sha256"]), "Nangate45 DB")
    if not setup.is_file():
        raise AsicError(f"missing local DC setup: {setup}")
    if matrix_root.exists():
        raise AsicError(f"refusing to overwrite existing DC matrix: {matrix_root}")
    matrix_root.mkdir(parents=True)
    input_manifest = {
        "schema": "npc-riscv-open/d7-dc-input-v1",
        "profile": contract["profile"], "mode": contract["mode"],
        "source_commit": contract["source_commit"],
        "source_set_sha256": contract["source_set_sha256"],
        "config_sha256": contract["config_sha256"],
        "frequencies_mhz": frequencies,
        "memory_mode": "registers", "macro_count": 0,
        "liberty_sha256": sha256_file(liberty), "db_sha256": sha256_file(database),
        "timer_clock_hz": args.timer_clock_hz,
        "files": {
            "constraint_sdc": {
                "path": str(root / "flows/asic/constraints/internal_clock.sdc"),
                "sha256": sha256_file(root / "flows/asic/constraints/internal_clock.sdc"),
            },
            "dc_setup": {"path": str(setup), "sha256": sha256_file(setup)},
            "stdcell_liberty": {"path": str(liberty), "sha256": sha256_file(liberty)},
            "stdcell_db": {"path": str(database), "sha256": sha256_file(database)},
        },
    }
    if contract["parameter_file"]:
        input_manifest["files"]["elaboration_parameters"] = {
            "path": str(contract["parameter_file"]),
            "sha256": sha256_file(contract["parameter_file"]),
        }
    write_json(matrix_root / "input_manifest.json", input_manifest)
    failed_tools = 0
    for frequency in frequencies:
        run = matrix_root / f"dc_{frequency}mhz"
        run.mkdir()
        period = 1000.0 / frequency
        extra_defines: List[str] = []
        if args.timer_clock_hz:
            if contract["profile"] != "rv32ima_sv32_linux":
                raise AsicError("--timer-clock-hz is only valid for the Linux Profile")
            extra_defines.extend([
                f"NPC_TIMER_CLK_HZ={args.timer_clock_hz}", "NPC_TIMEBASE_HZ=1000000",
            ])
        environment = os.environ.copy()
        environment.update({
            "LC_ALL": "C",
            "NPC_ASIC_ROOT": str(root),
            "NPC_ASIC_PROFILE": contract["profile"],
            "NPC_ASIC_TOP": contract["top"],
            "NPC_ASIC_FILELIST": str(contract["filelist"]),
            "NPC_ASIC_SDC": str(root / "flows/asic/constraints/internal_clock.sdc"),
            "NPC_ASIC_OUTPUT_DIR": str(run),
            "NPC_ASIC_DC_SETUP": str(setup),
            "NPC_ASIC_STDCELL_DB": str(database),
            "NPC_ASIC_CLOCK_PERIOD_NS": f"{period:.9f}",
            "NPC_ASIC_CLOCK_PORT": contract["clock_port"],
            "NPC_ASIC_RESET_PORT": contract["reset_port"],
            "NPC_ASIC_EXTRA_DEFINES": ",".join(extra_defines),
            "NPC_ASIC_PARAMETER_FILE": str(contract["parameter_file"] or ""),
        })
        with (run / "dc.log").open("w", encoding="utf-8") as log:
            completed = subprocess.run(
                [*tool, "-f", str(root / "flows/asic/dc/run.tcl")],
                cwd=run, env=environment, stdout=log, stderr=subprocess.STDOUT,
                check=False,
            )
        (run / "exit_status.txt").write_text(str(completed.returncode) + "\n")
        mapped = run / f"{contract['top']}_mapped.v"
        if completed.returncode == 0 and mapped.is_file():
            (run / "run.ok").write_text("DC_RUN_COMPLETED\n")
        else:
            failed_tools += 1
    rows = [parse_run(path) for path in sorted(matrix_root.glob("dc_*mhz"))]
    write_json(matrix_root / "summary.json", {"input": input_manifest, "runs": rows})
    if rows:
        import csv
        with (matrix_root / "summary.csv").open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader(); writer.writerows(rows)
    closed = [row for row in rows if row["setup_closed"]]
    selected = max(closed, key=lambda row: row["frequency_mhz"]) if closed else None
    write_json(matrix_root / "verdict.json", {
        "status": "DC_CLOSED_POINT_AVAILABLE" if selected else "DC_NO_CLOSED_POINT",
        "selected": selected, "tool_failures": failed_tools,
    })
    print("ASIC_DC_MATRIX_COMPLETE root={} closed_points={} tool_failures={}".format(
        matrix_root, len(closed), failed_tools))
    return 0 if failed_tools == 0 else 2


def pnr(root: Path, config_path: Path, args: argparse.Namespace) -> int:
    contract = build_contract(root, config_path, args.ooo_mode)
    dc_run = Path(args.dc_run).resolve()
    row = parse_run(dc_run)
    if not row["setup_closed"]:
        raise AsicError("P&R requires a setup-closed, loop-free DC run")
    dc_frequency = float(row["frequency_mhz"])
    frequency = int(args.frequency_mhz or (
        math.floor((0.80 * dc_frequency) / 25.0) * 25))
    if frequency <= 0 or frequency > dc_frequency:
        raise AsicError("P&R frequency must be positive and no higher than closed DC")
    if contract["profile"] == "rv32ima_sv32_linux":
        expected_timer = frequency * 1_000_000
        if row.get("timer_clock_hz") != expected_timer:
            raise AsicError(
                "Linux handoff requires a final DC run with NPC_TIMER_CLK_HZ={}"
                .format(expected_timer))
    mapped = dc_run / f"{contract['top']}_mapped.v"
    mapped_sdc = dc_run / f"{contract['top']}_mapped.sdc"
    for path in (mapped, mapped_sdc):
        if not path.is_file():
            raise AsicError(f"missing DC handoff: {path}")
    floorplan = calculate(float(row["area"]))
    run_id = args.run_id or utc_id()
    build_root = Path(args.build_root).resolve() if args.build_root else root / "build/asic"
    run = build_root / contract["profile"] / contract["mode"] / "pnr" / run_id / f"pnr_{frequency}mhz"
    print("ASIC_PNR profile={} mode={} dc_mhz={} pnr_mhz={} run={}".format(
        contract["profile"], contract["mode"], dc_frequency, frequency, run))
    if args.dry_run:
        print("DIE_AREA=" + format_box(floorplan["die_area"]))
        print("CORE_AREA=" + format_box(floorplan["core_area"]))
        print("ASIC_PNR_DRY_RUN_PASS")
        return 0
    if run.exists():
        raise AsicError(f"refusing to overwrite existing P&R run: {run}")
    input_dir = run / "input"
    input_dir.mkdir(parents=True)
    mapped_copy = input_dir / mapped.name
    sdc_copy = input_dir / mapped_sdc.name
    shutil.copy2(mapped, mapped_copy)
    shutil.copy2(mapped_sdc, sdc_copy)
    pnr_sdc = input_dir / f"{contract['top']}_pnr_{frequency}mhz.sdc"
    pnr_sdc.write_text(retarget(
        sdc_copy.read_text(encoding="ascii"), 1000.0 / frequency), encoding="ascii")
    write_json(run / "floorplan.json", floorplan)
    write_json(run / "input_manifest.json", {
        "schema": "npc-riscv-open/d7-pnr-input-v1",
        "profile": contract["profile"], "mode": contract["mode"],
        "source_commit": contract["source_commit"],
        "dc_frequency_mhz": dc_frequency, "pnr_frequency_mhz": frequency,
        "memory_mode": "registers", "macro_count": 0,
        "files": {
            "dc_mapped_netlist": {"path": str(mapped_copy), "sha256": sha256_file(mapped_copy)},
            "dc_mapped_sdc": {"path": str(sdc_copy), "sha256": sha256_file(sdc_copy)},
            "pnr_sdc": {"path": str(pnr_sdc), "sha256": sha256_file(pnr_sdc)},
        },
        "floorplan": floorplan,
    })
    image = os.environ.get("NPC_ASIC_ORFS_IMAGE", "")
    digest = str(contract["matrix"]["orfs"]["image_digest"])
    if not image.endswith("@" + digest):
        raise AsicError(f"NPC_ASIC_ORFS_IMAGE must end with @{digest}")
    tool = require_tool(os.environ.get("NPC_ASIC_OPENROAD_RUNNER", "bash"))
    nickname = re.sub(r"[^A-Za-z0-9_]", "_", "{}_{}_{}m".format(
        contract["profile"], contract["mode"], frequency))
    environment = os.environ.copy()
    environment.update({
        "NPC_ASIC_ROOT": str(root), "NPC_ASIC_BUILD_ROOT": str(run),
        "NPC_ASIC_TOP": contract["top"], "NPC_ASIC_DESIGN_NICKNAME": nickname,
        "NPC_ASIC_MAPPED_NETLIST": str(mapped_copy), "NPC_ASIC_PNR_SDC": str(pnr_sdc),
        "NPC_ASIC_PNR_PERIOD_NS": f"{1000.0 / frequency:.9f}",
        "NPC_ASIC_DIE_AREA": format_box(floorplan["die_area"]),
        "NPC_ASIC_CORE_AREA": format_box(floorplan["core_area"]),
        "NPC_ASIC_PLACE_DENSITY": str(floorplan["place_density"]),
        "NPC_ASIC_ORFS_COMMIT": str(contract["matrix"]["orfs"]["commit"]),
    })
    (run / "openroad_contract.txt").write_text(
        "design_nickname={}\n"
        "top={}\n"
        "platform=nangate45\n"
        "memory_mode=registers\n"
        "macro_count=0\n"
        "pnr_period_ns={:.9f}\n"
        "orfs_commit={}\n"
        "orfs_image={}\n"
        "mapped_netlist_sha256={}\n"
        "orfs_import_netlist_sha256=NA\n".format(
            nickname, contract["top"], 1000.0 / frequency,
            contract["matrix"]["orfs"]["commit"], image,
            sha256_file(mapped_copy)),
        encoding="utf-8",
    )
    with (run / "openroad.log").open("w", encoding="utf-8") as log:
        completed = subprocess.run(
            [*tool, str(root / "flows/asic/openroad/run.sh")], cwd=run,
            env=environment, stdout=log, stderr=subprocess.STDOUT, check=False)
    (run / "exit_status.txt").write_text(str(completed.returncode) + "\n")
    if completed.returncode != 0:
        write_json(run / "summary.json", parse_pnr_run(run))
        print(f"ASIC_PNR_PARTIAL run={run}")
        return 2
    handoff = run / "handoff"
    mapped_hashes = {
        "dc_output_sha256": sha256_file(mapped_copy),
        "pnr_input_sha256": sha256_file(mapped_copy),
        "orfs_import_sha256": sha256_file(
            run / "orfs/results/nangate45" / nickname / "base/1_2_yosys.v"),
    }
    if len(set(mapped_hashes.values())) != 1:
        raise AsicError("FAIL_HANDOFF_IDENTITY: DC/ORFS mapped netlist hashes differ")
    roles = {
        "mapped_netlist": mapped_hashes,
        "routed_netlist": {
            "pnr_output_sha256": sha256_file(handoff / f"{contract['top']}_postroute.v"),
        },
        "routed_sdc": {
            "pnr_output_sha256": sha256_file(handoff / f"{contract['top']}_postroute.sdc"),
        },
        "routed_database": {
            "pnr_output_sha256": sha256_file(handoff / f"{contract['top']}_postroute.odb"),
            "openrcx_input_sha256": sha256_file(handoff / f"{contract['top']}_postroute.odb"),
        },
        "spef": {
            "openrcx_output_sha256": sha256_file(handoff / f"{contract['top']}_postroute.spef"),
        },
    }
    write_json(run / "same_run_artifacts.json", roles)
    summary = parse_pnr_run(run)
    write_json(run / "summary.json", summary)
    if not summary["route_complete"]:
        print(f"ASIC_PNR_PARTIAL run={run}")
        return 2
    (run / "run.ok").write_text("PNR_RCX_COMPLETED\n")
    print(f"ASIC_PNR_COMPLETE run={run}")
    return 0


def sta(root: Path, config_path: Path, args: argparse.Namespace) -> int:
    contract = build_contract(root, config_path, args.ooo_mode)
    pnr_run = Path(args.pnr_run).resolve()
    pnr_input = load_json(pnr_run / "input_manifest.json")
    if pnr_input.get("profile") != contract["profile"] or pnr_input.get("mode") != contract["mode"]:
        raise AsicError("P&R handoff Profile/mode differs from selected configuration")
    pnr_summary = load_json(pnr_run / "summary.json")
    if not (pnr_run / "run.ok").is_file() or not pnr_summary.get("route_complete"):
        raise AsicError("PrimeTime requires a route-clean P&R/OpenRCX handoff")
    frequency = int(pnr_input["pnr_frequency_mhz"])
    handoff = pnr_run / "handoff"
    netlist = handoff / f"{contract['top']}_postroute.v"
    sdc = handoff / f"{contract['top']}_postroute.sdc"
    spef = handoff / f"{contract['top']}_postroute.spef"
    same_run = load_json(pnr_run / "same_run_artifacts.json")
    current = {
        "routed_netlist": sha256_file(netlist),
        "routed_sdc": sha256_file(sdc),
        "spef": sha256_file(spef),
    }
    expected = {
        "routed_netlist": same_run.get("routed_netlist", {}).get("pnr_output_sha256"),
        "routed_sdc": same_run.get("routed_sdc", {}).get("pnr_output_sha256"),
        "spef": same_run.get("spef", {}).get("openrcx_output_sha256"),
    }
    for role, digest in current.items():
        if expected.get(role) != digest:
            raise AsicError(f"FAIL_HANDOFF_IDENTITY: {role} hash drift")
    build_root = Path(args.build_root).resolve() if args.build_root else root / "build/asic"
    run_id = args.run_id or utc_id()
    run = build_root / contract["profile"] / contract["mode"] / "sta" / run_id / f"sta_{frequency}mhz"
    print("ASIC_STA profile={} mode={} frequency_mhz={} run={}".format(
        contract["profile"], contract["mode"], frequency, run))
    if args.dry_run:
        print("ASIC_STA_DRY_RUN_PASS")
        return 0
    database = Path(os.environ.get("NPC_ASIC_STDCELL_DB", "")).expanduser().resolve()
    expected_db = str(contract["matrix"]["libraries"]["db_sha256"])
    require_hash(database, expected_db, "Nangate45 DB")
    setup = Path(os.environ.get(
        "NPC_ASIC_PRIMETIME_SETUP", root / "flows/local/asic/primetime_setup.tcl")).resolve()
    if not setup.is_file():
        raise AsicError(f"missing local PrimeTime setup: {setup}")
    tool = require_tool(os.environ.get("NPC_ASIC_PT_SHELL", "pt_shell"))
    if run.exists():
        raise AsicError(f"refusing to overwrite existing STA run: {run}")
    run.mkdir(parents=True)
    write_json(run / "input_manifest.json", {
        "schema": "npc-riscv-open/d7-sta-input-v1",
        "profile": contract["profile"], "mode": contract["mode"],
        "source_commit": contract["source_commit"], "frequency_mhz": frequency,
        "db_sha256": sha256_file(database),
        "same_run_artifacts": {
            "routed_netlist": {
                "pnr_output_sha256": expected["routed_netlist"],
                "sta_input_sha256": current["routed_netlist"],
            },
            "routed_sdc": {
                "pnr_output_sha256": expected["routed_sdc"],
                "sta_input_sha256": current["routed_sdc"],
            },
            "spef": {
                "openrcx_output_sha256": expected["spef"],
                "sta_input_sha256": current["spef"],
            },
        },
        "files": {
            "routed_netlist": {"path": str(netlist), "sha256": current["routed_netlist"]},
            "routed_sdc": {"path": str(sdc), "sha256": current["routed_sdc"]},
            "spef": {"path": str(spef), "sha256": current["spef"]},
            "stdcell_db": {"path": str(database), "sha256": sha256_file(database)},
            "primetime_setup": {"path": str(setup), "sha256": sha256_file(setup)},
        },
    })
    environment = os.environ.copy()
    environment.update({
        "LC_ALL": "C", "NPC_ASIC_TOP": contract["top"],
        "NPC_ASIC_OUTPUT_DIR": str(run), "NPC_ASIC_STDCELL_DB": str(database),
        "NPC_ASIC_PRIMETIME_SETUP": str(setup),
        "NPC_ASIC_POSTROUTE_NETLIST": str(netlist),
        "NPC_ASIC_POSTROUTE_SDC": str(sdc), "NPC_ASIC_POSTROUTE_SPEF": str(spef),
        "NPC_ASIC_CLOCK_PERIOD_NS": f"{1000.0 / frequency:.9f}",
    })
    with (run / "primetime.log").open("w", encoding="utf-8") as log:
        completed = subprocess.run(
            [*tool, "-f", str(root / "flows/asic/primetime/run.tcl")],
            cwd=run, env=environment, stdout=log, stderr=subprocess.STDOUT, check=False)
    (run / "exit_status.txt").write_text(str(completed.returncode) + "\n")
    if completed.returncode != 0 or not (run / "run_contract.txt").is_file():
        print(f"ASIC_STA_PARTIAL run={run}")
        return 2
    summary = parse_sta_run(run)
    summary["same_run_artifacts"] = load_json(run / "input_manifest.json")["same_run_artifacts"]
    write_json(run / "summary.json", summary)
    if not summary["sta_closed"]:
        print(f"ASIC_STA_PARTIAL run={run}")
        return 2
    (run / "run.ok").write_text("PRIMETIME_COMPLETED\n")
    print(f"ASIC_STA_COMPLETE run={run}")
    return 0


def evidence_check(path: Path) -> int:
    root = path.resolve()
    errors: List[str] = []
    manifests = list(root.rglob("input_manifest.json"))
    if not manifests:
        errors.append(f"{root}: no D7 input manifests found")
    for manifest_path in manifests:
        try:
            record = load_json(manifest_path)
        except AsicError as error:
            errors.append(str(error)); continue
        files = record.get("files", {})
        if isinstance(files, dict):
            for role, item in files.items():
                if not isinstance(item, dict):
                    errors.append(f"{manifest_path}: malformed role {role}"); continue
                candidate = Path(str(item.get("path", "")))
                if not candidate.is_file():
                    errors.append(f"{manifest_path}: missing role {role}"); continue
                if sha256_file(candidate) != item.get("sha256"):
                    errors.append(f"{manifest_path}: hash drift for {role}")
        if (record.get("schema") == "npc-riscv-open/d7-sta-input-v1" and
                not isinstance(record.get("same_run_artifacts"), dict)):
            errors.append(f"{manifest_path}: missing same_run_artifacts")
    for same_path in root.rglob("same_run_artifacts.json"):
        record = load_json(same_path)
        mapped_record = record.get("mapped_netlist", {})
        mapped = [mapped_record.get(key) for key in (
            "dc_output_sha256", "pnr_input_sha256", "orfs_import_sha256")]
        if any(not value for value in mapped) or len(set(mapped)) != 1:
            errors.append(f"{same_path}: FAIL_HANDOFF_IDENTITY")
        database = record.get("routed_database", {})
        database_roles = [database.get("pnr_output_sha256"),
                          database.get("openrcx_input_sha256")]
        if any(not value for value in database_roles) or len(set(database_roles)) != 1:
            errors.append(f"{same_path}: FAIL_HANDOFF_IDENTITY routed_database")
        for role, key in (("routed_netlist", "pnr_output_sha256"),
                          ("routed_sdc", "pnr_output_sha256"),
                          ("spef", "openrcx_output_sha256")):
            if not record.get(role, {}).get(key):
                errors.append(f"{same_path}: missing {role}.{key}")
    for manifest_path in root.rglob("input_manifest.json"):
        record = load_json(manifest_path)
        if record.get("schema") != "npc-riscv-open/d7-sta-input-v1":
            continue
        same = record.get("same_run_artifacts", {})
        pairs = (
            ("routed_netlist", "pnr_output_sha256", "sta_input_sha256"),
            ("routed_sdc", "pnr_output_sha256", "sta_input_sha256"),
            ("spef", "openrcx_output_sha256", "sta_input_sha256"),
        )
        for role, source_key, sink_key in pairs:
            item = same.get(role, {})
            if not item.get(source_key) or item.get(source_key) != item.get(sink_key):
                errors.append(f"{manifest_path}: FAIL_HANDOFF_IDENTITY {role}")
    if errors:
        raise AsicError("ASIC_EVIDENCE_CHECK_FAILED\n  - " + "\n  - ".join(errors))
    print(f"ASIC_EVIDENCE_CHECK_PASS manifests={len(manifests)} root={root}")
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    result.add_argument("--config", type=Path, default=Path(".config"))
    commands = result.add_subparsers(dest="command")
    commands.required = True
    check = commands.add_parser("config-check")
    check.add_argument("--ooo-mode", default="auto",
                       choices=("auto", "legacy", "a3-split-off", "a3"))
    dc = commands.add_parser("dc-matrix")
    dc.add_argument("--dry-run", action="store_true")
    dc.add_argument("--ooo-mode", default="auto",
                    choices=("auto", "legacy", "a3-split-off", "a3"))
    dc.add_argument("--frequencies", default="")
    dc.add_argument("--timer-clock-hz", type=int)
    dc.add_argument("--build-root", default="")
    dc.add_argument("--run-id", default="")
    pnr_parser = commands.add_parser("pnr")
    pnr_parser.add_argument("--dry-run", action="store_true")
    pnr_parser.add_argument("--ooo-mode", default="auto",
                            choices=("auto", "legacy", "a3-split-off", "a3"))
    pnr_parser.add_argument("--dc-run", required=True)
    pnr_parser.add_argument("--frequency-mhz", type=int)
    pnr_parser.add_argument("--build-root", default="")
    pnr_parser.add_argument("--run-id", default="")
    sta_parser = commands.add_parser("sta")
    sta_parser.add_argument("--dry-run", action="store_true")
    sta_parser.add_argument("--ooo-mode", default="auto",
                            choices=("auto", "legacy", "a3-split-off", "a3"))
    sta_parser.add_argument("--pnr-run", required=True)
    sta_parser.add_argument("--build-root", default="")
    sta_parser.add_argument("--run-id", default="")
    evidence = commands.add_parser("evidence-check")
    evidence.add_argument("--build-root", required=True, type=Path)
    a3_eval = commands.add_parser("a3-dc-eval")
    a3_eval.add_argument("--legacy", type=Path, required=True)
    a3_eval.add_argument("--split-off", type=Path, required=True)
    a3_eval.add_argument("--a3", type=Path, required=True)
    a3_eval.add_argument("--cpi-summary", type=Path, required=True)
    a3_eval.add_argument("--output", type=Path, required=True)
    return result


def main(argv: Optional[List[str]] = None) -> int:
    args = parser().parse_args(argv)
    root = args.root.resolve()
    config_path = args.config if args.config.is_absolute() else root / args.config
    try:
        if args.command == "config-check":
            contract = build_contract(root, config_path, args.ooo_mode)
            print("ASIC_CONFIG_CHECK_PASS profile={} mode={} source={} source_set={} config={}".format(
                contract["profile"], contract["mode"], contract["source_commit"],
                contract["source_set_sha256"], contract["config_sha256"]))
            return 0
        if args.command == "dc-matrix":
            return dc_matrix(root, config_path, args)
        if args.command == "pnr":
            return pnr(root, config_path, args)
        if args.command == "sta":
            return sta(root, config_path, args)
        if args.command == "evidence-check":
            return evidence_check(args.build_root)
        if args.command == "a3-dc-eval":
            return compare_a3_dc(
                args.legacy, args.split_off, args.a3, args.cpi_summary, args.output)
        raise AsicError(f"unsupported command {args.command}")
    except (AsicError, OSError, ValueError, KeyError, RuntimeError,
            subprocess.SubprocessError) as error:
        print(f"asicctl: error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
