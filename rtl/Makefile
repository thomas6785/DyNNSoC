XPATH = /tools/Xilinx/2025.1/Vivado/bin

all: parse elab sim

.PHONY: parse
parse:
	cd $$SOCROOT/rtl/temp											;\
	$(XPATH)/xvlog -f $$SOCROOT/rtl/filelist

.PHONY: elab
elab:
	cd $$SOCROOT/rtl/temp											;\
	$(XPATH)/xelab TB_toplevel -debug typical -s tb_sim

.PHONY: sim
sim:
	cd $$SOCROOT/rtl/temp											;\
	$(XPATH)/xsim tb_sim -runall

.PHONY: gui
gui:
	cd $$SOCROOT/rtl/temp											;\
	$(XPATH)/xsim tb_sim --gui
