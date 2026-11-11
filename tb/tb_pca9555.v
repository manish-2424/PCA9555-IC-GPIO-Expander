//==============================================================================
// tb_pca9555.v  -  self-checking testbench for the PCA9555 RTL
// The testbench acts as an I2C master (400 kHz SCL, 100 MHz system clock).
// Two devices share the bus: DUT0 (A2:A0 = 000, I2C addr 0x20) is the main
// device under test, DUT1 (A2:A0 = 101, I2C addr 0x25) is used for the
// multiple-address test.
//==============================================================================
`timescale 1ns/1ps

module tb_pca9555;

    parameter QTR = 625;                 // quarter SCL period (ns) -> 400 kHz

    localparam [6:0] ADDR0 = 7'h20;      // 0100 000
    localparam [6:0] ADDR1 = 7'h25;      // 0100 101

    //--------------------------------------------------------------------------
    // Clock, reset, bus
    //--------------------------------------------------------------------------
    reg  clk = 1'b0;
    always #5 clk = ~clk;                // 100 MHz

    reg  rst_n;
    reg  scl_r;                          // master-driven SCL
    reg  sda_m_low;                      // master pulls SDA low

    tri1 sda;                            // pulled-up open-drain bus
    assign sda = sda_m_low ? 1'b0 : 1'bz;

    // DUT0 pins: pulled up, testbench can drive them externally
    tri1 [7:0] p0, p1;
    tri1       int_n;
    reg  [7:0] ext0_oe, ext0_val, ext1_oe, ext1_val;
    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : g_ext
            assign p0[g] = ext0_oe[g] ? ext0_val[g] : 1'bz;
            assign p1[g] = ext1_oe[g] ? ext1_val[g] : 1'bz;
        end
    endgenerate

    // DUT1 pins
    tri1 [7:0] p0_b, p1_b;
    tri1       int_n_b;

    pca9555 dut0 (.clk(clk), .rst_n(rst_n), .scl(scl_r), .sda(sda),
                  .addr(3'b000), .p0(p0), .p1(p1), .int_n(int_n));

    pca9555 dut1 (.clk(clk), .rst_n(rst_n), .scl(scl_r), .sda(sda),
                  .addr(3'b101), .p0(p0_b), .p1(p1_b), .int_n(int_n_b));

    //--------------------------------------------------------------------------
    // Scoreboard
    //--------------------------------------------------------------------------
    integer tests  = 0;
    integer errors = 0;

    task check8(input [8*44-1:0] name, input [7:0] got, input [7:0] exp);
        begin
            tests = tests + 1;
            if (got === exp)
                $display("[PASS] %0s : 0x%02h", name, got);
            else begin
                errors = errors + 1;
                $display("[FAIL] %0s : got 0x%02h, expected 0x%02h", name, got, exp);
            end
        end
    endtask

    task check1(input [8*44-1:0] name, input got, input exp);
        begin
            tests = tests + 1;
            if (got === exp)
                $display("[PASS] %0s : %b", name, got);
            else begin
                errors = errors + 1;
                $display("[FAIL] %0s : got %b, expected %b", name, got, exp);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // I2C master primitives (every task is entered/left with SCL low unless noted)
    //--------------------------------------------------------------------------
    task i2c_start;                      // also used as repeated START
        begin
            sda_m_low = 1'b0;  #QTR;     // release SDA
            scl_r     = 1'b1;  #QTR;     // SCL high
            sda_m_low = 1'b1;  #QTR;     // START: SDA falls while SCL high
            scl_r     = 1'b0;  #QTR;
        end
    endtask

    task i2c_stop;
        begin
            sda_m_low = 1'b1;  #QTR;
            scl_r     = 1'b1;  #QTR;
            sda_m_low = 1'b0;  #(2*QTR); // STOP: SDA rises while SCL high
        end
    endtask

    task i2c_write_byte(input [7:0] b, output ack);
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                sda_m_low = ~b[i];
                #QTR; scl_r = 1'b1;
                #(2*QTR); scl_r = 1'b0;
                #QTR;
            end
            sda_m_low = 1'b0;            // release SDA for the ACK bit
            #QTR; scl_r = 1'b1;
            #QTR; ack = ~sda;            // ACK = SDA low
            #QTR; scl_r = 1'b0;
            #QTR;
        end
    endtask

    task i2c_read_byte(input send_ack, output [7:0] b);
        integer i;
        begin
            sda_m_low = 1'b0;
            for (i = 7; i >= 0; i = i - 1) begin
                #QTR; scl_r = 1'b1;
                #QTR; b[i] = sda;
                #QTR; scl_r = 1'b0;
                #QTR;
            end
            sda_m_low = send_ack;        // master ACK (low) or NACK (high)
            #QTR; scl_r = 1'b1;
            #(2*QTR); scl_r = 1'b0;
            #QTR;
            sda_m_low = 1'b0;
        end
    endtask

    // clock n bits of '0' without completing a byte (for the abort test)
    task i2c_clock_zero_bits(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                sda_m_low = 1'b1;
                #QTR; scl_r = 1'b1;
                #(2*QTR); scl_r = 1'b0;
                #QTR;
            end
            sda_m_low = 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // High-level transactions
    //--------------------------------------------------------------------------
    reg [7:0] wbuf [0:15];
    reg [7:0] rbuf [0:15];
    reg       last_addr_ack;

    // START, ADDR+W, CMD, n data bytes (wbuf[0..n-1]), STOP
    task write_burst(input [6:0] a, input [2:0] cmd, input integer n);
        integer k;
        reg ack;
        begin
            i2c_start;
            i2c_write_byte({a, 1'b0}, last_addr_ack);
            i2c_write_byte({5'b00000, cmd}, ack);
            for (k = 0; k < n; k = k + 1)
                i2c_write_byte(wbuf[k], ack);
            i2c_stop;
        end
    endtask

    // START, ADDR+W, CMD, rSTART, ADDR+R, n bytes (rbuf[0..n-1]), NACK last, STOP
    task read_burst(input [6:0] a, input [2:0] cmd, input integer n);
        integer k;
        reg ack;
        begin
            i2c_start;
            i2c_write_byte({a, 1'b0}, last_addr_ack);
            i2c_write_byte({5'b00000, cmd}, ack);
            i2c_start;                                   // repeated START
            i2c_write_byte({a, 1'b1}, ack);
            for (k = 0; k < n; k = k + 1)
                i2c_read_byte((k != n-1), rbuf[k]);
            i2c_stop;
        end
    endtask

    // START, ADDR+R, n bytes from the current register pointer, STOP
    task read_current(input [6:0] a, input integer n);
        integer k;
        reg ack;
        begin
            i2c_start;
            i2c_write_byte({a, 1'b1}, ack);
            for (k = 0; k < n; k = k + 1)
                i2c_read_byte((k != n-1), rbuf[k]);
            i2c_stop;
        end
    endtask

    task write_reg(input [6:0] a, input [2:0] cmd, input [7:0] d);
        begin
            wbuf[0] = d;
            write_burst(a, cmd, 1);
        end
    endtask

    task read_reg(input [6:0] a, input [2:0] cmd, output [7:0] d);
        begin
            read_burst(a, cmd, 1);
            d = rbuf[0];
        end
    endtask

    // Release external pin drivers and pulse reset
    task do_reset;
        begin
            ext0_oe = 8'h00; ext0_val = 8'h00;
            ext1_oe = 8'h00; ext1_val = 8'h00;
            scl_r = 1'b1; sda_m_low = 1'b0;
            rst_n = 1'b0;
            repeat (6) @(posedge clk);
            rst_n = 1'b1;
            repeat (6) @(posedge clk);
        end
    endtask

    //--------------------------------------------------------------------------
    // Test sequence
    //--------------------------------------------------------------------------
    reg [7:0] rd;
    integer   r;

    initial begin
        $dumpfile("tb_pca9555.vcd");
        $dumpvars(0, tb_pca9555);
        rst_n = 1'b0; scl_r = 1'b1; sda_m_low = 1'b0;
        ext0_oe = 0; ext0_val = 0; ext1_oe = 0; ext1_val = 0;
        #100;

        //----------------------------------------------------------------------
        $display("\n=== TEST 1: reset defaults ===");
        do_reset;
        read_reg(ADDR0, 3'd0, rd); check8("Input  Port0 (pins pulled up)", rd, 8'hFF);
        read_reg(ADDR0, 3'd1, rd); check8("Input  Port1 (pins pulled up)", rd, 8'hFF);
        read_reg(ADDR0, 3'd2, rd); check8("Output Port0 default",          rd, 8'hFF);
        read_reg(ADDR0, 3'd3, rd); check8("Output Port1 default",          rd, 8'hFF);
        read_reg(ADDR0, 3'd4, rd); check8("Polarity Port0 default",        rd, 8'h00);
        read_reg(ADDR0, 3'd5, rd); check8("Polarity Port1 default",        rd, 8'h00);
        read_reg(ADDR0, 3'd6, rd); check8("Config Port0 default",          rd, 8'hFF);
        read_reg(ADDR0, 3'd7, rd); check8("Config Port1 default",          rd, 8'hFF);
        check1("INT# idle high after reset", int_n, 1'b1);

        //----------------------------------------------------------------------
        $display("\n=== TEST 2: write / read back of R/W registers ===");
        do_reset;
        for (r = 2; r < 8; r = r + 1) begin
            write_reg(ADDR0, r[2:0], 8'hA5);
            read_reg (ADDR0, r[2:0], rd);
            check8("Readback 0xA5 (reg cmd shown in wave)", rd, 8'hA5);
            write_reg(ADDR0, r[2:0], 8'h5A);
            read_reg (ADDR0, r[2:0], rd);
            check8("Readback 0x5A (reg cmd shown in wave)", rd, 8'h5A);
        end
        do_reset;
        write_reg(ADDR0, 3'd0, 8'h12);               // input regs are read-only
        read_reg (ADDR0, 3'd0, rd); check8("Write to Input Port0 ignored", rd, 8'hFF);

        //----------------------------------------------------------------------
        $display("\n=== TEST 3: address matching ===");
        do_reset;
        i2c_start; i2c_write_byte({7'h21, 1'b0}, last_addr_ack); i2c_stop;
        check1("Wrong address 0x21 -> NACK", last_addr_ack, 1'b0);
        i2c_start; i2c_write_byte({7'h20, 1'b0}, last_addr_ack); i2c_stop;
        check1("Address 0x20 -> ACK",        last_addr_ack, 1'b1);
        i2c_start; i2c_write_byte({7'h25, 1'b0}, last_addr_ack); i2c_stop;
        check1("Address 0x25 (DUT1) -> ACK", last_addr_ack, 1'b1);
        i2c_start; i2c_write_byte({7'h20, 1'b1}, last_addr_ack);
        i2c_read_byte(1'b0, rd); i2c_stop;
        check1("Address 0x20 + R -> ACK",    last_addr_ack, 1'b1);

        //----------------------------------------------------------------------
        $display("\n=== TEST 4: pins configured as outputs ===");
        do_reset;
        write_reg(ADDR0, 3'd6, 8'h00);
        write_reg(ADDR0, 3'd7, 8'h00);
        check8("Port0 pins drive default 0xFF", p0, 8'hFF);
        check8("Port1 pins drive default 0xFF", p1, 8'hFF);
        write_reg(ADDR0, 3'd2, 8'h3C);
        write_reg(ADDR0, 3'd3, 8'hC3);
        check8("Port0 pins follow Output0 = 3C", p0, 8'h3C);
        check8("Port1 pins follow Output1 = C3", p1, 8'hC3);

        //----------------------------------------------------------------------
        $display("\n=== TEST 5: pins configured as inputs ===");
        do_reset;
        ext0_oe = 8'hFF; ext0_val = 8'h96;
        ext1_oe = 8'hFF; ext1_val = 8'h69;
        read_reg(ADDR0, 3'd0, rd); check8("Input Port0 reflects pins 96", rd, 8'h96);
        read_reg(ADDR0, 3'd1, rd); check8("Input Port1 reflects pins 69", rd, 8'h69);

        //----------------------------------------------------------------------
        $display("\n=== TEST 6: polarity inversion ===");
        do_reset;
        ext0_oe = 8'hFF; ext0_val = 8'h96;
        write_reg(ADDR0, 3'd4, 8'hFF);
        read_reg (ADDR0, 3'd0, rd); check8("Polarity FF : 96 -> 69", rd, 8'h69);
        write_reg(ADDR0, 3'd4, 8'h0F);
        read_reg (ADDR0, 3'd0, rd); check8("Polarity 0F : 96 -> 99", rd, 8'h99);
        read_reg (ADDR0, 3'd4, rd); check8("Polarity reg itself unchanged", rd, 8'h0F);

        //----------------------------------------------------------------------
        $display("\n=== TEST 7: mixed direction ===");
        do_reset;
        write_reg(ADDR0, 3'd2, 8'hAF);               // output latch
        write_reg(ADDR0, 3'd6, 8'h0F);               // [7:4] out, [3:0] in
        ext0_oe = 8'h0F; ext0_val = 8'h05;           // external drives low nibble
        #200;
        check8("Pins = DUT high nibble + ext low nibble", p0, 8'hA5);
        read_reg(ADDR0, 3'd0, rd);
        check8("Input reg reads back all 8 pins", rd, 8'hA5);

        //----------------------------------------------------------------------
        $display("\n=== TEST 8: port 0 <-> port 1 auto-toggle ===");
        do_reset;
        wbuf[0] = 8'h11; wbuf[1] = 8'h22; wbuf[2] = 8'h33;
        write_burst(ADDR0, 3'd2, 3);                 // out0, out1, out0
        read_reg(ADDR0, 3'd2, rd); check8("3-byte write: Output0 = 3rd byte", rd, 8'h33);
        read_reg(ADDR0, 3'd3, rd); check8("3-byte write: Output1 = 2nd byte", rd, 8'h22);
        read_burst(ADDR0, 3'd2, 3);
        check8("Burst read byte 0 (Output0)", rbuf[0], 8'h33);
        check8("Burst read byte 1 (Output1)", rbuf[1], 8'h22);
        check8("Burst read byte 2 (Output0)", rbuf[2], 8'h33);
        read_burst(ADDR0, 3'd3, 2);                  // start at port 1
        check8("Burst from cmd 3, byte 0 (Output1)", rbuf[0], 8'h22);
        check8("Burst from cmd 3, byte 1 (Output0)", rbuf[1], 8'h33);
        wbuf[0] = 8'hF0; wbuf[1] = 8'h0F;
        write_burst(ADDR0, 3'd6, 2);                 // config pair
        read_burst (ADDR0, 3'd6, 2);
        check8("Config pair byte 0", rbuf[0], 8'hF0);
        check8("Config pair byte 1", rbuf[1], 8'h0F);

        //----------------------------------------------------------------------
        $display("\n=== TEST 9: interrupt assert / clear ===");
        do_reset;
        check1("INT# high initially", int_n, 1'b1);
        ext0_oe = 8'h08; ext0_val = 8'h00;           // pin P0_3 -> 0
        #200; check1("INT# low after P0_3 change", int_n, 1'b0);
        read_reg(ADDR0, 3'd1, rd);
        check1("Reading Port1 does not clear Port0 INT", int_n, 1'b0);
        read_reg(ADDR0, 3'd0, rd);
        check8("Port0 read returns changed value", rd, 8'hF7);
        check1("INT# high after Port0 read", int_n, 1'b1);
        ext0_oe = 8'h00;                             // P0_3 back high
        #200; check1("INT# low after P0_3 returns high", int_n, 1'b0);
        read_reg(ADDR0, 3'd0, rd);
        check1("INT# cleared again by read", int_n, 1'b1);
        // change and revert before any read: INT# must self-clear
        ext0_oe = 8'h08; #200; check1("INT# low (change)", int_n, 1'b0);
        ext0_oe = 8'h00; #200; check1("INT# high when change reverts", int_n, 1'b1);
        // port 1 change cleared only by port 1 read
        ext1_oe = 8'h80; ext1_val = 8'h00; #200;
        check1("INT# low after P1_7 change", int_n, 1'b0);
        read_reg(ADDR0, 3'd0, rd);
        check1("Port0 read does not clear Port1 INT", int_n, 1'b0);
        read_reg(ADDR0, 3'd1, rd);
        check1("INT# high after Port1 read", int_n, 1'b1);
        // output-configured pins must not interrupt
        do_reset;
        write_reg(ADDR0, 3'd6, 8'h00);               // all outputs
        write_reg(ADDR0, 3'd2, 8'h00);               // pins change 1 -> 0
        #200; check1("No INT# from output pin changes", int_n, 1'b1);

        //----------------------------------------------------------------------
        $display("\n=== TEST 10: repeated START and current-pointer read ===");
        do_reset;
        write_reg(ADDR0, 3'd3, 8'h77);
        read_reg (ADDR0, 3'd3, rd); check8("Repeated-START read of Output1", rd, 8'h77);
        i2c_start;                                   // set pointer only
        i2c_write_byte({ADDR0, 1'b0}, last_addr_ack);
        i2c_write_byte(8'h03, last_addr_ack);
        i2c_stop;
        read_current(ADDR0, 1);
        check8("Read from current pointer (cmd 3)", rbuf[0], 8'h77);

        //----------------------------------------------------------------------
        $display("\n=== TEST 11: two devices on one bus ===");
        do_reset;
        write_reg(ADDR1, 3'd6, 8'h00);               // DUT1 Config0 = outputs
        write_reg(ADDR1, 3'd2, 8'h5A);               // DUT1 Output0
        read_reg (ADDR1, 3'd6, rd); check8("DUT1 Config0 = 00", rd, 8'h00);
        read_reg (ADDR0, 3'd6, rd); check8("DUT0 Config0 untouched = FF", rd, 8'hFF);
        read_reg (ADDR0, 3'd2, rd); check8("DUT0 Output0 untouched = FF", rd, 8'hFF);
        check8("DUT1 Port0 pins = 5A", p0_b, 8'h5A);
        check8("DUT0 Port0 pins = FF (inputs, pulled up)", p0, 8'hFF);

        //----------------------------------------------------------------------
        $display("\n=== TEST 12: aborted transfers and back-to-back traffic ===");
        do_reset;
        i2c_start;                                   // STOP mid byte
        i2c_write_byte({ADDR0, 1'b0}, last_addr_ack);
        i2c_write_byte(8'h02, last_addr_ack);
        i2c_clock_zero_bits(4);
        i2c_stop;
        read_reg(ADDR0, 3'd2, rd); check8("Partial byte not written", rd, 8'hFF);
        i2c_start;                                   // STOP right after command
        i2c_write_byte({ADDR0, 1'b0}, last_addr_ack);
        i2c_write_byte(8'h04, last_addr_ack);
        i2c_stop;
        write_reg(ADDR0, 3'd5, 8'hC9);               // immediately after
        read_reg (ADDR0, 3'd5, rd); check8("Write after aborted transfer", rd, 8'hC9);
        for (r = 0; r < 4; r = r + 1) begin          // back-to-back writes
            write_reg(ADDR0, 3'd3, 8'h10 + r);
            read_reg (ADDR0, 3'd3, rd);
            check8("Back-to-back write/read", rd, 8'h10 + r);
        end

        //----------------------------------------------------------------------
        $display("\n==========================================");
        if (errors == 0)
            $display(" ALL TESTS PASSED  (%0d checks)", tests);
        else
            $display(" %0d of %0d CHECKS FAILED", errors, tests);
        $display("==========================================\n");
        $finish;
    end

    // watchdog
    initial begin
        #60_000_000;
        $display("[FAIL] watchdog timeout");
        $finish;
    end
endmodule
