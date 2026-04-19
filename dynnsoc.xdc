# clock period (150 MHz)
create_clock -period 6.667 -name clk [get_ports {clk}]

# Waive I/O standard for all pins
# This is completely unacceptable for a real design
# so don't generate a bitstream like this
# but it's fine for validating that implementation can
# complete and meet timing
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
