//==============================================================================
// io_ports.v  -  16 bidirectional pins with per-bit direction control
//   cfg = 1 : pin is an input  (output driver released, high-Z)
//   cfg = 0 : pin is an output (drives the Output register bit)
// Pin values are double-flop synchronized before use.
//==============================================================================
module io_ports (
    input  wire       clk,
    input  wire [7:0] cfg0,
    input  wire [7:0] cfg1,
    input  wire [7:0] out0,
    input  wire [7:0] out1,
    inout  wire [7:0] p0,
    inout  wire [7:0] p1,
    output wire [7:0] pin0_s,
    output wire [7:0] pin1_s
);
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : g_pin
            assign p0[i] = cfg0[i] ? 1'bz : out0[i];
            assign p1[i] = cfg1[i] ? 1'bz : out1[i];
        end
    endgenerate

    reg [7:0] p0_m, p0_q, p1_m, p1_q;
    always @(posedge clk) begin
        p0_m <= p0;  p0_q <= p0_m;
        p1_m <= p1;  p1_q <= p1_m;
    end
    assign pin0_s = p0_q;
    assign pin1_s = p1_q;
endmodule
