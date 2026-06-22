export NMTA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export VERILATOR_ROOT="$NMTA_ROOT/externals/verilator"
export RISCV="$NMTA_ROOT/externals/riscv-gnu-toolchain/build"
export PATH="$VERILATOR_ROOT/bin:$RISCV/bin:$PATH"

export NMTA_ENV_MK="$NMTA_ROOT/sw/env/nmta_env.mk"