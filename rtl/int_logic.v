//==============================================================================
// int_logic.v  -  interrupt generation for INT#
// A snapshot of each input port is kept. If an input-configured pin differs
// from its snapshot, the interrupt is active. A read of Input Port n (at the
// ACK clock) refreshes that port's snapshot and clears its interrupt.
// Pins configured as outputs never generate interrupts.
//==============================================================================
module int_logic (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] pin0,
    input  wire [7:0] pin1,
    input  wire [7:0] cfg0,
    input  wire [7:0] cfg1,
    input  wire       rd_strobe,       // a read byte was acknowledged
    input  wire [2:0] rd_strobe_addr,  // which register was read
    output wire       int_active
);
    reg [7:0] snap0, snap1;

    wire [7:0] diff0 = (pin0 ^ snap0) & cfg0;
    wire [7:0] diff1 = (pin1 ^ snap1) & cfg1;
    assign int_active = (|diff0) | (|diff1);

    wire clr0 = rd_strobe && (rd_strobe_addr == 3'd0);
    wire clr1 = rd_strobe && (rd_strobe_addr == 3'd1);

    always @(posedge clk) begin
        if (!rst_n) begin
            snap0 <= pin0;
            snap1 <= pin1;
        end else begin
            // output-configured bits simply follow the pin
            snap0 <= clr0 ? pin0 : ((snap0 & cfg0) | (pin0 & ~cfg0));
            snap1 <= clr1 ? pin1 : ((snap1 & cfg1) | (pin1 & ~cfg1));
        end
    end
endmodule
