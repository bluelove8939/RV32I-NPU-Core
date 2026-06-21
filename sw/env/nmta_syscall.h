#ifndef NMTA_SYSCALL_H
#define NMTA_SYSCALL_H

#include <stddef.h>
#include <stdint.h>

#define NMTA_SYS_READ   63
#define NMTA_SYS_WRITE  64
#define NMTA_SYS_EXIT   93
#define NMTA_SYS_BRK    214

#define NMTA_ENOSYS     38

static inline long nmta_ecall0(long sysno)
{
    register long a7 asm("a7") = sysno;
    register long a0 asm("a0");
    asm volatile ("ecall" : "=r"(a0) : "r"(a7) : "memory");
    return a0;
}

static inline long nmta_ecall1(long sysno, long arg0)
{
    register long a7 asm("a7") = sysno;
    register long a0 asm("a0") = arg0;
    asm volatile ("ecall" : "+r"(a0) : "r"(a7) : "memory");
    return a0;
}

static inline long nmta_ecall3(long sysno, long arg0, long arg1, long arg2)
{
    register long a7 asm("a7") = sysno;
    register long a0 asm("a0") = arg0;
    register long a1 asm("a1") = arg1;
    register long a2 asm("a2") = arg2;
    asm volatile ("ecall"
                  : "+r"(a0)
                  : "r"(a7), "r"(a1), "r"(a2)
                  : "memory");
    return a0;
}

#endif
