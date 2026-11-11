//==============================================================================
// i2c_front_end.v
// Synchronizes SCL/SDA into the system-clock domain and generates the
// START / STOP / SCL-edge strobes used by the slave FSM.
// Requires clk to be at least ~8x faster than SCL (oversampling approach).
//==============================================================================
module i2c_front_end (
    input  wire clk,
    input  wire rst_n,
    input  wire scl,        // raw SCL pin
    input  wire sda,        // raw SDA pin (resolved bus value)
    output wire sda_s,      // synchronized SDA
    output wire scl_rise,   // 1-clk pulse: SCL 0->1
    output wire scl_fall,   // 1-clk pulse: SCL 1->0
    output wire start_det,  // 1-clk pulse: SDA falls while SCL high
    output wire stop_det    // 1-clk pulse: SDA rises while SCL high
);
    reg [1:0] scl_sync, sda_sync;
    reg       scl_d, sda_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin            // bus idle = both lines high
            scl_sync <= 2'b11;
            sda_sync <= 2'b11;
            scl_d    <= 1'b1;
            sda_d    <= 1'b1;
        end else begin
            scl_sync <= {scl_sync[0], scl};
            sda_sync <= {sda_sync[0], sda};
            scl_d    <= scl_sync[1];
            sda_d    <= sda_sync[1];
        end
    end

    wire scl_s = scl_sync[1];
    assign sda_s     = sda_sync[1];
    assign scl_rise  =  scl_s & ~scl_d;
    assign scl_fall  = ~scl_s &  scl_d;
    assign start_det =  scl_s &  scl_d &  sda_d & ~sda_s;
    assign stop_det  =  scl_s &  scl_d & ~sda_d &  sda_s;
endmodule
