# ISA Extension

베이스 명령어셋인 RV32I 이외의 다른 명령어들을 정리한 문서이다.

## Direct Memory Access (DMA)

### Instructions

|Name           |Type   |Description    |
|---            |---    |---            |
|nmta.dma.cv    |S      |(copy vector)  Copy a single vector (64B) from the off-chip address (imm + rs1) to the on-chip address (rd)|
|nmta.dma.cm    |S      |(copy matrix)  Copy a single matrix (2KB) from the off-chip address (imm + rs1) to the on-chip address (rd)|

## Tensor Processing

### T Type Instruction

|Fleid      |Range  |Description    |
|---        |---    |---            |
|opcode     |6:0    |?|
|funct      |14:12  |Function code of each instruction (preload/execute/flush)|
|rs1        |19:15  |First source tensor register|
|rs2        |24:20  |Second source tensor register (only for execute)|
|rd         |11:7   |Destination tensor register (only for flush)|

### Instructions