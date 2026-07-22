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
    check_performance_records(root, errors)
    if errors:
        raise SystemExit("DOCS_CHECK_FAILED\n  - " + "\n  - ".join(sorted(set(errors))))
    print("DOCS_CHECK_PASS pairs={} visitor_files={}".format(len(CORE_PAIRS), len(visitor_paths(root))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
