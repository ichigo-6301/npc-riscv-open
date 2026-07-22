/* SPDX-License-Identifier: MIT
 * Bounded M-mode architectural smoke for the frozen RV32IMA/Sv32 source set.
 * This is deliberately not presented as a Linux boot or full Sv32 test.
 */

    .section .text.init
    .globl _start
    .option norvc
_start:
    lui  t0, 0x80010
    addi t1, x0, 5
    sw   t1, 0(t0)

1:  lr.w t2, (t0)
    addi t2, t2, 1
    sc.w t3, t2, (t0)
    bne  t3, x0, 1b
    lw   t4, 0(t0)
    addi t5, x0, 6
    bne  t4, t5, fail

    /* Exercise implemented machine CSR read/write paths without changing
       privilege or address translation state. */
    csrr t1, mstatus
    csrw mscratch, t1
    csrr t2, mscratch
    bne  t1, t2, fail

    ebreak

fail:
    jal x0, fail
