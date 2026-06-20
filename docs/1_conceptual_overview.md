# Conceptual Overview

이 프로젝트는 RISC-V ISA (RV32I)를 기반으로하는 NPU 코어를 설계하는 프로젝트이다. 개발할 하드웨어의 아키텍처는 다음 특징을 갖는다.

## 명령어 및 마이크로아키텍처

* RV32I + Zicsr + Machine mode only를 1차 목표로 둔다. ECALL은 M-mode baremetal runtime call로 처리하고, mcause=11을 사용한다. syscall ABI는 a7=syscall_id, a0-a5=args, a0=return으로 정의한다. 추후 U-mode를 추가하면 user program의 ECALL은 mcause=8로 trap되어 M-mode runtime이 처리하도록 확장한다.
* RV32I ISA를 지원하는 CPU에 행렬 및 벡터 연산 처리를 위한 명령어와 온칩 메모리와 오프칩 메인 메모리 사이 데이터를 복사하는 명령어가 추가된다.
* 벡터 연산기는 RVV(RISC-V Vector Extension)와는 다르다. VLEN이 특정 값으로 고정되고 DL 워크로드에 널리 활용되는 일부 연산(Softmax, GeLU, Exponential 등)에 특화된다.
* 텐서 연산기는 $32 \times 32$ 정방행렬곱과 elementwise 연산을 지원한다.
* CPU 구조는 in-order를 기준으로 하되, 행렬 및 벡터 연산기의 경우 RV32I를 위한 ALU보다 연산 사이클이 크므로 별도의 command queue에 명령어를 push하고 벡터 및 텐서 연산기가 command queue에서 명령어를 가져와 연산을 수행하도록 한다.
* 벡터 레지스터 파일이 존재한다. VLEN은 고정이고 워드 크기는 2Byte이다. BF16 연산만을 지원한다. 레지스터의 개수는 32개 이다.
* 텐서 레지스터 파일이 존재한다. 크기는 $32 \times 32$ 이고 워드 크기는 2Byte이다. BF16 연산만을 지원한다. 레지스터의 개수는 4개이다. Output stationary GEMM 연산기이다.
* 벡터 및 텐서 레지스터 ID는 명령어 사이의 의존성을 파악하는데 활용된다.
* 벡터 연산기를 위한 명령어는 크게 1) 벡터 레지스터에 데이터를 로드하는 명령어 2) 벡터 레지스터의 값을 읽고 연산을 수행한 뒤 값을 다른 레지스터에 저장하는 R-type 명령어 3) 벡터 레지스터의 값을 메모리로 내보내는 명령어로 구성된다.
* 텐서 연산기를 위한 명령어는 크게 1) 텐서 레지스터에 데이터를 로드하는 명령어 2) preload / execute (matmul, elementwise 등) / flush 명령어 3) 텐서 레지스터의 값을 메모리로 내보내는 명령어로 구성된다.
* 벡터 및 텐서 레지스터에 대한 load/store 명령어들은 내부 규약에 따라 in-order로 처리되며, 나머지 실행과 관련된 명령어들은 out-of-order로 실행될 수 있다. 또한, 벡터 연산기 명령어들과 텐서 연산기 명령어들은 서로 독립적이다.
* 메모리 가상화는 지원하지 않으며, 모든 메모리 주소는 물리 주소 공간을 따른다. 또한, 모든 코드는 baremetal로 실행된다.

## 온칩 메모리

* Instruction / Data 캐시가 존재하지 않으며, 명령어 및 데이터를 저장하기위한 멀티 뱅크 Scratchpad Memory (SPM)이 존재한다.
* SPM은 CPU 메인 연산기 뿐만 아니라 행렬 및 벡터 연산기 또한 동일한 메모리를 공유한다.
* SPM은 소프트웨어적으로 관리되므로, 코어의 메모리 주소 맵 (memory address map)에 포함된다. 즉, SPM 주소에 해당하는 메모리 리퀘스트는 SPM에 접근하며, DRAM과 SPM 사이의 데이터 이동은 memcpy로 구현된다.

## 오프칩 메모리 및 DMA

* DMA 엔진은 memcpy 연산이 발생하는 경우 SPM 혹은 레지스터파일(scalar/vector/tensor)과 메인 메모리 (DRAM) 사이의 데이터 이동을 처리한다.
* 데이터의 이동 단위는 64B (32*2B)이다.

## Scale-out 시나리오

* 해당 NPU 코어 구조는 NoC를 통해 확장 가능하다. 이를 위해 Torus Network에 대한 라우터가 각 NPU 코어마다 2개 존재한다. (full-duplex channel)
* 확장된 NPU 코어들이 각각 포함하고 있는 SPM은 글로벌 memory address map에 노출된다. 즉, NPU 코어는 다른 NPU 코어의 SPM에 접근할 수 있다.
* NPU 코어 간 동기화를 위한 atomic operation을 지원한다. NoC를 통한 원격 메모리 접근에 대해서도 atomic operation은 유지되어야 한다. 이때 원격 메모리 접근에 대한 coherency는 소프트웨어적으로 보장되어야 하며, 하드웨어는 어떠한 것도 보장하지 않는다.