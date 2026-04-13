run:
	echo "\n\nRunning test at $$(pwd)"								&&\
	cd artefacts													&&\
	xvlog -f ../filelist 						> log.log			&&\
	xelab -debug typical TB_toplevel -s tb_sim	>> log.log			&&\
	xsim tb_sim -runall 						>> log.log			&&\
	tail log.log
