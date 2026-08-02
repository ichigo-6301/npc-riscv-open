#!/usr/bin/env python3
"""Run the D8 cache-leaf contract against the audited OpenRAM models."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Dict


MACROS = (
    "npc_icache_data_1r1w_512x32",
    "npc_dcache_data_1r1w_512x32_b8",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def model_path(canonical_root: Path, macro: str) -> Path:
    root = canonical_root / macro
    manifest = json.loads((root / "canonical_manifest.json").read_text(encoding="utf-8"))
    relative = manifest["view_files"][".v"]
    path = root / "reproducibility/run1/views" / relative
    if not path.is_file():
        raise ValueError(f"missing OpenRAM model for {macro}: {path}")
    return path


def testbench() -> str:
    return r'''`timescale 1ns / 1ps

module d8_sync_ref (
    input clk,
    input ren,
    input [8:0] raddr,
    output reg [31:0] rdata,
    input wen,
    input [8:0] waddr,
    input [31:0] wdata,
    input [3:0] wstrb
);
    reg [31:0] mem [0:511];
    integer byte_i;
    always @(posedge clk) begin
        if (ren) rdata <= mem[raddr];
        if (wen) begin
            for (byte_i = 0; byte_i < 4; byte_i = byte_i + 1)
                if (wstrb[byte_i]) mem[waddr][byte_i * 8 +: 8] <= wdata[byte_i * 8 +: 8];
        end
    end
endmodule

module d8_sram_leaf_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg [3:0] ren = 0;
    reg [8:0] raddr [0:3];
    wire [31:0] macro_rdata [0:3];
    wire [31:0] xpm_rdata [0:3];
    wire [31:0] ref_rdata [0:3];
    reg [3:0] wen = 0;
    reg [8:0] waddr [0:3];
    reg [31:0] wdata [0:3];
    reg [3:0] wstrb [0:3];
    integer errors = 0;
    integer i;

    CacheDataArray1R1W #(.ADDR_WIDTH(9), .DATA_WIDTH(32), .DEPTH(512),
        .WSTRB_WIDTH(4), .MEMORY_KIND(0)) u_icache_way0 (
        .clk(clk), .ren(ren[0]), .raddr(raddr[0]), .rdata(macro_rdata[0]),
        .wen(wen[0]), .waddr(waddr[0]), .wdata(wdata[0]), .wstrb(wstrb[0]));
    CacheDataArray1R1W #(.ADDR_WIDTH(9), .DATA_WIDTH(32), .DEPTH(512),
        .WSTRB_WIDTH(4), .MEMORY_KIND(0)) u_icache_way1 (
        .clk(clk), .ren(ren[1]), .raddr(raddr[1]), .rdata(macro_rdata[1]),
        .wen(wen[1]), .waddr(waddr[1]), .wdata(wdata[1]), .wstrb(wstrb[1]));
    CacheDataArray1R1W #(.ADDR_WIDTH(9), .DATA_WIDTH(32), .DEPTH(512),
        .WSTRB_WIDTH(4), .MEMORY_KIND(1)) u_dcache_way0 (
        .clk(clk), .ren(ren[2]), .raddr(raddr[2]), .rdata(macro_rdata[2]),
        .wen(wen[2]), .waddr(waddr[2]), .wdata(wdata[2]), .wstrb(wstrb[2]));
    CacheDataArray1R1W #(.ADDR_WIDTH(9), .DATA_WIDTH(32), .DEPTH(512),
        .WSTRB_WIDTH(4), .MEMORY_KIND(1)) u_dcache_way1 (
        .clk(clk), .ren(ren[3]), .raddr(raddr[3]), .rdata(macro_rdata[3]),
        .wen(wen[3]), .waddr(waddr[3]), .wdata(wdata[3]), .wstrb(wstrb[3]));

`ifdef D8_TEST_XPM
    xpm_memory_sdpram #(.ADDR_WIDTH_A(9), .ADDR_WIDTH_B(9),
        .BYTE_WRITE_WIDTH_A(8), .MEMORY_SIZE(16384), .READ_DATA_WIDTH_B(32),
        .READ_LATENCY_B(1), .WRITE_DATA_WIDTH_A(32)) u_xpm_icache_way0 (
        .dbiterrb(), .doutb(xpm_rdata[0]), .sbiterrb(),
        .addra(waddr[0]), .addrb(raddr[0]), .clka(clk), .clkb(clk),
        .dina(wdata[0]), .ena(wen[0]), .enb(ren[0]),
        .injectdbiterra(1'b0), .injectsbiterra(1'b0), .regceb(1'b1),
        .rstb(1'b0), .sleep(1'b0), .wea(4'b1111));
    xpm_memory_sdpram #(.ADDR_WIDTH_A(9), .ADDR_WIDTH_B(9),
        .BYTE_WRITE_WIDTH_A(8), .MEMORY_SIZE(16384), .READ_DATA_WIDTH_B(32),
        .READ_LATENCY_B(1), .WRITE_DATA_WIDTH_A(32)) u_xpm_icache_way1 (
        .dbiterrb(), .doutb(xpm_rdata[1]), .sbiterrb(),
        .addra(waddr[1]), .addrb(raddr[1]), .clka(clk), .clkb(clk),
        .dina(wdata[1]), .ena(wen[1]), .enb(ren[1]),
        .injectdbiterra(1'b0), .injectsbiterra(1'b0), .regceb(1'b1),
        .rstb(1'b0), .sleep(1'b0), .wea(4'b1111));
    xpm_memory_tdpram #(.ADDR_WIDTH_A(9), .ADDR_WIDTH_B(9),
        .BYTE_WRITE_WIDTH_A(8), .MEMORY_SIZE(16384), .READ_DATA_WIDTH_A(32),
        .READ_LATENCY_A(1), .READ_DATA_WIDTH_B(32), .READ_LATENCY_B(1),
        .WRITE_DATA_WIDTH_A(32), .WRITE_DATA_WIDTH_B(32)) u_xpm_dcache_way0 (
        .douta(), .doutb(xpm_rdata[2]), .addra(waddr[2]), .addrb(raddr[2]),
        .clka(clk), .clkb(clk), .dina(wdata[2]), .dinb(32'b0),
        .ena(1'b1), .enb(ren[2]), .wea(wen[2] ? wstrb[2] : 4'b0000), .web(4'b0000));
    xpm_memory_tdpram #(.ADDR_WIDTH_A(9), .ADDR_WIDTH_B(9),
        .BYTE_WRITE_WIDTH_A(8), .MEMORY_SIZE(16384), .READ_DATA_WIDTH_A(32),
        .READ_LATENCY_A(1), .READ_DATA_WIDTH_B(32), .READ_LATENCY_B(1),
        .WRITE_DATA_WIDTH_A(32), .WRITE_DATA_WIDTH_B(32)) u_xpm_dcache_way1 (
        .douta(), .doutb(xpm_rdata[3]), .addra(waddr[3]), .addrb(raddr[3]),
        .clka(clk), .clkb(clk), .dina(wdata[3]), .dinb(32'b0),
        .ena(1'b1), .enb(ren[3]), .wea(wen[3] ? wstrb[3] : 4'b0000), .web(4'b0000));
`else
    genvar xpm_i;
    generate for (xpm_i = 0; xpm_i < 4; xpm_i = xpm_i + 1) begin : gen_xpm_alias
        assign xpm_rdata[xpm_i] = macro_rdata[xpm_i];
    end endgenerate
`endif

    genvar ref_i;
    generate for (ref_i = 0; ref_i < 4; ref_i = ref_i + 1) begin : gen_ref
        d8_sync_ref u_ref (
            .clk(clk), .ren(ren[ref_i]), .raddr(raddr[ref_i]), .rdata(ref_rdata[ref_i]),
            .wen(wen[ref_i]), .waddr(waddr[ref_i]), .wdata(wdata[ref_i]),
            .wstrb(wstrb[ref_i]));
    end endgenerate

    task drive_write;
        input integer way;
        input [8:0] address;
        input [31:0] data;
        input [3:0] mask;
        begin
            @(negedge clk); #1;
            wen[way] = 1'b1; waddr[way] = address; wdata[way] = data; wstrb[way] = mask;
            @(negedge clk); #1;
            wen[way] = 1'b0;
        end
    endtask

    task check_read;
        input integer way;
        input [8:0] address;
        input [31:0] expected;
        begin
            @(negedge clk); #1;
            ren[way] = 1'b1; raddr[way] = address;
            @(negedge clk); #4;
            if (macro_rdata[way] !== expected || xpm_rdata[way] !== expected ||
                ref_rdata[way] !== expected || macro_rdata[way] !== ref_rdata[way] ||
                xpm_rdata[way] !== ref_rdata[way]) begin
                $display("D8_SRAM_LEAF_MISMATCH way=%0d addr=%0d macro=%08x xpm=%08x ref=%08x expected=%08x",
                         way, address, macro_rdata[way], xpm_rdata[way], ref_rdata[way], expected);
                errors = errors + 1;
            end
            #1 ren[way] = 1'b0;
        end
    endtask

    initial begin
        for (i = 0; i < 4; i = i + 1) begin
            raddr[i] = 0; waddr[i] = 0; wdata[i] = 0; wstrb[i] = 0;
        end

        // Full-word writes and independent I-cache ways.
        drive_write(0, 9'd3, 32'h12345678, 4'b1111);
        drive_write(1, 9'd7, 32'h89abcdef, 4'b1111);
        @(negedge clk); #1;
        ren[0] = 1'b1; raddr[0] = 9'd3;
        ren[1] = 1'b1; raddr[1] = 9'd7;
        @(negedge clk); #4;
        if (macro_rdata[0] !== 32'h12345678 || macro_rdata[1] !== 32'h89abcdef ||
            xpm_rdata[0] !== 32'h12345678 || xpm_rdata[1] !== 32'h89abcdef ||
            macro_rdata[0] !== ref_rdata[0] || macro_rdata[1] !== ref_rdata[1] ||
            xpm_rdata[0] !== ref_rdata[0] || xpm_rdata[1] !== ref_rdata[1]) begin
            $display("D8_SRAM_LEAF_DUAL_WAY_MISMATCH");
            errors = errors + 1;
        end
        #1 ren[0] = 0; ren[1] = 0;

        // D-cache full write followed by byte-mask update.
        drive_write(2, 9'd4, 32'h11223344, 4'b1111);
        drive_write(2, 9'd4, 32'haabbccdd, 4'b0101);
        check_read(2, 9'd4, 32'h11bb33dd);

        // Concurrent different-address read/write and a consecutive read.
        @(negedge clk); #1;
        wen[2] = 1'b1; waddr[2] = 9'd5; wdata[2] = 32'hdeadbeef; wstrb[2] = 4'b1111;
        ren[2] = 1'b1; raddr[2] = 9'd4;
        @(negedge clk); #4;
        if (macro_rdata[2] !== 32'h11bb33dd || xpm_rdata[2] !== 32'h11bb33dd ||
            macro_rdata[2] !== ref_rdata[2] || xpm_rdata[2] !== ref_rdata[2]) begin
            $display("D8_SRAM_LEAF_CONCURRENT_MISMATCH");
            errors = errors + 1;
        end
        #1 wen[2] = 0; ren[2] = 0;
        check_read(2, 9'd5, 32'hdeadbeef);

        // Prohibited collision: the OpenRAM model must emit its native warning.
        @(negedge clk); #1;
        wen[3] = 1'b1; waddr[3] = 9'd6; wdata[3] = 32'hcafef00d; wstrb[3] = 4'b1111;
        ren[3] = 1'b1; raddr[3] = 9'd6;
        @(negedge clk); #4;
        wen[3] = 0; ren[3] = 0;

        if (errors != 0) $fatal(1, "D8_SRAM_LEAF_FAIL errors=%0d", errors);
        $display("D8_SRAM_LEAF_PASS");
        $finish;
    end
endmodule
'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--d6-canonical-root", required=True, type=Path)
    parser.add_argument("--cache-array-rtl", required=True, type=Path)
    parser.add_argument("--xpm-register-models", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    args = parser.parse_args()

    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        raise ValueError(f"refusing to overwrite non-empty leaf-test output: {output}")
    output.mkdir(parents=True, exist_ok=True)
    rtl = args.cache_array_rtl.resolve()
    if not rtl.is_file():
        raise ValueError(f"missing cache array RTL: {rtl}")
    xpm = args.xpm_register_models.resolve() if args.xpm_register_models else None
    if xpm is not None and not xpm.is_file():
        raise ValueError(f"missing XPM compatibility RTL: {xpm}")
    models: Dict[str, Path] = {
        macro: model_path(args.d6_canonical_root.resolve(), macro) for macro in MACROS
    }
    iverilog = shutil.which(args.iverilog) or args.iverilog
    vvp = shutil.which(args.vvp) or args.vvp
    tb = output / "d8_sram_leaf_tb.sv"
    tb.write_text(testbench(), encoding="ascii")
    executable = output / "d8_sram_leaf_tb.vvp"
    compile_command = [
        iverilog, "-g2012", "-DSYNTHESIS", "-DNPC_ASIC", "-DNPC_ASIC_SRAM",
        *(["-DD8_TEST_XPM"] if xpm is not None else []),
        "-s", "d8_sram_leaf_tb", "-o", str(executable), str(rtl),
        *([str(xpm)] if xpm is not None else []),
        *(str(models[name]) for name in MACROS), str(tb),
    ]
    compiled = subprocess.run(compile_command, cwd=output, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    (output / "iverilog.log").write_text(compiled.stdout, encoding="utf-8")
    if compiled.returncode != 0:
        raise ValueError("Icarus compilation failed")
    simulated = subprocess.run([vvp, str(executable)], cwd=output, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    (output / "vvp.log").write_text(simulated.stdout, encoding="utf-8")
    if (simulated.returncode != 0 or "D8_SRAM_LEAF_PASS" not in simulated.stdout or
            "WARNING: Writing and reading" not in simulated.stdout):
        raise ValueError("SRAM leaf contract simulation failed")
    files = {"cache_array_rtl": rtl, **({"xpm_register_models": xpm} if xpm else {}),
             **{f"model_{name}": path for name, path in models.items()}}
    manifest = {
        "schema": "npc-riscv-open/d8-sram-leaf-test-v1",
        "status": "D8_SRAM_LEAF_PASS",
        "xpm_backend_checked": xpm is not None,
        "collision_warning_observed": True,
        "files": {role: {"path": str(path), "sha256": sha256_file(path)}
                  for role, path in files.items()},
        "commands": {"iverilog": compile_command, "vvp": [vvp, str(executable)]},
        "output_sha256": {
            "iverilog_log": sha256_file(output / "iverilog.log"),
            "vvp_log": sha256_file(output / "vvp.log"),
        },
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"D8_SRAM_LEAF_PASS output={output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"verify_sram_leaf: error: {error}", file=sys.stderr)
        raise SystemExit(2)
