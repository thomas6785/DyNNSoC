run: artefacts/main.hex compile-sv elab-sv sim-sv report

FW_DIR  := $(SOCROOT)/firmware
include $(FW_DIR)/firmware.mk

.SILENT: artefacts/log.log
artefacts/log.log:
	cd artefacts &&\
	echo "" > log.log

.PHONY: compile-sv elab-sv sim-sv report clean
.SILENT: compile-sv elab-sv sim-sv report

# There are separate targets for compile, elab, sim
# They aren't actually dependencies since the user might want to rerun just one,
# but Make can detect if they are out of date so it will always rerun them all
# if you want a full clean run use "make run"

compile-sv: artefacts/log.log
	echo "\nCompiling test $$(pwd)"								&&\
	cd artefacts													&&\
	xvlog -f ../filelist 						>> log.log

elab-sv: artefacts/log.log
	echo "\nElaborating test $$(pwd)"								&&\
	cd artefacts													&&\
	xelab -debug typical TB_toplevel -s tb_sim	>> log.log

sim-sv: artefacts/log.log
	echo "\nSimulating test $$(pwd)"								&&\
	cd artefacts													&&\
	xsim tb_sim -runall 						>> log.log

report: sim-sv artefacts/log.log
	cd artefacts													&&\
	tail log.log

gui: compile-sv elab-sv
	cd artefacts &&\
	xsim tb_sim -gui

clean:
	rm -r artefacts/*
