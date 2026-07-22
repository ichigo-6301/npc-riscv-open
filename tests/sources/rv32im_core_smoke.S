/* SPDX-License-Identifier: MIT
 * Deterministic RV32IM self-check used by all three public profiles.
 * Any mismatch loops until the public watchdog fires; only the final ebreak
 * is a successful terminal event.
 */

    .section .text.init
    .globl _start
    .option norvc
_start:
    addi x16, x0, 1
    addi x17, x16, 2
    add  x18, x16, x17
    addi t0, x0, 4
    bne  x18, t0, fail

    /* High-register WAW/RAW coverage. */
    addi x31, x0, 9
    addi x31, x31, 3
    add  x30, x31, x18
    addi t0, x0, 16
    bne  x30, t0, fail

    /* Load/store coverage in the public sparse PMEM window. */
    lui  t1, 0x80010
    sw   x30, 0(t1)
    lw   t2, 0(t1)
    bne  t2, x30, fail
    sh   x18, 4(t1)
    lhu  t2, 4(t1)
    bne  t2, x18, fail

    /* M-extension coverage. */
    addi t3, x0, 6
    addi t4, x0, 7
    mul  t5, t3, t4
    addi t6, x0, 42
    bne  t5, t6, fail
    div  t5, t6, t3
    bne  t5, t4, fail
    rem  t5, t6, t4
    bne  t5, x0, fail

    ebreak

fail:
    jal x0, fail
