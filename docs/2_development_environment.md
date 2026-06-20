# Development Environment

## 개요

|Requirements               |Description                |
|---------------------------|---------------------------|
|Language                   |SystemVerilog / Verilog    |
|Build Environment          |GNU Make (Makefile)        |
|RTL Testbench Compiler     |Verilator                  |
|RTL Synthesis Tool (FPGA)  |Vivado (Alveo U280 Board)  |
|RTL Synthesis Tool (ASIC)  |Synopsys Design Compiler   |

## 디자인 목표

* 합성이 가능한 디자인을 생성하는 것을 목표로 한다. (ASIC / FPGA)
* 1차 목표는 RV32I + Zicsr + M-mode privileged architecture 기반의 단일 CPU 코어를 구현하는 것이다.
* 1차 CPU 구현은 캐시를 사용하지 않는다. 모든 instruction fetch 및 data load/store는 SPM(Scratchpad Memory)에 직접 접근한다고 가정한다.
* 1차 CPU 구현에서는 오프칩 DRAM 및 DMA(memory copy between DRAM and SPM)를 고려하지 않는다. 모든 유효한 메모리 주소는 SPM 주소로 취급한다.
* 온칩 메모리는 FPGA 타겟에서는 BRAM(Block RAM)으로 합성되도록 하며, ASIC 타겟에서는 SRAM으로 합성되도록 한다.
* 오프칩 메모리는 향후 FPGA 타겟에서 Xilinx에서 제공하는 버스 및 메모리 컨트롤러 인터페이스를 활용한다. ASIC 1차 CPU 구현에서는 제외한다.
* FPGA의 경우 타겟 보드는 Xilinx Alveo U280 보드이다.

## 설계 워크플로우

전체 개발은 먼저 RV32I CPU를 안정화하고, 이후 NPU 확장 기능을 단계적으로 추가하는 방식으로 진행한다.

### 1. Base CPU RTL 설계

다음 순서대로 RV32I + Zicsr + M-mode privileged architecture 기반 CPU를 설계한다.

1. SPM(Scratchpad Memory) with Bus Interface
2. CPU Architectural State
3. Instruction Fetch Unit
4. Instruction Decode Unit
5. ALU / Branch / Jump Execute Datapath
6. Load/Store Unit for SPM
7. Writeback and Commit Logic
8. CSR File and Zicsr Instructions
9. Trap / Exception / Interrupt / MRET Logic
10. ECALL-based Baremetal System Call Path
11. Base CPU Integration Testbench

#### 1.1 SPM with Bus Interface

* Instruction fetch와 data load/store가 모두 접근할 수 있는 SPM 인터페이스를 정의한다.
* 초기 구현에서는 모든 메모리 주소가 SPM 주소라고 가정한다.
* CPU 관점의 SPM 접근 단위, byte enable, read/write latency, ready/valid handshake를 명확히 정의한다.
* 초기 구현은 단순 fixed-latency SPM으로 시작할 수 있으며, multi-bank 구조와 arbitration은 이후 확장한다.

#### 1.2 CPU Architectural State

* Program Counter(PC)를 정의한다.
* RV32I integer register file `x0`-`x31`을 구현한다.
* `x0`는 항상 0으로 유지한다.
* M-mode privileged architecture를 위한 CSR state를 정의한다.
* 최소 CSR은 `mstatus`, `misa`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`, `mhartid`, `mcycle`, `minstret`로 한다.

#### 1.3 Instruction Fetch Unit

* PC를 사용해 SPM에서 32-bit instruction을 fetch한다.
* 초기 구현에서는 prefetch buffer를 사용하지 않아도 된다.
* branch, jump, trap, `mret`에 의해 PC가 변경될 때 fetch 흐름을 flush할 수 있어야 한다.
* instruction address misalignment가 발생하면 exception을 발생시킨다.

#### 1.4 Instruction Decode Unit

* RV32I의 R/I/S/B/U/J type instruction을 decode한다.
* immediate generator, register source/destination selection, ALU operation, branch condition, load/store width, writeback source를 생성한다.
* Zicsr instruction과 system instruction(`ecall`, `ebreak`, `mret`)을 decode한다.
* 지원하지 않는 instruction은 illegal instruction exception으로 처리한다.

#### 1.5 ALU / Branch / Jump Execute Datapath

* RV32I integer ALU operation을 구현한다.
* branch condition 비교와 branch target 계산을 구현한다.
* `jal`, `jalr`, `auipc`, `lui`를 포함한 PC-relative datapath를 구현한다.
* 초기 구현에서는 branch predictor와 BTB를 사용하지 않는다. branch/jump 결과가 확정되면 PC를 갱신하고 잘못 fetch된 instruction을 flush한다.

#### 1.6 Load/Store Unit for SPM

* `lb`, `lh`, `lw`, `lbu`, `lhu`, `sb`, `sh`, `sw`를 SPM 접근으로 처리한다.
* load 결과에 대해 sign extension 및 zero extension을 수행한다.
* store에 대해 byte enable을 생성한다.
* 초기 구현에서는 misaligned load/store를 exception으로 처리한다.

#### 1.7 Writeback and Commit Logic

* ALU, load, CSR, PC+4 결과를 register file에 writeback한다.
* `x0`에 대한 write는 무시한다.
* instruction commit 시 `minstret`를 증가시킨다.
* exception이 발생한 instruction은 일반 writeback을 수행하지 않는다.

#### 1.8 CSR File and Zicsr Instructions

* `csrrw`, `csrrs`, `csrrc`, `csrrwi`, `csrrsi`, `csrrci`를 구현한다.
* CSR read-modify-write 동작은 architectural state 관점에서 atomic하게 보이도록 한다.
* read-only CSR에 대한 write, 존재하지 않는 CSR 접근, 권한이 맞지 않는 CSR 접근은 illegal instruction exception으로 처리한다.
* `mcycle`은 cycle마다 증가시키고, `minstret`는 commit된 instruction마다 증가시킨다.

#### 1.9 Trap / Exception / Interrupt / MRET Logic

* 최소 exception은 illegal instruction, instruction address misaligned, load address misaligned, store address misaligned, breakpoint, environment call from M-mode를 지원한다.
* trap 발생 시 `mepc`, `mcause`, `mtval`, `mstatus`를 갱신하고 PC를 `mtvec`로 변경한다.
* `mret` 실행 시 `mepc`로 복귀하고 `mstatus`의 interrupt/privilege state를 복원한다.
* 초기 구현에서는 interrupt source를 단순화할 수 있으나, `mie`, `mip`, `mstatus.MIE`의 구조는 확장 가능하도록 유지한다.

#### 1.10 ECALL-based Baremetal System Call Path

* `ecall`은 M-mode baremetal runtime call로 처리한다.
* `ecall` 발생 시 `mcause=11`을 기록한다.
* syscall ABI는 `a7`(`x17`)을 syscall id, `a0`-`a5`(`x10`-`x15`)를 argument, `a0`를 return value로 사용한다.
* trap handler는 syscall 처리 후 `mepc`를 다음 instruction으로 갱신하고 `mret`으로 복귀한다.

#### 1.11 Base CPU Integration Testbench

* Verilator testbench는 SPM에 instruction/data image를 preload하고 CPU를 실행한다.
* RV32I instruction별 directed test를 작성한다.
* CSR, exception, `ecall`, `mret` 동작을 별도 test로 검증한다.
* 테스트 종료 방식은 SPM 내 memory-mapped test status 또는 `ecall` 기반 종료 convention으로 정의한다.

### 2. Base CPU 성능 구조 확장

Base CPU의 functional correctness가 검증된 뒤 다음 구조를 추가한다.

1. Instruction Prefetch Buffer
2. Multi-bank SPM and Arbitration
3. Branch Predictor and Branch Target Buffer
4. Pipeline Stage Refinement
5. Hazard Detection and Forwarding

* 위 기능들은 기능 정확성보다 성능 및 구조 확장성을 위한 항목이다.
* 각 기능을 추가할 때 기존 RV32I, CSR, trap test가 regression으로 통과해야 한다.

### 3. 소프트웨어 스택 구성 및 테스트케이스 기반 검증

* RISC-V GNU toolchain을 기반으로 baremetal binary를 생성한다.
* linker script는 instruction/data가 SPM address map에 배치되도록 작성한다.
* startup code는 stack pointer 초기화, `mtvec` 설정, trap handler 설치를 수행한다.
* C runtime 없이 동작하는 최소 kernel/runtime library를 작성한다.
* assembly directed test에서 시작해 C 기반 baremetal test로 확장한다.

### 4. NPU 확장 RTL 설계

Base CPU와 SPM 기반 실행 환경이 안정화된 뒤 다음 NPU 구성 요소를 설계한다.

1. DMA Engine for DRAM-SPM Memory Copy
2. TPU/VPU Custom Instruction Decode
3. TPU/VPU Frontend (Command Queue, Dependency Tracking, Reorder Logic)
4. TPU (Tensor Processing Unit)
5. VPU (Vector Processing Unit)
6. CPU-TPU/VPU Integration

* DMA는 SPM과 오프칩 DRAM 사이의 데이터 이동을 담당한다.
* TPU/VPU 명령어는 base CPU에서 decode한 뒤 command queue로 전달한다.
* TPU/VPU load/store 및 execute 명령 사이의 ordering과 dependency tracking 규칙을 명확히 정의한다.

### 5. 전체 NPU 통합 검증

* RV32I base CPU test를 regression으로 유지한다.
* TPU/VPU 단위 테스트를 작성한다.
* DMA, TPU, VPU, SPM이 동시에 동작하는 통합 테스트를 작성한다.
* RISC-V baremetal software stack과 custom kernel library를 통합한다.
* kernel library를 통해 vector/tensor 연산 test binary를 생성하고 성능을 측정한다.

### 6. 멀티코어 구성 검증

* 여러 개의 NPU 코어를 활용한 scale-out 아키텍처를 구성한다.
* 각 코어의 SPM을 글로벌 memory address map에 노출한다.
* NoC 기반 원격 SPM 접근과 atomic operation을 검증한다.
* 원격 메모리 접근의 coherency는 소프트웨어가 보장하며, 하드웨어는 coherency를 보장하지 않는다.
* 멀티코어 상에서 baremetal software와 NPU kernel library를 실행해 통합 검증을 수행한다.
