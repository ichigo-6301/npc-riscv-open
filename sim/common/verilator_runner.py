#!/usr/bin/env python3
"""Small, deterministic Verilator entry point for the public NPC release.

The runner intentionally owns only build/run orchestration.  It does not know
about NEMU, NVBoard, AM, or private workbench paths.  A profile supplies a
filelist and a wrapper named ``npc_public_sim_top``; all profiles then share
the same C++ harness and DPI memory service.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
from typing import Iterable, Sequence


def _repo_root() -> Path:
    # Works both from the private overlay (npc/open/...) and from the exported
    # public root (sim/...).  Do not rely on a fixed absolute checkout depth.
    here = Path(__file__).resolve()
    for candidate in (here.parent, *here.parents):
        if (candidate / "rtl").is_dir() and (
            (candidate / "Kconfig").is_file() or
            (candidate / "control" / "Kconfig").is_file()
        ):
            return candidate
    # The private workbench has no top-level Kconfig; retain a conservative
    # fallback for direct developer invocation before export.
    if len(here.parents) > 4:
        return here.parents[4]
    return here.parent.parent.parent


def _read_filelist(path: Path, root: Path) -> tuple[list[str], list[str]]:
    """Read a Verilator filelist while rejecting private absolute paths.

    ``+define+`` and ``-I`` options are retained.  Relative source paths are
    resolved against the filelist directory (the usual Verilator convention),
    then rendered as absolute paths for the subprocess.  The returned second
    list is the resolved source inventory used in the build signature.
    """

    options: list[str] = []
    sources: list[str] = []
    # Public filelists are rooted at repository top (``rtl/...``), while a
    # developer may also provide a local filelist relative to its own folder.
    base = root

    def resolve_relative(value: str) -> Path:
        candidate = (base / value).resolve()
        if candidate.exists():
            return candidate
        return (path.parent / value).resolve()

    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("//"):
            continue
        # Permit shell-style comments after a path but do not invoke a shell.
        if " #" in line:
            line = line.split(" #", 1)[0].rstrip()
        for token in shlex.split(line):
            if token.startswith("+incdir+"):
                include_path = Path(token[len("+incdir+"):])
                if not include_path.is_absolute():
                    include_path = resolve_relative(str(include_path))
                _assert_public_path(include_path, root)
                options.append("-I" + str(include_path))
                continue
            if token.startswith("+define+") or token.startswith("-D"):
                options.append(token.replace("+define+", "-D", 1))
                continue
            if token.startswith("-I"):
                include = token[2:] or next_token(line, token)
                include_path = Path(include)
                if not include_path.is_absolute():
                    include_path = resolve_relative(str(include_path))
                _assert_public_path(include_path, root)
                options.append("-I" + str(include_path))
                continue
            if token.startswith("-"):
                options.append(token)
                continue
            source = Path(token)
            if not source.is_absolute():
                source = resolve_relative(str(source))
            _assert_public_path(source, root)
            if not source.is_file():
                raise FileNotFoundError(f"filelist source does not exist: {source}")
            sources.append(str(source))
    if not sources:
        raise ValueError(f"filelist has no source files: {path}")
    return options, sources


def next_token(_: str, token: str) -> str:
    # Separate ``-Ifoo`` is the supported form.  This helper keeps malformed
    # ``-I foo`` entries explicit instead of silently selecting cwd.
    raise ValueError(f"filelist must use -I<dir>, got {token!r}")


def _assert_public_path(path: Path, root: Path) -> None:
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"filelist path escapes public repository: {path}") from exc


def _signature(parts: Iterable[str]) -> str:
    h = hashlib.sha256()
    for part in parts:
        h.update(part.encode("utf-8"))
        h.update(b"\0")
    return h.hexdigest()[:16]


def _portable_option(option: str, root: Path) -> str:
    if option.startswith("-I"):
        path = Path(option[2:]).resolve()
        _assert_public_path(path, root)
        return "-I" + path.relative_to(root).as_posix()
    return option


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", default="rv32im_ooo_4k")
    parser.add_argument("--image", type=Path)
    parser.add_argument("--filelist", type=Path)
    parser.add_argument("--top", default="npc_public_sim_top")
    parser.add_argument("--build-dir", type=Path, default=Path("build/verilator"))
    parser.add_argument("--verilator", default=os.environ.get("VERILATOR", "verilator"))
    parser.add_argument("--watchdog", type=int, default=int(os.environ.get("NPC_OPEN_WATCHDOG", "1000000")))
    parser.add_argument("--reset-cycles", type=int, default=8)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--ifetch-latency", type=int, default=None,
                        help="DPI instruction-fetch latency in cycles (0 allowed)")
    parser.add_argument("--lsu-latency", type=int, default=None,
                        help="DPI LSU latency in cycles (0 allowed)")
    parser.add_argument("--memory-latency", type=int, default=None,
                        help="DPI fallback memory latency in cycles (0 allowed)")
    parser.add_argument("--difftest-so", type=Path)
    parser.add_argument("--vcd", type=Path)
    parser.add_argument("--trace", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--clean", action="store_true")
    parser.add_argument("--json-summary", type=Path)
    parser.add_argument("extra", nargs=argparse.REMAINDER,
                        help="arguments passed to the generated simulator after --")
    return parser


def _default_filelist(root: Path, profile: str) -> Path:
    candidates = [root / "filelists" / f"{profile}.f",
                  root / "filelists" / f"{profile}.sv.f"]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(
        f"no filelist for profile {profile!r}; expected filelists/{profile}.f")


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if args.top != "npc_public_sim_top":
        raise ValueError(
            "public harness ABI is fixed at --top npc_public_sim_top; "
            "select a profile wrapper instead"
        )
    for name in ("ifetch_latency", "lsu_latency", "memory_latency"):
        value = getattr(args, name)
        if value is not None and value < 0:
            raise ValueError(f"--{name.replace('_', '-')} must be >= 0")
    root = _repo_root()
    filelist = (args.filelist or _default_filelist(root, args.profile)).resolve()
    _assert_public_path(filelist, root)
    if not filelist.is_file():
        raise FileNotFoundError(filelist)
    options, sources = _read_filelist(filelist, root)
    wrapper_include = root / "rtl" / "wrappers"
    if wrapper_include.is_dir():
        include_flag = "-I" + str(wrapper_include.resolve())
        if include_flag not in options:
            options.append(include_flag)
    verilator = shutil.which(args.verilator) or args.verilator
    build_dir = (root / args.build_dir).resolve() if not args.build_dir.is_absolute() else args.build_dir.resolve()

    common = Path(__file__).resolve().parent
    main_cpp = common / "verilator_main.cpp"
    dpi_cpp = common / "dpi_memory.cpp"
    for required in (main_cpp, dpi_cpp):
        if not required.is_file():
            raise FileNotFoundError(required)

    signature_parts = [args.profile, args.top, str(args.seed), str(args.trace)]
    signature_parts.extend(_portable_option(option, root) for option in options)
    for source_name in sources:
        source = Path(source_name)
        signature_parts.extend([
            source.relative_to(root).as_posix(),
            hashlib.sha256(source.read_bytes()).hexdigest(),
        ])
    for common_source in (main_cpp, dpi_cpp, common.parent / "include/profile_abi.hpp"):
        signature_parts.extend([
            common_source.relative_to(common.parent.parent).as_posix(),
            hashlib.sha256(common_source.read_bytes()).hexdigest(),
        ])
    source_hash = _signature(signature_parts)
    mdir = build_dir / f"{args.profile}-{source_hash}"
    executable = mdir / f"V{args.top}"
    command: list[str] = [verilator, "--cc", "--exe", "--build", "--timing",
                          "-Wall", "-Wno-fatal", "--top-module", args.top,
                          "--Mdir", str(mdir), "-j", "0"]
    if args.trace or args.vcd:
        command.append("--trace")
    command.extend(options)
    sim_include = common.parent / "include"
    command.extend(["-CFLAGS", "-std=c++17 -O2 -I" + str(common) + " -I" + str(sim_include),
                    "-LDFLAGS", "-ldl",
                    str(main_cpp), str(dpi_cpp), *sources])

    run_command = [str(executable), "--profile", args.profile,
                   "--watchdog", str(args.watchdog),
                   "--reset-cycles", str(args.reset_cycles)]
    for flag, value in (("--ifetch-latency", args.ifetch_latency),
                        ("--lsu-latency", args.lsu_latency),
                        ("--memory-latency", args.memory_latency)):
        if value is not None:
            run_command.extend([flag, str(value)])
    if args.image:
        image = args.image.resolve()
        if not image.is_file():
            raise FileNotFoundError(image)
        run_command.extend(["--image", str(image)])
    if args.difftest_so:
        diff = args.difftest_so.resolve()
        if not diff.is_file():
            raise FileNotFoundError(diff)
        run_command.extend(["--difftest-so", str(diff)])
    if args.verbose:
        run_command.append("--verbose")
    env = os.environ.copy()
    env["NPC_PUBLIC_SEED"] = str(args.seed)
    vcd = args.vcd.resolve() if args.vcd else None
    if vcd:
        env["NPC_PUBLIC_VCD"] = str(vcd)

    summary = {
        "profile": args.profile,
        "top": args.top,
        "filelist": str(filelist.relative_to(root)),
        "source_count": len(sources),
        "build_dir": str(mdir.relative_to(root)),
        "signature": source_hash,
        "build_command": command,
        "run_command": run_command,
        "trace": bool(args.trace or args.vcd),
        "seed": args.seed,
        "ifetch_latency": args.ifetch_latency,
        "lsu_latency": args.lsu_latency,
        "memory_latency": args.memory_latency,
        "itrace": env.get("NPC_OPEN_ITRACE") == "1",
        "itrace_path": env.get("NPC_OPEN_ITRACE_PATH", ""),
    }
    if args.dry_run:
        print(json.dumps(summary, indent=2))
        return 0

    build_dir.mkdir(parents=True, exist_ok=True)
    if args.clean and build_dir.exists():
        # Only delete the caller-selected build directory, never source files.
        shutil.rmtree(build_dir)
        build_dir.mkdir(parents=True)
    if vcd:
        vcd.parent.mkdir(parents=True, exist_ok=True)
    if env.get("NPC_OPEN_ITRACE") == "1":
        itrace_value = env.get("NPC_OPEN_ITRACE_PATH", "")
        if not itrace_value:
            raise ValueError("NPC_OPEN_ITRACE=1 requires NPC_OPEN_ITRACE_PATH")
        itrace_path = Path(itrace_value)
        if not itrace_path.is_absolute():
            itrace_path = root / itrace_path
        itrace_path.parent.mkdir(parents=True, exist_ok=True)
        env["NPC_OPEN_ITRACE_PATH"] = str(itrace_path.resolve())

    if shutil.which(verilator) is None and not Path(verilator).is_file():
        raise RuntimeError(f"Verilator executable not found: {args.verilator}")
    if args.verbose:
        print("[public]", " ".join(shlex.quote(x) for x in command))
    else:
        print(f"[public] build profile={args.profile} signature={source_hash} sources={len(sources)}")
    subprocess.run(command, cwd=root, env=env, check=True)
    if args.json_summary:
        args.json_summary.parent.mkdir(parents=True, exist_ok=True)
        args.json_summary.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    if args.build_only:
        return 0
    if args.verbose:
        print("[public]", " ".join(shlex.quote(x) for x in run_command))
    else:
        print(f"[public] run profile={args.profile} image={args.image or '<none>'}")
    completed = subprocess.run(run_command + list(args.extra), cwd=root, env=env)
    return completed.returncode


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, ValueError, RuntimeError) as exc:
        print(f"verilator_runner: {exc}", file=sys.stderr)
        raise SystemExit(2)
