export VERILATOR_ROOT=$(pwd)/externals/verilator
export RISCV="$(pwd)/externals/riscv-gnu-toolchain/build"
export PATH="$VERILATOR_ROOT/bin:$RISCV/bin:$PATH"