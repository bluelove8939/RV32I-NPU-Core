#!/usr/bin/env bash
set -Eeuo pipefail

#####################################################
# STEP 0: Global Environment Settings
#####################################################

TOP_REPO="$(pwd)"
LOG_DIR="$TOP_REPO/.logs"
mkdir -p "$LOG_DIR"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/setup_${TIMESTAMP}.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "====================================================="
echo "[SETUP] Time: $(date)"
echo "[SETUP] Top: $TOP_REPO"
echo "[SETUP] Log: $LOG_FILE"
echo "====================================================="

trap 'echo "[ERROR] setup.sh failed at line $LINENO"; echo "[ERROR] Last command: $BASH_COMMAND"; echo "[ERROR] Current dir: $(pwd)"; exit 1' ERR

#####################################################
# STEP 1: Setup RISC-V GNU Toolchain
#####################################################

echo
echo "====================================================="
echo "[STEP 1] Setup RISC-V GNU Toolchain"
echo "====================================================="

cd "$TOP_REPO/externals/riscv-gnu-toolchain"
echo "[INFO] Current dir: $(pwd)"

export RISCV="$TOP_REPO/externals/riscv-gnu-toolchain/build"
echo "[INFO] RISCV=$RISCV"

echo "[CMD] ./configure --prefix=$RISCV --with-arch=rv32i_zicsr --with-abi=ilp32"
./configure --prefix="$RISCV" --with-arch=rv32i_zicsr --with-abi=ilp32

echo "[CMD] make -j$(nproc)"
make -j"$(nproc)"

echo "[CMD] make linux -j$(nproc)"
make linux -j"$(nproc)"

export PATH="$RISCV/bin:$PATH"
echo "[INFO] PATH updated"
echo "[CHECK] riscv32-unknown-elf-gcc:"
command -v riscv32-unknown-elf-gcc || true
echo "[CHECK] riscv32-unknown-linux-gnu-gcc:"
command -v riscv32-unknown-linux-gnu-gcc || true

# #####################################################
# # STEP 2: Setup Spike
# #####################################################

# echo
# echo "====================================================="
# echo "[STEP 2] Setup Spike"
# echo "====================================================="

# cd "$TOP_REPO/externals/riscv-isa-sim"
# echo "[INFO] Current dir: $(pwd)"

# rm -rf build
# mkdir -p build
# cd build
# echo "[INFO] Current dir: $(pwd)"

# echo "[CMD] ../configure --prefix=$RISCV"
# ../configure --prefix="$RISCV"

# echo "[CMD] make -j$(nproc)"
# make -j"$(nproc)"

# echo "[CMD] make install"
# make install

# echo "[CHECK] spike:"
# command -v spike || true
# spike --help | head -40 || true

# echo
# echo "====================================================="
# echo "[SETUP] Completed successfully"
# echo "[SETUP] Log saved to: $LOG_FILE"
# echo "====================================================="