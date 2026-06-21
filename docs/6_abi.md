# NMTA ABI

This document defines the baseline Application Binary Interface (ABI) for the
NMTA RV32I + Zicsr + M-mode bare-metal environment.

The goal of this ABI is to make GNU-toolchain generated ELF files, the RTL
simulation harness, Spike reference runs, and future runtime libraries agree on
the same calling convention, memory map, startup contract, and system call
interface.

## Scope

The first software ABI targets the base CPU before vector/tensor ISA extensions
are exposed to C code.

| Item | ABI decision | Status |
| --- | --- | --- |
| ISA profile | `rv32i_zicsr` | Current |
| C ABI | `ilp32` | Current |
| Privilege mode | M-mode only | Current |
| Endianness | Little-endian | Current |
| Compressed instructions | Not supported | Current |
| Floating-point ABI | Not supported | Current |
| Atomics | Not supported | Current |
| Virtual memory | Not supported | Current |
| Runtime model | Bare-metal, SPM-resident ELF | Current |

Programs must be compiled with:

```sh
-march=rv32i_zicsr -mabi=ilp32
```

## Register ABI

NMTA follows the standard RISC-V ILP32 integer register convention.

| Register | ABI name | Role | Preserved across calls |
| --- | --- | --- | --- |
| `x0` | `zero` | Constant zero | Always zero |
| `x1` | `ra` | Return address | No |
| `x2` | `sp` | Stack pointer | Yes |
| `x3` | `gp` | Global pointer | Fixed by runtime |
| `x4` | `tp` | Thread pointer | Reserved |
| `x5`-`x7` | `t0`-`t2` | Temporaries | No |
| `x8`-`x9` | `s0/fp`-`s1` | Saved registers | Yes |
| `x10`-`x11` | `a0`-`a1` | Arguments / return values | No |
| `x12`-`x17` | `a2`-`a7` | Arguments | No |
| `x18`-`x27` | `s2`-`s11` | Saved registers | Yes |
| `x28`-`x31` | `t3`-`t6` | Temporaries | No |

Rules:

* `sp` must be 16-byte aligned at C function call boundaries.
* `gp` is initialized to `__global_pointer$` by startup code.
* `tp` is reserved for future thread-local storage and is not initialized by
  the current runtime.
* The current runtime calls `main(0, 0)`. `argc`, `argv`, and `envp` are not
  populated yet.

## Memory ABI

The GNU-toolchain and ELF harness environment maps the local SPM into the
RISC-V physical address space.

| Region | Address range | Status |
| --- | --- | --- |
| SPM | `0x8000_0000` - `0x800F_FFFF` | Current |
| First byte after SPM | `0x8010_0000` | Current |
| Reset PC | `0x8000_0000` | Current |

All code and data sections are linked into SPM by `sw/env/link.ld`. There is no
MMU, cache, ROM copy stage, DRAM loader, or DMA in the current base CPU flow.

The linker script exports the following ABI symbols:

| Symbol | Meaning | Status |
| --- | --- | --- |
| `__spm_origin` | SPM base address | Current |
| `__spm_length` | SPM size in bytes | Current |
| `__spm_end` | First byte after SPM | Current |
| `__data_start`, `__data_end` | Initialized data range | Current |
| `__bss_start`, `__bss_end` | BSS range cleared by startup | Current |
| `tohost`, `fromhost` | Host communication words | Current |
| `console_putchar` | Host console output mailbox | Current |
| `begin_signature`, `end_signature` | Optional test signature range | Current |
| `__heap_start`, `__heap_end` | Heap region for `_sbrk` | Current |
| `__stack_bottom`, `__stack_top` | Downward-growing stack range | Current |

Section placement is defined in `sw/env/link.ld` and summarized in
`docs/5_environment.md`.

## Startup ABI

The startup file is `sw/env/start.S`.

At reset:

1. PC starts at `0x8000_0000`.
2. `_start` sets `mtvec` to the default trap entry.
3. Interrupts are disabled.
4. `gp` is initialized from `__global_pointer$`.
5. `sp` is initialized to `__stack_top`.
6. `.bss` is cleared.
7. `main(0, 0)` is called.
8. The return value from `main` is passed to `_exit`.

Because the ELF harness loads allocated sections directly into SPM, initialized
`.data` is already present before reset is released. A future ROM or external
memory boot path must add load-memory-address symbols and a `.data` copy loop.

Current gaps:

| Feature | Reason it is not complete yet | Planned action |
| --- | --- | --- |
| C constructors | No `__libc_init_array` call yet | Add init/fini array sections and startup calls when using hosted C runtime features |
| C destructors | No `__libc_fini_array` call yet | Call from `_exit` if needed |
| `argc` / `argv` | No command-line block ABI yet | Define an optional SPM argument block |
| TLS | No thread model yet | Keep `tp` reserved |

## Program Exit ABI

Current `_exit` behavior:

1. Execute `ecall` with `a7 = 93`.
2. The M-mode trap handler recognizes syscall `93`.
3. The trap handler writes a riscv-tests-style status word to `tohost`.
4. The trap handler executes `fence` so the status store reaches SPM.
5. The trap handler enters a self-loop halt.

The `tohost` status word uses this encoding:

| Program result | Value written to `tohost` |
| --- | --- |
| `exit(0)` | `1` |
| `exit(code != 0)` | `(code << 1) | 1` |
| Unexpected trap | Current default trap handler writes `mcause` |

The current Verilator ELF harness finds the `tohost` symbol in the ELF symbol
table and watches SPM writes to that address. A nonzero `tohost` write is the
primary simulation termination condition. Repeated `jal x0, 0` self-loop
detection remains as a fallback halt condition.

Harness behavior:

1. Prefer `tohost != 0` as the architectural test result.
2. Decode `tohost == 1` as PASS.
3. Decode odd non-pass values as encoded exit failures.
4. Keep self-loop detection as a fallback timeout-friendly halt.
5. Future work: extract `begin_signature` - `end_signature` for riscv-tests
   style signature comparison.

## ECALL / Syscall ABI

`ecall` is treated as an M-mode bare-metal runtime call in the current CPU.

| Item | ABI definition | Status |
| --- | --- | --- |
| Trap cause | `mcause = 11`, environment call from M-mode | Current hardware |
| Syscall number | `a7` / `x17` | Defined |
| Arguments | `a0`-`a5` / `x10`-`x15` | Defined |
| Return value | `a0` / `x10` | Defined |
| Error return | Negative errno value in `a0` | Planned |
| Resume rule | Handler increments `mepc` by 4 and executes `mret` | Current for unsupported syscalls |

For resumable syscalls, the trap handler must preserve all architectural state
except the defined return registers. Normal C caller-saved registers may be
clobbered by the runtime implementation if the syscall is exposed through a C
wrapper.

### Syscall Compatibility Policy

NMTA does not implement the full RARS environment-call table as its baseline
ABI. RARS includes two different classes of calls:

* Linux/pk-style calls that are useful for GNU-toolchain integration, such as
  `read`, `write`, and `exit`.
* Education-simulator convenience calls inherited from MARS, such as
  `PrintInt`, `PrintString`, dialogs, MIDI, random numbers, and floating-point
  console services.

The NMTA baseline ABI implements only the Linux/pk-style subset needed by
bare-metal C programs, newlib stubs, and benchmark harnesses. RARS/MARS
convenience calls may be added later as an optional compatibility layer, but
they are not part of the architectural ABI.

Reasons not to make the complete RARS table mandatory:

* Many RARS calls are simulator UI features rather than hardware/runtime
  requirements.
* Several calls use floating-point registers, while the baseline core has no F
  or D extension.
* Dialog, MIDI, random, wall-clock, current-working-directory, and host file
  calls would make deterministic RTL regression harder.
* Basic C benchmarks normally need termination, optional console output, and
  heap support, not the full educational syscall surface.

### Final Baseline Syscall Set

The baseline syscall numbers stay close to the RISC-V Linux convention where
possible.

| Number | Name | Arguments | Return | Status |
| --- | --- | --- | --- | --- |
| `93` | `exit` | `a0 = status` | Does not return | Current |
| `64` | `write` | `a0 = fd`, `a1 = buf`, `a2 = count` | Bytes written or negative errno | Current |
| `63` | `read` | `a0 = fd`, `a1 = buf`, `a2 = count` | Bytes read, `0` for EOF, or negative errno | Current EOF stub |

The following are runtime hooks rather than required baseline `ecall`
operations:

| Hook | Implementation policy | Status |
| --- | --- | --- |
| `_sbrk` | Allocate locally from `__heap_start` to `__heap_end` | Current |
| `_close` | Return success for dummy descriptors or `-1` for unsupported descriptors | Current |
| `_lseek` | Return `0` for non-seekable stdio or `-1` for unsupported descriptors | Current |
| `_fstat` | Report character-device-like metadata for stdio | Current |
| `_isatty` | Return true for fd `0`, `1`, and `2` | Current |
| `_getpid` | Return a fixed process id, normally `1` | Current |
| `_kill` | Return `-1` | Current |

The following syscalls are optional future extensions:

| Number | Name | Reason |
| --- | --- | --- |
| `214` | `brk` | Useful if heap management is moved from local `_sbrk` to the trap/harness ABI. |
| `57` | `close` | Needed only if host file descriptors become real harness resources. |
| `62` | `lseek` | Needed only with host file support. |
| `56` | `openat` | Linux-like file open path; preferred over RARS-specific `open = 1024` if file I/O is needed. |
| `80` | `fstat` / related stat ABI | Needed only with richer newlib file support. |

Recommended file descriptor convention:

| FD | Meaning |
| --- | --- |
| `0` | stdin |
| `1` | stdout |
| `2` | stderr |

Initial implementation policy:

* `exit` is implemented in the startup trap handler and harness `tohost`
  monitor.
* `_write(1, ...)` and `_write(2, ...)` call `ecall` with syscall `64`.
  The M-mode trap handler reads the target buffer and writes each byte to the
  `console_putchar` mailbox. The mailbox is 64-byte aligned to avoid false
  console events from cacheline-sized SPM commits.
* `_read(0, ...)` calls `ecall` with syscall `63`, which returns `0` until
  interactive input is required.
* Unsupported syscalls should return `-ENOSYS`.
* `_sbrk` is implemented fully in `sw/env` using `__heap_start` and
  `__heap_end`, without issuing `ecall`.

RARS compatibility aliases such as `PrintInt = 1`, `PrintString = 4`,
`Sbrk = 9`, `Exit = 10`, `PrintChar = 11`, and `Open = 1024` are deliberately
excluded from the baseline. If assembly examples written for RARS need to run
unchanged, add a separate compatibility dispatcher and keep it clearly marked
as non-baseline.

## Newlib / C Runtime ABI

To run ordinary C benchmarks, `sw/env` should grow a small bare-metal runtime
library.

| Runtime hook | ABI behavior | Status |
| --- | --- | --- |
| `_exit(int status)` | Invoke syscall `93`; trap handler reports status through `tohost` | Current |
| `_write(int fd, const void *buf, size_t len)` | Invoke syscall `64`; trap handler prints fd `1`/`2` through `console_putchar` | Current |
| `_read(int fd, void *buf, size_t len)` | Invoke syscall `63`; trap handler returns EOF for fd `0` | Current |
| `_sbrk(ptrdiff_t inc)` | Allocate from `__heap_start` to `__heap_end` | Current |
| `_close`, `_lseek`, `_fstat`, `_isatty` | Minimal stubs for newlib | Current |
| `_kill`, `_getpid` | Minimal process stubs | Current |

The first implementation should prefer simple stubs that make freestanding
benchmarks and small `printf`-style demos work. Full POSIX semantics are out of
scope for the base CPU environment.

## Trap and Interrupt ABI

Current hardware supports precise trap redirection through M-mode CSRs. The
software ABI is still intentionally small.

| Trap type | Current software policy | Planned action |
| --- | --- | --- |
| Illegal instruction | Default trap handler writes `mcause` to `tohost` and halts | Add diagnostic status encoding |
| Misaligned instruction target | Same as above | Add directed tests and diagnostics |
| Misaligned load/store | Same as above | Add runtime-visible fault reporting if needed |
| Breakpoint | Same as above | Reserve for debugger or test halt |
| M-mode `ecall` | Syscall `93` exits; unsupported syscalls return `-ENOSYS` and resume | Add more syscalls |
| External/timer/software interrupt | Hardware path exists | Define runtime interrupt registration only when needed |
| `mret` | Hardware path exists | Used by future syscall and interrupt handlers |

Future syscall-capable trap handler policy:

1. Read `mcause`.
2. If `mcause == 11`, dispatch syscall by `a7`.
3. For syscall `93`, encode `a0` to `tohost`, execute `fence`, and halt.
4. For unsupported syscalls, store `-ENOSYS` in `a0`, advance `mepc` by 4,
   and execute `mret`.
5. For non-resumable traps, report through `tohost`, execute `fence`, and halt.

## Implementation Checklist

The ABI items still missing from code are:

| Priority | Item | Target files |
| --- | --- | --- |
| 1 | Signature dump extraction for riscv-tests | harness |
| 2 | Constructor/destructor array support | `sw/env/link.ld`, `sw/env/start.S` |
| 3 | Optional argument block for `argc` / `argv` | `sw/env/`, harness |
| 4 | Optional host file I/O syscalls | `sw/env/`, harness |

Until these items are implemented, C tests may use termination, stdout/stderr
output, stdin EOF, and heap allocation. They should not assume constructors,
destructors, command-line arguments, environment variables, real files, or
interactive input.
