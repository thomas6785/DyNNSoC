AHBDIR=$SOCROOT/rtl/ahb
RUNDIR=$AHBDIR/artefacts/rw_regs_test

mkdir -p $RUNDIR
pushd $RUNDIR

xvlog -sv $AHBDIR/ahb_intf.sv $AHBDIR/ahb_rw_regs.sv
xvlog -sv $AHBDIR/models/ahb_master.sv
xvlog -sv $AHBDIR/smoke_tests/ahb_rw_regs_tb.sv
xelab ahb_rw_regs_tb -s tb_sim

xsim tb_sim -runall

echo Refer to `pwd` for full logs
echo
popd
