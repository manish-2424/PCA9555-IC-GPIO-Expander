//==============================================================================
// pca9555.v  -  Top level: 16-bit I2C / SMBus I/O expander with interrupt
//
//   clk   : system clock used to oversample SCL/SDA (>= 8x SCL frequency)
//   rst_n : active-low reset (models power-on reset)
//   scl   : I2C clock input
//   sda   : I2C data, open-drain
//   addr  : A2,A1,A0 hardware address pins
//   p0,p1 : 16 quasi-bidirectional I/O pins
//   int_n : open-drain, active-low interrupt output
//==============================================================================
module pca9555 (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       scl,
    inout  wire       sda,
    input  wire [2:0] addr,
    inout  wire [7:0] p0,
    inout  wire [7:0] p1,
    output wire       int_n
);
    // front end
    wire sda_s, scl_rise, scl_fall, start_det, stop_det;
    // slave <-> register file
    wire       sda_oe, wr_en, rd_strobe;
    wire [2:0] wr_addr, rd_addr, rd_strobe_addr;
    wire [7:0] wr_data, rd_data;
    // registers / pins
    wire [7:0] out0, out1, pol0, pol1, cfg0, cfg1, pin0_s, pin1_s;
    wire       int_active;

    i2c_front_end u_front (
        .clk(clk), .rst_n(rst_n), .scl(scl), .sda(sda),
        .sda_s(sda_s), .scl_rise(scl_rise), .scl_fall(scl_fall),
        .start_det(start_det), .stop_det(stop_det)
    );

    i2c_slave u_slave (
        .clk(clk), .rst_n(rst_n),
        .sda_s(sda_s), .scl_rise(scl_rise), .scl_fall(scl_fall),
        .start_det(start_det), .stop_det(stop_det),
        .dev_addr(addr), .sda_oe(sda_oe),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_addr(rd_addr), .rd_data(rd_data),
        .rd_strobe(rd_strobe), .rd_strobe_addr(rd_strobe_addr)
    );

    reg_file u_regs (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_addr(rd_addr), .rd_data(rd_data),
        .pin0(pin0_s), .pin1(pin1_s),
        .out0(out0), .out1(out1), .pol0(pol0), .pol1(pol1),
        .cfg0(cfg0), .cfg1(cfg1)
    );

    io_ports u_io (
        .clk(clk), .cfg0(cfg0), .cfg1(cfg1), .out0(out0), .out1(out1),
        .p0(p0), .p1(p1), .pin0_s(pin0_s), .pin1_s(pin1_s)
    );

    int_logic u_int (
        .clk(clk), .rst_n(rst_n),
        .pin0(pin0_s), .pin1(pin1_s), .cfg0(cfg0), .cfg1(cfg1),
        .rd_strobe(rd_strobe), .rd_strobe_addr(rd_strobe_addr),
        .int_active(int_active)
    );

    // open-drain outputs
    assign sda   = sda_oe     ? 1'b0 : 1'bz;
    assign int_n = int_active ? 1'b0 : 1'bz;
endmodule
