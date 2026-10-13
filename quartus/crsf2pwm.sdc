# Timing constraints for the MAX II revision (crsf2pwm.qsf), the own board.
# The Cyclone IV revision uses crsf2pwm_c4.sdc.

# 25 MHz from Y1 on the board. Matches CLK_HZ in crsf2pwm.qsf.
create_clock -name clk25 -period 40.000 [get_ports clk]

derive_clock_uncertainty

# rx is asynchronous to clk and goes through a synchronizer; no timing check.
set_false_path -from [get_ports rx]

# PWM outputs and LEDs: servos and eyes do not care about nanoseconds.
set_false_path -to [get_ports {steer throttle led[*]}]
