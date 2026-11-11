//==============================================================================
// i2c_slave.v  -  PCA9555 I2C slave protocol engine
//
// Slave address : 0 1 0 0 A2 A1 A0   (+ R/W)
// Write         : START, ADDR+W, CMD, DATA, DATA, ... STOP
// Read          : START, ADDR+W, CMD, rSTART, ADDR+R, DATA... NACK, STOP
//                 (or START, ADDR+R, ... to read from the current pointer)
// The command byte's bit 0 toggles after every data byte, so consecutive
// bytes alternate between port 0 and port 1 of the selected register pair.
//==============================================================================
module i2c_slave (
    input  wire       clk,
    input  wire       rst_n,
    // from front end
    input  wire       sda_s,
    input  wire       scl_rise,
    input  wire       scl_fall,
    input  wire       start_det,
    input  wire       stop_det,
    // config
    input  wire [2:0] dev_addr,        // A2 A1 A0
    // SDA open-drain control (1 = pull SDA low)
    output reg        sda_oe,
    // register-file interface
    output reg        wr_en,
    output reg  [2:0] wr_addr,
    output reg  [7:0] wr_data,
    output wire [2:0] rd_addr,
    input  wire [7:0] rd_data,
    // read-acknowledge strobe for the interrupt logic
    output reg        rd_strobe,
    output reg  [2:0] rd_strobe_addr
);
    localparam [3:0] S_IDLE     = 4'd0,
                     S_ADDR     = 4'd1,
                     S_ADDR_ACK = 4'd2,
                     S_CMD      = 4'd3,
                     S_CMD_ACK  = 4'd4,
                     S_WR       = 4'd5,
                     S_WR_ACK   = 4'd6,
                     S_RD       = 4'd7,
                     S_RD_ACK   = 4'd8;

    reg [3:0] state;
    reg [3:0] bitcnt;       // counts SCL rising edges within a byte
    reg [7:0] sh;           // receive shift register
    reg [7:0] tx_sh;        // transmit shift register
    reg [2:0] cmd;          // command byte (register pointer)
    reg [2:0] rd_last;      // register of the byte being read
    reg       rw;           // 1 = master read
    reg       nack;         // master NACK captured on the 9th clock

    assign rd_addr = cmd;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;  bitcnt <= 4'd0;  sh <= 8'h00;  tx_sh <= 8'h00;
            cmd <= 3'd0;  rd_last <= 3'd0;  rw <= 1'b0;  nack <= 1'b0;
            sda_oe <= 1'b0;
            wr_en <= 1'b0;  wr_addr <= 3'd0;  wr_data <= 8'h00;
            rd_strobe <= 1'b0;  rd_strobe_addr <= 3'd0;
        end else begin
            wr_en     <= 1'b0;
            rd_strobe <= 1'b0;

            if (stop_det) begin                     // STOP: always back to idle
                state  <= S_IDLE;
                sda_oe <= 1'b0;
                bitcnt <= 4'd0;
            end else if (start_det) begin           // START / repeated START
                state  <= S_ADDR;
                sda_oe <= 1'b0;
                bitcnt <= 4'd0;
            end else begin
                case (state)
                //------------------------------------------------------------
                S_IDLE: ;   // wait for START (also used after address mismatch)

                //------------------------------------------------------------
                // Receive states: shift 8 bits on SCL rise, act on the 8th fall
                S_ADDR, S_CMD, S_WR: begin
                    if (scl_rise && bitcnt < 4'd8) begin
                        sh     <= {sh[6:0], sda_s};
                        bitcnt <= bitcnt + 4'd1;
                    end else if (scl_fall && bitcnt == 4'd8) begin
                        bitcnt <= 4'd0;
                        case (state)
                            S_ADDR:
                                if (sh[7:1] == {4'b0100, dev_addr}) begin
                                    rw     <= sh[0];
                                    sda_oe <= 1'b1;         // ACK
                                    state  <= S_ADDR_ACK;
                                end else
                                    state  <= S_IDLE;       // not for us
                            S_CMD: begin
                                cmd    <= sh[2:0];
                                sda_oe <= 1'b1;             // ACK
                                state  <= S_CMD_ACK;
                            end
                            default: begin                  // S_WR
                                wr_en   <= 1'b1;
                                wr_addr <= cmd;
                                wr_data <= sh;
                                cmd[0]  <= ~cmd[0];         // port toggle
                                sda_oe  <= 1'b1;            // ACK
                                state   <= S_WR_ACK;
                            end
                        endcase
                    end
                end

                //------------------------------------------------------------
                // ACK states: ACK is held until the 9th falling edge
                S_ADDR_ACK:
                    if (scl_fall) begin
                        if (rw) begin                       // read: first byte
                            tx_sh  <= rd_data;
                            sda_oe <= ~rd_data[7];
                            bitcnt <= 4'd0;
                            state  <= S_RD;
                        end else begin
                            sda_oe <= 1'b0;
                            state  <= S_CMD;
                        end
                    end

                S_CMD_ACK:
                    if (scl_fall) begin
                        sda_oe <= 1'b0;
                        state  <= S_WR;
                    end

                S_WR_ACK:
                    if (scl_fall) begin
                        sda_oe <= 1'b0;
                        state  <= S_WR;
                    end

                //------------------------------------------------------------
                // Transmit: next bit is driven on every SCL falling edge
                S_RD: begin
                    if (scl_rise && bitcnt < 4'd8)
                        bitcnt <= bitcnt + 4'd1;
                    else if (scl_fall) begin
                        if (bitcnt == 4'd8) begin           // byte done
                            sda_oe  <= 1'b0;                // release for ACK
                            rd_last <= cmd;
                            cmd[0]  <= ~cmd[0];             // port toggle
                            bitcnt  <= 4'd0;
                            state   <= S_RD_ACK;
                        end else begin
                            sda_oe <= ~tx_sh[6];
                            tx_sh  <= {tx_sh[6:0], 1'b0};
                        end
                    end
                end

                S_RD_ACK: begin
                    if (scl_rise) begin                     // master ACK/NACK
                        nack           <= sda_s;
                        rd_strobe      <= 1'b1;
                        rd_strobe_addr <= rd_last;
                    end else if (scl_fall) begin
                        if (nack) begin
                            sda_oe <= 1'b0;
                            state  <= S_IDLE;
                        end else begin                      // send next byte
                            tx_sh  <= rd_data;
                            sda_oe <= ~rd_data[7];
                            bitcnt <= 4'd0;
                            state  <= S_RD;
                        end
                    end
                end

                default: state <= S_IDLE;
                endcase
            end
        end
    end
endmodule
