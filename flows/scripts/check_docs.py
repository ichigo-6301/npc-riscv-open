#!/usr/bin/env python3
"""Validate the public documentation contract without external packages."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from urllib.parse import unquote


CORE_PAIRS = (
    ("README.md", "README.en.md"),
    ("docs/README.md", "docs/README.en.md"),
    ("docs/architecture.md", "docs/architecture.en.md"),
    ("docs/performance.md", "docs/performance.en.md"),
    ("docs/soc-integration.md", "docs/soc-integration.en.md"),
    ("docs/simulation.md", "docs/simulation.en.md"),
    ("docs/verification.md", "docs/verification.en.md"),
    ("docs/limitations.md", "docs/limitations.en.md"),
    ("docs/roadmap.md", "docs/roadmap.en.md"),
    (
        "docs/evidence/backend_closure.md",
        "docs/evidence/backend_closure.en.md",
    ),
    (
        "docs/evidence/performance_history.md",
        "docs/evidence/performance_history.en.md",
    ),
    (
        "docs/evidence/system_fpga_history.md",
        "docs/evidence/system_fpga_history.en.md",
    ),
)
LEGACY_PAGES = (
    "docs/README.zh-CN.md",
    "docs/reproduction.md",
    "docs/validation.md",
)
FORBIDDEN = (
    re.compile(r"发行版"),
    re.compile(r"发布候选"),
    re.compile(r"\brelease\b", re.I),
    re.compile(r"\bRC1\b", re.I),
)
LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
METRIC_KEYWORD_RE = re.compile(
    r"(?i)(?:coremark|cpi|mhz|wns|area|frequency|cycles?|commits?|"
    r"频率|面积|周期|提交|指令)"
)
METRIC_VALUE_RE = re.compile(
    r"(?i)(?:[-+]?\d+\.\d+|\d{1,3}(?:,\d{3})+|\d+\s*(?:mhz|ns|cycles?|commits?))"
)
METRIC_MARKER_RE = re.compile(r"\b(nonclaim|evidence):([A-Za-z0-9_.-]+)\b")
CODE_TOKEN_RE = re.compile(r"`([A-Za-z0-9_.-]+)`")
SHOWCASE_START = "<!-- showcase:key-results:start -->"
SHOWCASE_END = "<!-- showcase:key-results:end -->"
README_RESULT_ROWS = {
    "evidence/performance/coremark.json": (
        "1.4849", "current", "verified",
    ),
    "evidence/performance/linux_coremark_ab.json": (
        "8.587→1.726", "4.98x", "historical_verified", "partial",
        "not_reverified",
    ),
    "evidence/system/linux_boot.json": (
        "6.6.141", "historical_verified", "not_reverified",
    ),
    "evidence/performance/ooo_frontend_branch_ab.json": (
        "53.76%→23.29%", "59.38%→17.73%", "historical_verified",
        "pre-loop-remediation", "provisional",
    ),
    "evidence/fpga/single_xc7z100_history.json": (
        "200 MHz", "historical_verified", "partial", "not_claimed",
    ),
    "evidence/implementation/nangate45_fixed_points.json": (
        "200–475 MHz", "verified", "partial",
    ),
}
README_RESULT_GUIDES = {
    "README.md": {
        "evidence/performance/coremark.json": "docs/evidence/coremark_reproduction.md",
        "evidence/performance/linux_coremark_ab.json": "docs/evidence/performance_history.md",
        "evidence/system/linux_boot.json": "docs/evidence/system_fpga_history.md",
        "evidence/performance/ooo_frontend_branch_ab.json": "docs/evidence/performance_history.md",
        "evidence/fpga/single_xc7z100_history.json": "docs/evidence/system_fpga_history.md",
        "evidence/implementation/nangate45_fixed_points.json": "docs/evidence/backend_closure.md",
    },
    "README.en.md": {
        "evidence/performance/coremark.json": "docs/evidence/coremark_reproduction.en.md",
        "evidence/performance/linux_coremark_ab.json": "docs/evidence/performance_history.en.md",
        "evidence/system/linux_boot.json": "docs/evidence/system_fpga_history.en.md",
        "evidence/performance/ooo_frontend_branch_ab.json": "docs/evidence/performance_history.en.md",
        "evidence/fpga/single_xc7z100_history.json": "docs/evidence/system_fpga_history.en.md",
        "evidence/implementation/nangate45_fixed_points.json": "docs/evidence/backend_closure.en.md",
    },
}
README_CODE_PATHS = (
    "rtl/profiles/rv32im_single_perf/cpu_top.v",
    "rtl/profiles/rv32ima_sv32_linux/top/cpu_top.v",
    "rtl/profiles/rv32im_ooo_4k/top/ooo_npc_top.sv",
    "rtl/profiles/rv32im_single_perf/cpu_top/if_stage.v",
    "rtl/profiles/rv32im_single_perf/cpu_top/id_stage.v",
    "rtl/profiles/rv32im_single_perf/cache/ICache.v",
    "rtl/profiles/rv32im_single_perf/cache/DCache.v",
    "rtl/profiles/rv32ima_sv32_linux/csr/PrivCsrRegs.v",
    "rtl/profiles/rv32ima_sv32_linux/csr/TrapCtrl.v",
    "rtl/profiles/rv32ima_sv32_linux/frontend/Sv32FrontendPipe.v",
    "rtl/profiles/rv32ima_sv32_linux/mmu/Sv32Tlb.v",
    "rtl/profiles/rv32ima_sv32_linux/lsu/Sv32DCacheBridge.v",
    "rtl/profiles/rv32ima_sv32_linux/lsu/Sv32LSUPipe.v",
    "rtl/profiles/rv32im_ooo_4k/core/ooo_rename_dispatch_recovery_2w.sv",
    "rtl/profiles/rv32im_ooo_4k/core/ooo_prf.sv",
    "rtl/profiles/rv32im_ooo_4k/core/small_rob.sv",
    "rtl/profiles/rv32im_ooo_4k/core/alu_issue_queue_1w.sv",
    "rtl/profiles/rv32im_ooo_4k/core/ooo_branch_checkpoint_state_2w.sv",
    "rtl/profiles/rv32im_ooo_4k/execute/ooo_lsu_atomic_mem_arbiter_2e.sv",
    "rtl/profiles/rv32im_ooo_4k/execute/ooo_precise_store_buffer_4entry.sv",
    "rtl/wrappers/rv32im_single_perf_sim_top.sv",
    "rtl/wrappers/rv32ima_sv32_linux_sim_top.sv",
    "rtl/wrappers/rv32im_ooo_4k_sim_top.sv",
    "sim/include/profile_abi.hpp",
    "sim/adapters/nemu_public_adapter.cpp",
    "sim/common/verilator_runner.py",
    "sim/common/verilator_main.cpp",
    "tests/sources/rv32im_core_smoke.S",
)
README_CHECK_TOKENS = (
    "rv32im_single_perf_defconfig",
    "rv32ima_sv32_linux_defconfig",
    "rv32im_ooo_4k_defconfig",
    "verilator-lint",
    "smoke",
    "regression",
    "runtime-tests",
    "docs-check",
    "evidence-check",
    "showcase-check",
    "implementation-check",
    "verify-checksums",
    "public-hygiene",
    "lc-macros-dry-run",
    "dc-matrix-dry-run",
    "pnr-dry-run",
    "sta-dry-run",
)


def load_json_yaml(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"{path}: expected dependency-free JSON-compatible YAML: {error}")
    if not isinstance(value, dict):
        raise RuntimeError(f"{path}: top level must be a mapping")
    return value


def visitor_paths(root: Path) -> list[Path]:
    paths: list[Path] = []
    for name in ("README.md", "README.en.md", "NOTICE", "NOTICE.md", "Kconfig", "Makefile"):
        path = root / name
        if path.is_file():
            paths.append(path)
    for directory in ("docs", "delivery", "provenance"):
        base = root / directory
        if base.is_dir():
            paths.extend(path for path in sorted(base.rglob("*")) if path.is_file())
    return paths


def check_pairs(root: Path, errors: list[str]) -> None:
    for left, right in CORE_PAIRS:
        for relative in (left, right):
            path = root / relative
            if not path.is_file():
                errors.append(f"missing bilingual core page: {relative}")
            elif not path.read_text(encoding="utf-8").strip():
                errors.append(f"empty bilingual core page: {relative}")
    for relative in LEGACY_PAGES:
        if (root / relative).exists():
            errors.append(f"legacy documentation page must be removed: {relative}")


def check_terms(root: Path, errors: list[str]) -> None:
    for path in visitor_paths(root):
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        relative = path.relative_to(root).as_posix()
        for pattern in FORBIDDEN:
            match = pattern.search(text)
            if match:
                line = text.count("\n", 0, match.start()) + 1
                errors.append(f"{relative}:{line}: forbidden public lifecycle term {match.group(0)!r}")


def link_target(raw: str) -> str:
    raw = raw.strip()
    if raw.startswith("<") and ">" in raw:
        return raw[1 : raw.index(">")]
    if " " in raw:
        raw = raw.split(" ", 1)[0]
    return raw


def check_links(root: Path, errors: list[str]) -> None:
    markdown = [root / "README.md", root / "README.en.md"]
    markdown.extend(sorted((root / "docs").rglob("*.md")))
    for path in markdown:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for match in LINK_RE.finditer(text):
            target = link_target(match.group(1))
            if not target or target.startswith(("#", "http://", "https://", "mailto:")):
                continue
            target = unquote(target.split("#", 1)[0].split("?", 1)[0])
            resolved = root / target.lstrip("/") if target.startswith("/") else path.parent / target
            if not resolved.exists():
                line = text.count("\n", 0, match.start()) + 1
                errors.append(f"{path.relative_to(root)}:{line}: broken local link {target}")


def check_readme_showcase(root: Path, errors: list[str]) -> None:
    headings = {
        "README.md": (
            "## 关键结果与证据入口", "## 60 秒状态矩阵",
            "## 10 分钟代码阅读路径", "## 快速检查（不依赖商业 EDA）",
            "## Canonical top 与 filelist", "## 文档导航", "## 限制与 Roadmap",
        ),
        "README.en.md": (
            "## Key Results And Evidence", "## 60-Second Status Matrix",
            "## 10-Minute Code Reading Path", "## Quick Checks Without Commercial EDA",
            "## Canonical Top And Filelist", "## Documentation",
            "## Limitations And Roadmap",
        ),
    }
    for name, expected_headings in headings.items():
        path = root / name
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        positions = [text.find(heading) for heading in expected_headings]
        if any(position < 0 for position in positions) or positions != sorted(positions):
            errors.append(f"{name}: interview-entry section order drift")
        if text.count(SHOWCASE_START) != 1 or text.count(SHOWCASE_END) != 1:
            errors.append(f"{name}: key-results block markers must appear exactly once")
            continue
        block = text.split(SHOWCASE_START, 1)[1].split(SHOWCASE_END, 1)[0]
        table_lines = [line for line in block.splitlines() if line.startswith("|")]
        if len(table_lines) != 8:
            errors.append(f"{name}: key-results table must contain exactly six data rows")
        for evidence_path, tokens in README_RESULT_ROWS.items():
            matches = [line for line in table_lines if f"]({evidence_path})" in line]
            if len(matches) != 1:
                errors.append(f"{name}: key-results row mismatch for {evidence_path}")
                continue
            row = matches[0]
            for token in (*tokens, README_RESULT_GUIDES[name][evidence_path]):
                if token not in row:
                    errors.append(
                        f"{name}: key-results row {evidence_path} lacks {token}")
        for code_path in README_CODE_PATHS:
            if f"]({code_path})" not in text:
                errors.append(f"{name}: code-reading path lacks {code_path}")
        for token in README_CHECK_TOKENS:
            if token not in text:
                errors.append(f"{name}: quick-check entry lacks {token}")
        for badge in ("actions/workflows/public-ci.yml", "RTL-Verilog", "github/license"):
            if badge not in text:
                errors.append(f"{name}: public badge drift for {badge}")
        for boundary in ("Fmax", "OCV/MMMC", "foundry signoff", "silicon"):
            if boundary not in text:
                errors.append(f"{name}: result nonclaim boundary lacks {boundary}")


def metric_records(root: Path) -> tuple[dict[str, dict], set[str]]:
    nonclaims_data = load_json_yaml(root / "delivery/claims/nonclaims.yaml")
    evidence_data = load_json_yaml(root / "delivery/evidence/manifest.yaml")
    nonclaim_items = [
        item for item in nonclaims_data.get("nonclaims", [])
        if isinstance(item, dict) and item.get("id")
    ]
    evidence_items = [
        item for item in evidence_data.get("evidence", [])
        if isinstance(item, dict) and item.get("id")
    ]
    nonclaims = {str(item["id"]): item for item in nonclaim_items}
    evidence = {str(item["id"]) for item in evidence_items}
    if len(nonclaims) != len(nonclaim_items):
        raise RuntimeError("delivery/claims/nonclaims.yaml contains duplicate ids")
    if len(evidence) != len(evidence_items):
        raise RuntimeError("delivery/evidence/manifest.yaml contains duplicate ids")
    return nonclaims, evidence


def check_performance_records(root: Path, errors: list[str]) -> None:
    try:
        nonclaims, evidence = metric_records(root)
    except RuntimeError as error:
        errors.append(str(error))
        return
    for language in ("docs/performance.md", "docs/performance.en.md"):
        path = root / language
        if not path.is_file():
            continue
        bound_values: set[str] = set()
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not METRIC_KEYWORD_RE.search(line) or not METRIC_VALUE_RE.search(line):
                continue
            values = {
                value.casefold().replace(" ", "").lstrip("+-")
                for value in METRIC_VALUE_RE.findall(line)
            }
            markers = METRIC_MARKER_RE.findall(line)
            markers.extend(
                ("nonclaim", token) if token in nonclaims else ("evidence", token)
                for token in CODE_TOKEN_RE.findall(line)
                if token in nonclaims or token in evidence
            )
            if not markers:
                if not values.issubset(bound_values):
                    errors.append(f"{language}:{number}: performance value lacks nonclaim/evidence marker")
                continue
            bound_values.update(values)
            for kind, identifier in markers:
                if kind == "evidence":
                    if identifier not in evidence:
                        errors.append(f"{language}:{number}: unknown evidence id {identifier}")
                    continue
                record = nonclaims.get(identifier)
                if record is None:
                    errors.append(f"{language}:{number}: unknown nonclaim id {identifier}")
                    continue
                missing = [key for key in ("profile", "source_commit", "conditions", "evidence_status") if not record.get(key)]
                if missing:
                    errors.append(f"{language}:{number}: nonclaim {identifier} lacks {','.join(missing)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    errors: list[str] = []
    check_pairs(root, errors)
    check_terms(root, errors)
    check_links(root, errors)
    check_readme_showcase(root, errors)
    check_performance_records(root, errors)
    if errors:
        raise SystemExit("DOCS_CHECK_FAILED\n  - " + "\n  - ".join(sorted(set(errors))))
    print("DOCS_CHECK_PASS pairs={} visitor_files={}".format(len(CORE_PAIRS), len(visitor_paths(root))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
