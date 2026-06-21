/*
 * Minimal RV32I + Zicsr startup code for the SPM-only NMTA environment.
 *
 * Responsibilities:
 *   - enter from reset PC 0x8000_0000
 *   - initialize gp and sp
 *   - clear .bss
 *   - call main(0, 0)
 *   - report the returned exit code through the M-mode ecall ABI
 *
 * The ELF harness loads allocated sections directly into SPM, so .data does
 * not need a ROM-to-RAM copy in this environment.
 */

    .option norvc

    .section .text.init, "ax", @progbits
    .align 6
    .globl _start
    .type _start, @function
_start:
    la      t0, trap_entry
    csrw    mtvec, t0
    csrwi   mstatus, 0
    csrwi   mie, 0

    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    la      sp, __stack_top

    la      t0, __bss_start
    la      t1, __bss_end
1:
    bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b

2:
    addi    a0, zero, 0
    addi    a1, zero, 0
    jal     ra, main
    jal     zero, _exit

    .size _start, . - _start

    .section .text, "ax", @progbits
    .align 2
    .globl _exit
    .type _exit, @function
_exit:
    addi    a7, zero, 93
    ecall

    /* ecall exit should not return. Keep a fallback halt for robustness. */
1:
    j       1b
    .size _exit, . - _exit

    .align 2
    .weak main
    .type main, @function
main:
    addi    a0, zero, 0
    jalr    zero, 0(ra)
    .size main, . - main

    .align 2
    .globl trap_entry
    .type trap_entry, @function
trap_entry:
    csrr    t0, mcause
    addi    t1, zero, 11
    beq     t0, t1, handle_ecall

    /* Non-resumable trap: publish mcause and halt. */
    la      t0, tohost
    csrr    t1, mcause
    sw      t1, 0(t0)
    fence

1:
    j       1b

handle_ecall:
    addi    t0, zero, 93
    beq     a7, t0, handle_exit
    addi    t0, zero, 64
    beq     a7, t0, handle_write
    addi    t0, zero, 63
    beq     a7, t0, handle_read

    /* Unsupported syscall: return -ENOSYS and resume after ecall. */
    addi    a0, zero, -38
    j       resume_syscall

handle_write:
    addi    t0, zero, 1
    beq     a0, t0, 1f
    addi    t0, zero, 2
    beq     a0, t0, 1f
    addi    a0, zero, -1
    j       resume_syscall
1:
    add     t5, a2, zero
    add     t6, a2, zero
    la      t4, console_putchar
2:
    beq     t6, zero, 3f
    lbu     t3, 0(a1)
    sw      t3, 0(t4)
    fence
    addi    a1, a1, 1
    addi    t6, t6, -1
    j       2b
3:
    add     a0, t5, zero
    j       resume_syscall

handle_read:
    beq     a0, zero, 1f
    addi    a0, zero, -1
    j       resume_syscall
1:
    addi    a0, zero, 0

resume_syscall:
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    mret

handle_exit:
    la      t0, tohost
    beq     a0, zero, 2f
    slli    t1, a0, 1
    ori     t1, t1, 1
    j       3f
2:
    addi    t1, zero, 1
3:
    sw      t1, 0(t0)
    fence

4:
    j       4b
    .size trap_entry, . - trap_entry
