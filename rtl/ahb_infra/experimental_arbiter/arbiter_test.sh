AHBDIR=$SOCROOT/rtl/ahb
RUNDIR=$AHBDIR/artefacts/arbiter_test

mkdir -p $RUNDIR
pushd $RUNDIR

xvlog -sv $AHBDIR/ahb_intf.sv $AHBDIR/ahb_arbiter.sv
xvlog -sv $AHBDIR/smoke_tests/ahb_arbiter_tb.sv
xelab ahb_arbiter_tb -s tb_sim

xsim tb_sim -runall

echo Refer to `pwd` for full logs
echo
popd
