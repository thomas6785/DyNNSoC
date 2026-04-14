run: newlog artefacts/main.hex comp elab sim report

FW_DIR  := $(SOCROOT)/firmware
include $(FW_DIR)/firmware.mk

.SILENT: artefacts/log.log
.PHONY: newlog
newlog:
	cd artefacts &&\
	echo "" > log.log

.PHONY: comp elab sim report clean
.SILENT: comp elab sim report

# There are separate targets for compile, elab, sim
# They aren't actually dependencies since the user might want to rerun just one,
# but Make can detect if they are out of date so it will always rerun them all
# if you want a full clean run use "make run"

comp: newlog
	echo "\nCompiling test $$(pwd)"								&&\
	cd artefacts													&&\
	xvlog -sv -f ../filelist 						>> log.log

elab: newlog
	echo "\nElaborating test $$(pwd)"								&&\
	cd artefacts													&&\
	xelab -debug typical TB_toplevel -s tb_sim	>> log.log

sim: newlog
	echo "\nSimulating test $$(pwd)"								&&\
	cd artefacts													&&\
	xsim tb_sim -runall 						>> log.log

report: sim
	cd artefacts													&&\
	tail log.log

gui:
	cd artefacts													&&\
	xsim tb_sim -gui

clean:
	rm -r artefacts/*
