# 仿真指南

[English](simulation.en.md)

## 环境要求

- Linux；
- Python 3.8 或更新版本；
- GNU Make、C++ compiler；
- PyYAML；
- Verilator 5.x。

安装 Python 依赖后先生成 Profile 配置：

```sh
python3 -m pip install --user PyYAML
make defconfig
make showconfig
```

`showconfig` 应显示 `project_id=npc-riscv-open`、当前 `snapshot_id` 和唯一的
`profile_id`。旧版 `.config` 不兼容新的 project/snapshot 字段；切换代码后
直接重新执行一个 defconfig target。

## 选择 Profile

```sh
make rv32im_single_perf_defconfig
make rv32ima_sv32_linux_defconfig
make rv32im_ooo_4k_defconfig
```

`make defconfig` 默认选择 `rv32im_ooo_4k`。架构宽度、ISA、cache/TLB 和 OoO
机制由 Profile manifest 固定；命令行只用于镜像、watchdog、seed、trace 等
运行输入。

## 标准流程

```sh
make config-check source-check docs-check public-hygiene
make verify-checksums
make sim-dry-run
make verilator-lint
make smoke
make regression
```

`sim-dry-run` 输出实际 top、filelist、define、latency 和 runner 命令，但不
启动长仿真。`smoke` 使用选中 Profile 的固定小程序；`regression` 只运行该
Profile manifest 明确列出的测试。

## 自备程序镜像

```sh
NPC_OPEN_IMAGE=/path/to/program.bin make sim
```

runtime 支持原始 binary，以及以 `.hex` 或 `.mem` 结尾的 word-oriented 文本
镜像。默认 PMEM 范围是 `0x80000000..0x8FFFFFFF`；文本镜像可用 `@<hex_addr>`
改变装载地址。镜像超出 PMEM 或无法解析时仿真直接失败。

可选环境输入包括：

| 变量 | 用途 |
| --- | --- |
| `NPC_OPEN_IMAGE` | 覆盖 `.config` 中的程序镜像 |
| `NPC_PUBLIC_MEM_BASE/LIMIT` | 调整 sparse PMEM 范围 |
| `NPC_PUBLIC_TOHOST` | 设置 32-bit tohost 地址；默认不启用 |
| `VERILATOR` | 指定 Verilator executable |

这些输入不会改变 Profile 的 ISA 或微架构身份。

## 默认 latency

| Profile | IF latency | LSU latency | memory latency |
| --- | ---: | ---: | ---: |
| `rv32im_single_perf` | 2 | 2 | 2 |
| `rv32ima_sv32_linux` | 0 | 0 | 0 |
| `rv32im_ooo_4k` | 2 | 3 | 2 |

这里的数字是公共 DPI transport 配置，不是 ASIC SRAM 时序，也不直接等于
cache hit latency。即使配置为 0，请求/响应仍遵循时钟化 ready/valid 仿真
协议，不应解释为组合逻辑 memory。

## Trace 与 watchdog

三个 defconfig 默认关闭 VCD 和 itrace，watchdog 为 20,000,000 cycles。
需要调试时可通过 Kconfig/`.config` 显式开启：

- `CONFIG_NPC_VCD`，默认输出路径 `build/waves/sim.vcd`；
- `CONFIG_NPC_ITRACE`，默认输出路径 `build/traces/itrace.log`。

trace 会产生大量文件并降低宿主仿真速度，性能测量时应保持关闭。mtrace、
ftrace、pmemtrace、SDB、反汇编和 NVBoard 不属于公共 runtime。

## 可选 NEMU difftest

默认仿真无需 NEMU。严格本地检查按 Profile 构建对应 reference：

```sh
make rv32im_ooo_4k_defconfig
make difftest-prepare NPC_NEMU_SOURCE_REPO=/path/to/ysyx-workbench
make difftest
```

`difftest-prepare` 从 manifest 锁定的 workbench commit 取得对应 NEMU tree，
在 `flows/local/nemu/<profile>/` 构建 raw reference 和 MIT ABI adapter，并
记录二者 hash。该目录被 Git 忽略。

构建 NEMU 还需要 GNU Make、C compiler、`libdl` 和 readline development
library。`make difftest` 会验证 sidecar hash、Profile、reset vector 和 image，
直接传入 raw NEMU `.so` 会失败。

当前 adapter 逐 commit 检查 PC、instruction 和 GPR，支持 OoO 同周期双
退休。它不验证完整 Linux device/MMIO/interrupt 等价，详见
[SoC 集成](soc-integration.md)。

## 输出与 Git clean

构建、trace、local NEMU 和用户镜像输出应位于 Git 忽略路径。运行后使用：

```sh
git status --short
```

受控 fresh clone 测试结束后，除被正确忽略的 `.config`、`build/` 与
`flows/local/` 外不得产生未跟踪文件。
