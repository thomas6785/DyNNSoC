# open_saif ~/myrun.saif
# log_saif

# launch_simulation
#

# First launch the simulation
# The testbench calls $stop when it detects the MVU being started
launch_simulation
run -all

# sim will halt just before kicking off the MVU - let's start logging switching activity now

# set up logging of switching activity in the SAIF file
open_saif /tmp/myrun.saif

# Log top-level signals in the DUT
current_scope /TB_toplevel/dut
log_saif [get_objects]

# Log top-level signals in the CPU
current_scope cpu
log_saif [get_objects]

# Log top-level signals in the MVU array
current_scope ../MVU/mvu
log_saif [get_objects]

# Log the signals in each mvu.sv
# this includes the data/weights being read/written from memory
current_scope \mvuarray[0].mvuunit      ;
log_saif [get_objects]                  ;
current_scope ../\mvuarray[1].mvuunit   ;
log_saif [get_objects]                  ;
current_scope ../\mvuarray[2].mvuunit   ;
log_saif [get_objects]                  ;
current_scope ../\mvuarray[3].mvuunit   ;
log_saif [get_objects]

# Continue the run, logging all that switching activity
run -all
close_saif

# sim will halt again at the end
close_sim

# Open the implemented design and read the SAIF file to report power
open_run impl_1
read_saif /tmp/myrun.saif
report_power
close_design
