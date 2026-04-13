#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export SOCROOT=$SCRIPT_DIR

# Add Vivado to PATH
PATH=$PATH:/tools/Xilinx/2025.1/Vivado/bin/

# Add RISCV tools to PATH
PATH=$PATH:/home/tudentstudent/riscv/bin/
