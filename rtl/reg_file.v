//==============================================================================
// reg_file.v  -  PCA9555 register bank
//   cmd 0 : Input Port 0   (read only)     cmd 4 : Polarity Inversion Port 0
//   cmd 1 : Input Port 1   (read only)     cmd 5 : Polarity Inversion Port 1
//   cmd 2 : Output Port 0                  cmd 6 : Configuration Port 0
//   cmd 3 : Output Port 1                  cmd 7 : Configuration Port 1
// Power-on defaults: Output = FF, Polarity = 00, Configuration = FF (inputs)
//==============================================================================
module reg_file (
    input  wire       clk,
    input  wire       rst_n,
    // write port (from I2C slave)
    input  wire       wr_en,
    input  wire [2:0] wr_addr,
    input  wire [7:0] wr_data,
    // read port (from I2C slave)
    input  wire [2:0] rd_addr,
    output reg  [7:0] rd_data,
    // synchronized pin values
    input  wire [7:0] pin0,
    input  wire [7:0] pin1,
    // register outputs to the rest of the design
    output reg  [7:0] out0,
    output reg  [7:0] out1,
    output reg  [7:0] pol0,
    output reg  [7:0] pol1,
    output reg  [7:0] cfg0,
    output reg  [7:0] cfg1
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out0 <= 8'hFF;  out1 <= 8'hFF;
            pol0 <= 8'h00;  pol1 <= 8'h00;
            cfg0 <= 8'hFF;  cfg1 <= 8'hFF;
        end else if (wr_en) begin
            case (wr_addr)
                3'd2: out0 <= wr_data;
                3'd3: out1 <= wr_data;
                3'd4: pol0 <= wr_data;
                3'd5: pol1 <= wr_data;
                3'd6: cfg0 <= wr_data;
                3'd7: cfg1 <= wr_data;
                default: ;          // input registers are read-only
            endcase
        end
    end

    always @(*) begin
        case (rd_addr)
            3'd0:    rd_data = pin0 ^ pol0;   // input reg = pin XOR polarity
            3'd1:    rd_data = pin1 ^ pol1;
            3'd2:    rd_data = out0;
            3'd3:    rd_data = out1;
            3'd4:    rd_data = pol0;
            3'd5:    rd_data = pol1;
            3'd6:    rd_data = cfg0;
            default: rd_data = cfg1;
        endcase
    end
endmodule
