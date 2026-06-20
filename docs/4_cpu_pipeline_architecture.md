# CPU Pipeline Architecture

This document specifies the baseline microarchitecture of the RV32I + Zicsr + M-mode CPU.

The initial implementation uses a 3-stage in-order pipeline. This is sufficient for the first RV32I CPU because the ISA subset does not include long-latency multiply/divide instructions and all memory accesses are routed to SPM through ready/valid interfaces. If timing closure later shows that the IF/ID decode path, EX branch path, or MEM cacheline datapath is too long, the pipeline can be extended after reviewing the measured timing report.


## Design Scope

The baseline CPU has the following assumptions.

* ISA: RV32I + Zicsr.
* Privilege: M-mode only.
* Memory system: no cache, no MMU, no virtual memory.
* Valid memory addresses are treated as SPM addresses.
* Instruction fetch and data load/store access SPM by cacheline through the SPM bus.
* The CPU is single issue, in-order, and commits instructions in program order.
* The baseline implementation prioritizes functional correctness and clean control over maximum IPC.


## Pipeline Overview

The CPU is composed of 3 pipeline stages.

1. IF/ID stage
2. EX stage
3. MEM/WB stage

Write-back is performed at the architectural boundary between MEM/WB and IF/ID. The register file supports one write port and two read ports. A write in the current cycle must be visible to a same-cycle or following decode read through either write-first register file behavior or explicit writeback bypass logic. The implementation should use explicit bypass when the target synthesis memory style is ambiguous.

The pipeline carries a `valid` bit in each stage register. A stage with `valid=0` is a bubble and must not update architectural state.


## Stage 1: IF/ID Stage

### PC State

The PC is architectural control state managed by the instruction fetch path.

* Reset PC is implementation parameterized. The initial value should default to `0x0000_0000`.
* PC is always 4-byte aligned for RV32I instruction fetch.
* Sequential PC is `pc + 4`.
* Redirect PC sources are branch/jump result, trap vector, and `mret` return address.
* If an instruction fetch address is not 4-byte aligned, the pipeline raises an instruction address misaligned exception.
* If the SPM bus returns an instruction fetch error, the pipeline raises an instruction access fault or implementation-defined fetch fault.

Redirect priority is:

1. Trap entry
2. `mret`
3. Taken branch / jump
4. Sequential PC

### Instruction Fetcher

The instruction fetcher reads instruction cachelines from SPM and selects a 32-bit instruction by PC word offset.

* SPM bus requests use cacheline address, not byte address.
* Cacheline size is 16 words, or 64 bytes.
* `line_addr = pc[31:6]`.
* `word_offset = pc[5:2]`.
* The fetcher contains a one-entry prefetch buffer with `{valid, line_addr, line_data}`.
* If the requested PC hits the prefetch buffer, no SPM request is sent.
* If the requested PC misses the prefetch buffer, IF/ID stalls until the requested cacheline returns.
* On redirect, any pending or buffered instruction from the wrong path must not enter EX. The cacheline buffer itself may remain valid if its line address matches a future PC.
* The fetcher exposes a snoop query for the cacheline containing the current PC.
* If the snoop path reports a stall for the queried line, the fetcher must not issue an SPM request or emit an instruction from its prefetch buffer for that line.
* If an invalidate arrives for a buffered cacheline, the fetcher invalidates the matching prefetch buffer entry and any held output instruction from that line.
* If an invalidate arrives for an outstanding SPM request, the corresponding response is discarded and the line is fetched again after the snoop stall is released.

The fetcher output to decode is:

* `if_id_valid`
* `if_id_pc`
* `if_id_instr`
* `if_id_exception_valid`
* `if_id_exception_cause`
* `if_id_exception_tval`

### Instruction Decoder

The decoder generates control signals for RV32I, Zicsr, and system instructions.

* Decode R/I/S/B/U/J instruction formats.
* Generate immediate values.
* Select source registers `rs1` and `rs2`.
* Select destination register `rd`.
* Generate ALU operation.
* Generate branch/jump operation.
* Generate load/store width and sign extension mode.
* Generate CSR operation.
* Detect `ecall`, `ebreak`, and `mret`.
* Detect illegal instruction.

Unsupported instructions raise illegal instruction exception before modifying architectural state.

### Register File Read and Write-back

The register file is read in IF/ID and written from MEM/WB.

* `x0` always reads as zero.
* Writes to `x0` are ignored.
* Decode reads two source operands.
* MEM/WB writes one destination register.
* Same-cycle read-after-write to the same register must return the writeback value using explicit bypass or equivalent behavior.


## Stage 2: EX Stage

The EX stage performs integer execution and branch resolution.

### ALU

The ALU supports all RV32I integer operations.

* Arithmetic: `add`, `sub`, `addi`.
* Logical: `and`, `or`, `xor`, `andi`, `ori`, `xori`.
* Shift: `sll`, `srl`, `sra`, `slli`, `srli`, `srai`.
* Compare: `slt`, `sltu`, `slti`, `sltiu`.
* Upper immediate: `lui`, `auipc`.

### Branch and Jump

The EX stage resolves control flow.

* Branch conditions are evaluated in EX.
* Branch target is `pc + branch_imm`.
* `jal` target is `pc + jal_imm`.
* `jalr` target is `(rs1 + jalr_imm) & ~1`.
* `jal` and `jalr` write `pc + 4` to `rd`.
* Taken branch and jump redirect the fetcher and flush younger IF/ID contents.
* Misaligned branch or jump target raises instruction address misaligned exception if the target is not 4-byte aligned.

### CSR and System Preparation

CSR instructions are decoded in IF/ID and prepared in EX.

* CSR read value may be obtained from the CSR file in EX or MEM/WB depending on implementation timing.
* CSR write data is computed from the old CSR value and source operand or immediate.
* CSR access legality is checked before commit.
* `ecall`, `ebreak`, illegal instruction, and misaligned target exceptions are forwarded to MEM/WB for precise trap commit.
* `mret` is treated as a redirecting system instruction and must not retire until older instructions have committed.


## Stage 3: MEM/WB Stage

The MEM/WB stage handles SPM data access, final result selection, CSR state update, trap entry, and architectural commit.

### Load/Store Unit

The load/store unit accesses SPM by cacheline.

* `line_addr = addr[31:6]`.
* `word_offset = addr[5:2]`.
* Byte offset inside the selected word is `addr[1:0]`.
* Loads support `lb`, `lh`, `lw`, `lbu`, `lhu`.
* Stores support `sb`, `sh`, `sw`.
* Misaligned `lh/lhu/sh` and `lw/sw` raise load/store address misaligned exceptions.
* Stores are staged in a one-entry cacheline store buffer.
* A store hit updates the staged cacheline in the store buffer.
* A store miss first commits a dirty staged cacheline to SPM, then reads the target cacheline and merges the store data into the buffer.
* Byte-level and halfword-level stores are implemented by read-modify-write of the selected 32-bit word inside the staged cacheline.
* Loads stall MEM/WB until data returns from SPM.
* Stores stall MEM/WB until the write response returns from SPM.
* While MEM/WB is stalled by SPM, earlier pipeline stages must also stall unless a later decoupling buffer is explicitly added.
* Loads to a cacheline staged in the store buffer read from the store buffer, not from SPM.
* The LSU exposes an explicit flush request to commit a dirty store buffer to SPM.
* The LSU also exposes an instruction-fetch snoop interface. If instruction fetch needs a cacheline that is dirty in the LSU store buffer, the LSU commits that cacheline to SPM and requests the frontend to stall instruction fetch until the commit is complete.

The first implementation uses a one-entry data cacheline buffer. More aggressive multi-entry coalescing can be added later after the base CPU is correct.

### Write-back

The final writeback source is selected in MEM/WB.

* ALU result.
* Load result.
* CSR old value.
* `pc + 4` for `jal` and `jalr`.
* Upper immediate result for `lui` and `auipc`.

An instruction writes `rd` only if:

* the pipeline entry is valid,
* the instruction has a register destination,
* `rd != x0`,
* no exception is taken for that instruction.

### CSR Commit

CSR state is updated in MEM/WB so that CSR instructions, trap entry, `mret`, and `minstret` remain precise.

* Zicsr instructions perform read-modify-write atomically at commit.
* Illegal CSR access raises illegal instruction exception and does not update the target CSR.
* `mcycle` increments every cycle.
* `minstret` increments only for instructions that retire without exception.
* Trap entry updates `mepc`, `mcause`, `mtval`, and `mstatus`.
* `mret` restores interrupt enable state and redirects PC to `mepc`.


## Hazard Handling

The baseline pipeline is in-order and uses simple stall plus forwarding logic.

### Data Hazards

* EX-to-EX forwarding is required for ALU results consumed by the next instruction.
* MEM/WB-to-EX forwarding is required for ALU, CSR, and load results.
* A load-use dependency stalls IF/ID and EX until the load data is available.
* CSR-use dependencies stall or forward from MEM/WB if a following instruction depends on a CSR instruction result written to `rd`.
* Writes to `x0` do not create dependencies.

### Structural Hazards

Instruction fetch and data access use separate SPM bus client ports.

* Different bank groups may proceed in parallel.
* Same-bankgroup conflicts are arbitrated by the SPM bank group, with data access taking priority over instruction fetch.
* If instruction fetch is denied by SPM arbitration, IF/ID stalls.
* If data access is denied or waiting for response, MEM/WB stalls and back-pressures the pipeline.

### Control Hazards

Branches and jumps resolve in EX.

* Not-taken branch has no redirect.
* Taken branch or jump flushes IF/ID younger work.
* Trap entry flushes all younger work.
* `mret` flushes all younger work and redirects to `mepc`.

Flush priority is higher than ordinary stall. If a stage is both stalled and flushed, the flushed instruction must not commit later.


## Exception and Trap Model

The CPU must provide precise traps.

* Exceptions are associated with the instruction that caused them.
* Younger instructions are flushed on trap.
* Older instructions commit before the trap is taken.
* The faulting instruction does not perform normal register writeback or store commit.
* `mepc` receives the faulting instruction PC.
* `mcause` receives the exception or interrupt cause.
* `mtval` receives the faulting address or illegal instruction value when applicable.

Minimum exception support:

* Instruction address misaligned.
* Illegal instruction.
* Breakpoint.
* Load address misaligned.
* Store address misaligned.
* Environment call from M-mode.

Interrupts are sampled at instruction boundaries. An interrupt is taken only when `mstatus.MIE` and the corresponding `mie`/`mip` bit are set.


## Stage Register Contents

The IF/ID to EX pipeline register should carry:

* Valid bit.
* PC.
* Instruction.
* Decoded source/destination register IDs.
* Source operand values.
* Immediate.
* ALU operation.
* Branch/jump control.
* Load/store control.
* CSR control.
* System instruction control.
* Exception metadata.

The EX to MEM/WB pipeline register should carry:

* Valid bit.
* PC.
* Instruction.
* Destination register ID.
* Register write enable.
* ALU result.
* Store data.
* Load/store address and access size.
* Branch/jump redirect request and target.
* CSR operation metadata.
* Exception metadata.
* `pc + 4`.


## Timing Considerations

The 3-stage design is the baseline. It is expected to be feasible for the first implementation because the CPU is scalar, in-order, and RV32I-only.

Potential timing-critical paths are:

* IF/ID: instruction select from cacheline, decode, register read, hazard decision.
* EX: operand forwarding, ALU operation, branch compare, branch target calculation.
* MEM/WB: cacheline word select, load sign extension, store read-modify-write data generation, writeback mux.
* CSR: CSR read-modify-write and trap priority logic.

If timing violation is observed, the preferred extension path is:

1. Split IF and ID into separate stages.
2. Move CSR read/legality check earlier or register CSR outputs.
3. Split MEM and WB if load/store data formatting or CSR commit becomes timing-critical.

The pipeline depth must not be changed without updating this document and the corresponding testbench expectations.


## Future Extensions

The following features are intentionally not required for the first CPU pipeline implementation.

* Multi-entry instruction prefetch queue.
* Branch predictor and BTB.
* Multi-entry read/write coalescing for the data fetcher.
* Snoop filter for TPU/VPU writers beyond the baseline LSU-to-instruction-fetch dirty-line flush.
* Non-blocking load/store unit.
* Out-of-order memory completion.

These features can be added after the base RV32I + Zicsr + M-mode pipeline passes directed instruction, CSR, trap, and baremetal tests.
