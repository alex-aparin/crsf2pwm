# Timing constraints.

# 50 MHz from the board oscillator.
create_clock -name clk50 -period 20.000 [get_ports clk]

derive_clock_uncertainty

# rx is asynchronous to clk and goes through a synchronizer; no timing check.
set_false_path -from [get_ports rx]

# PWM outputs and LEDs: servos and eyes do not care about nanoseconds.
set_false_path -to [get_ports {steer throttle led[*]}]
