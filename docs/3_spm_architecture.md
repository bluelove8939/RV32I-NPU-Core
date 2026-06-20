# SPM Architecture

This documentation describes in detail about how the SPM is organized.


## Hierarchical Overview

Multi-bank SPM is composed of 3 hierarchical steps.

1. SPM Bus

* The SPM bus controls the bank groups.
* The SPM bus receives the address of the cacheline from the clients, not the byte address.

2. Bank Group

* A group of banks that is responsible for handling a cacheline read/write requests.
* Clients (e.g., instruction fetcher, data fetcher ...) can simultaneously send requests to different bank groups and these requests can be handled in parallel.
* Requests comming to the same bank group will be arbitrated within the bank group with fixed priority (scheduling policy will be replaced later).
* A single cacheline includes 16words. (cacheline = 32bit * 16 = 512bit) Therefore, each bank group includes 16 banks.

3. Bank

* A single SPM instance that is responsible for handling a word read/write requests.
* Since this architecture is based on 32bit RISC-V CPU (RV32I), a single word is 32bit.


## Clients

Arbitration priority is considered high when the value itself is small.

1. Instruction Fetcher

* arbitration priority: 1
* Fetches a single cacheline that belongs to the current PC address from the SPM. 
* Simple prefetcher is included - prefetches a cacheline and reuse them if the address of the instructions are contiguous.

2. Data Fetcher

* arbitration priority: 0
* Fetches a single cacheline that belongs to the given word address from the SPM.
* Simple prefetcher is included - prefetches a cacheline and reuse them if the address of the data words are contiguous.