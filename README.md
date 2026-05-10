# DyNNSoC
## Overview
DyNNSoC (Dynamic Neural Network System-on-Chip) is an SoC optimised for accelerating *dynamically quantised* neural networks.

It integrates a modified version of the bit-serial processing element described in [1] (herein referred to as an MVU)
It borrows idea from a previous SoC which used the processing element, described in [2]
Those designs targetted mixed-precision neural networks without necessarily considering dynamic quantisation, though there is minimal added effort to accommodate that.

Two key papers on dynamic quantisation ALGORITHMS (which do not consider hardware implementation) are [3] and [4]

## Roadmap

General:

- Instead of requiring neural networks to be implemented in C, provide a code generator which parses an Onnx file to generate the C code for the network, still using the hardware-abstraction API methods provided with this SoC. Similar to the MVU Code Generator associated with BARVINN, but preferably less buggy and using C instead of ASM

- Modify MVU register map to allow them to be self-restarting i.e. as soon as one operation finishes, immediately pulse 'start' (updating the shadow register -> live registers), meaning there is no 'handover period' waiting for the core to give the go-ahead

- Pre-add is not used in the scaler-bias units so should be removed (though this could interfere with inferring DSP for FPGA ?)

- Write conflicts are detected but not handled (e.g. wrd_grnt is driven but not used anywhere)

- Upgrade to latest version of Ibex core (current RTL was borrowed from [5] and is not the most up-to-date version)

- Possible problem around convolutions - how do we handle padding? Need an output AGU or similar solution. A workaround is to pad the input data with 0s before we begin, but that is wasteful.

- MVU Register map (mvutop_wrapper.sv) could be cleaner and it would be best if it were automatically generated from a register spec that also generates C headers (or generate C headers from HDL? just need a better flow there as it has been manually maintained until now)

Power optimisations:

- Add data gate between shifter-accumulator and scaler-bias units on the MVU datapath to avoid unnecessary switching activity in the scaler-bias unit (which is implemented on FPGA as a DSP)

- Each MVU should have a top-level clock gate disabling the processing logic when the controller is not asserting 'run'

- Each MVU could also have a POWER gate. This will lose internal state which could be problematic

- The Ibex core has a power gating but the appropriate primitive not implemented for FPGA implementation (see prim_clock_gating.v)

## References

[1] Bilaniuk, Olexa, et al. "Bit-slicing FPGA accelerator for quantized neural networks." 2019 IEEE International Symposium on Circuits and Systems (ISCAS). IEEE, 2019.
[2] Askarihemmat, Mohammadhossein, et al. "BARVINN: Arbitrary precision DNN accelerator controlled by a RISC-V CPU." Proceedings of the 28th Asia and South Pacific Design Automation Conference. 2023.
[3] Jin, Qing, Linjie Yang, and Zhenyu Liao. "Adabits: Neural network quantization with adaptive bit-widths." Proceedings of the IEEE/CVF conference on computer vision and pattern recognition. 2020.
[4] Liu, Zhenhua, et al. "Instance-aware dynamic neural network quantization." Proceedings of the IEEE/CVF conference on computer vision and pattern recognition. 2022.
[5] https://github.com/NouranAbdelaziz/ML_and_Sec_Accelerated_Chameleon_SoC/blob/main/verilog/rtl/soc_core.v