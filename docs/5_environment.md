# Environment

This document specifies the environment configuration of the core and how the linker script is configured.

## Baseline Memory Model

The baseline software environment assumes that the CPU executes entirely from
the local Scratchpad Memory (SPM). There is no cache, MMU, virtual memory, DRAM
loader, or DMA in this stage.

* SPM base address: `0x8000_0000`
* SPM size: `1 MiB`
* SPM end address: `0x8010_0000`
* CPU reset PC: `0x8000_0000`
* Instruction and data addresses are both interpreted as SPM byte addresses.
* The hardware SPM bus still transfers cachelines internally. Software sees a
  flat byte-addressed memory region.

The GNU-toolchain and ELF harness flow maps SPM at `0x8000_0000`, matching the
common RISC-V bare-metal convention that keeps low addresses available for ROM,
debug, MMIO, or null-pointer fault detection. The legacy hand-written RTL
regression tests still use a 0-based SPM mapping so they can continue to verify
the original compact test binaries.

The Verilator CPU top-level testbenches instantiate the SPM with `MEM_BYTES =
1048576`. Smaller SPM sizes are still used by some unit-level testbenches to
keep focused tests compact and to preserve out-of-range access checks.

## Linker Script

The linker script for this environment follows the `riscv-tests` naming
convention:

* `sw/env/link.ld`

It places all executable and writable sections in the 1 MiB SPM address range.
The entry point is `_start`, and `.text.init` is placed first so that reset PC
`0x8000_0000` can immediately fetch the startup code.

## Section Layout

| Section | Placement | Purpose |
| --- | --- | --- |
| `.text.init` | SPM base, 64-byte aligned | Reset/startup code. This must contain `_start` or an initial branch to `_start`. |
| `.text` | After `.text.init`, 4-byte aligned | Normal executable code. |
| `.rodata` | After `.text`, 16-byte aligned | Constants and read-only data. |
| `.data` / `.sdata` | After `.rodata`, 16-byte aligned | Initialized writable data. |
| `.bss` / `.sbss` | After `.data`, 16-byte aligned | Zero-initialized writable data. Startup code must clear this range. |
| `.tohost` | After `.bss`, 64-byte aligned | Optional riscv-tests style host communication and console mailbox area. |
| `.signature` | After `.tohost`, 16-byte aligned | Optional signature dump area for ISA tests. |
| heap | After `.signature` | Available dynamic allocation region. |
| stack | Top of SPM | Downward-growing runtime stack. |

The linker script exports these symbols for startup code and syscall stubs:

| Symbol | Meaning |
| --- | --- |
| `__spm_origin` | SPM base address. |
| `__spm_length` | SPM size in bytes. |
| `__spm_end` | First byte after SPM. |
| `__data_start`, `__data_end` | Initialized data range. |
| `__bss_start`, `__bss_end` | BSS range to clear at boot. |
| `__heap_start`, `__heap_end` | Heap region available to `_sbrk`. |
| `__stack_bottom`, `__stack_top` | Reserved stack range. |
| `tohost`, `fromhost` | Optional riscv-tests host communication words. |
| `console_putchar` | 32-bit host console mailbox watched by the RTL harness. |
| `begin_signature`, `end_signature` | Optional signature memory range. |

The default stack reservation is `16 KiB`. It can be overridden at link time by
defining `__stack_size`, for example:

```sh
riscv32-unknown-elf-gcc \
  -march=rv32i_zicsr -mabi=ilp32 -nostdlib \
  -Wl,-T,sw/env/link.ld \
  -Wl,--defsym=__stack_size=0x8000 \
  ...
```

## Toolchain ISA Options

Even if the installed GNU toolchain supports wider RISC-V profiles, programs
for this core must be compiled for the implemented ISA subset:

```sh
-march=rv32i_zicsr -mabi=ilp32
```

Do not compile with `rv32gc`, `rv32im`, or compressed instruction support until
the corresponding hardware extensions are implemented. The CPU currently
fetches and decodes one 32-bit instruction per instruction address.

## Boot Responsibilities

The linker script only decides where sections live. The startup code still must
perform the runtime initialization:

1. Set `sp = __stack_top`.
2. Set `gp = __global_pointer$` if small data is used.
3. Clear memory from `__bss_start` to `__bss_end`.
4. Call `main` or jump to the test body.
5. Exit through the agreed test ABI, such as `ecall a7=93`, a `tohost` write,
   or a self-loop halt used by the current Verilator tests.

The default startup file is:

* `sw/env/start.S`

All firmware support code for this environment should live under `sw/env/`.
The startup file is intentionally limited to RV32I + Zicsr instructions. It
initializes `mtvec`, disables interrupts, sets `gp`, sets `sp` to
`__stack_top`, clears `.bss`, calls `main(0, 0)`, and then exits through
`_exit`.

The `_exit` routine executes `ecall` with `a7 = 93`. The M-mode trap handler
then writes a riscv-tests-style status word to `tohost`, executes `fence` so the
store reaches SPM, and enters a self-loop halt.

The `.tohost` area also contains `console_putchar`, a 32-bit mailbox used by
the minimal `_write` runtime hook. It is placed on its own 64-byte cacheline so
cacheline-sized SPM store commits cannot be mistaken for console writes.

Because the ELF harness loads allocated sections directly into their SPM
addresses, `.data` is already initialized before reset is released. If a future
boot flow loads code from ROM or external memory, the linker script and startup
code should be extended with load-memory-address symbols and a `.data` copy
loop.

## ELF Simulation Harness

The ELF simulation harness lives in `harness/` and is built through the top-level
Makefile.

```sh
make harness
make run_harness_elf ELF=<program.elf> MAX_CYCLES=10000
```

The initial harness supports the minimum flow required for GNU-toolchain
integration:

1. Read a 32-bit little-endian RISC-V ELF file.
2. Load every allocated ELF section into the 1 MiB SPM image.
3. Zero `SHT_NOBITS` sections such as `.bss`, `.tohost`, and `.stack`.
4. Preload touched SPM cachelines through the RTL SPM bus.
5. Release the CPU and print committed instructions.
6. Print characters written to the `console_putchar` mailbox.
7. Stop when a nonzero `tohost` write is observed, when the same `jal x0, 0`
   self-loop commits three times, or on timeout.

The harness is intentionally small for the first integration step. Future
extensions should add waveform control, signature extraction, and richer
riscv-tests result reporting.
