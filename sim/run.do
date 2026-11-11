# ModelSim run script - usage (from the sim/ folder):  vsim -do run.do
#   or inside ModelSim:  cd <path>/pca9555/sim ; do run.do
quit -sim
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

vlog -work work ../rtl/i2c_front_end.v ../rtl/reg_file.v ../rtl/io_ports.v \
                ../rtl/int_logic.v ../rtl/i2c_slave.v ../rtl/pca9555.v
vlog -work work ../tb/tb_pca9555.v

vsim -voptargs=+acc work.tb_pca9555

# ---- waveforms ----
add wave -divider {Clock / Reset}
add wave -noupdate /tb_pca9555/clk /tb_pca9555/rst_n
add wave -divider {I2C bus}
add wave -noupdate /tb_pca9555/scl_r /tb_pca9555/sda /tb_pca9555/int_n
add wave -divider {DUT0 pins}
add wave -noupdate -radix hex /tb_pca9555/p0 /tb_pca9555/p1
add wave -divider {DUT0 slave FSM}
add wave -noupdate -radix unsigned /tb_pca9555/dut0/u_slave/state
add wave -noupdate -radix hex /tb_pca9555/dut0/u_slave/cmd /tb_pca9555/dut0/u_slave/sh
add wave -noupdate /tb_pca9555/dut0/u_front/start_det /tb_pca9555/dut0/u_front/stop_det
add wave -divider {DUT0 registers}
add wave -noupdate -radix hex /tb_pca9555/dut0/u_regs/out0 /tb_pca9555/dut0/u_regs/out1 \
                               /tb_pca9555/dut0/u_regs/pol0 /tb_pca9555/dut0/u_regs/pol1 \
                               /tb_pca9555/dut0/u_regs/cfg0 /tb_pca9555/dut0/u_regs/cfg1
add wave -divider {DUT1 (addr 0x25)}
add wave -noupdate -radix hex /tb_pca9555/p0_b

configure wave -timelineunits us
run -all
wave zoom full
