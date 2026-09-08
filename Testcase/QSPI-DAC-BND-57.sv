// =========================================================================
// TEST 57: 4-Byte Address Mode (>128MB Flash) (QSPI-DAC-BND-57)
// Validates that the controller can handle extended addressing for flash
// devices larger than 128Mb (16MB), requiring 4-byte address mode via DAC.
// =========================================================================

task automatic run_test_57(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 57: 4-Byte Address Mode (>128MB Flash) (QSPI-DAC-BND-57)");
    $display(" Target: Validate extended addressing for large flash devices");
    $display("=======================================================================\n");

    fork
        // ---------------------------------------------------------
        // THREAD 1: Mock Flash Slave (4-Byte Address Response)
        // ---------------------------------------------------------
        begin : mock_4byte_slave
            reg [31:0] payload = 32'h4AD0_57BE;
            reg [3:0]  slave_drv;
            forever begin
                @(negedge vif.CS_n);

                // Wait for 8-bit command + 32-bit address (10 cycles in full Quad mode = 40 bits)
                repeat(10) @(negedge vif.CLK);
                #1; // Delta-cycle safety

                // Shift out 8 nibbles (32 bits) of payload data
                for (int i = 7; i >= 0; i--) begin
                    slave_drv = (payload >> (i*4)) & 4'hF;
                    vif.D3 <= slave_drv[3];
                    vif.D2 <= slave_drv[2];
                    vif.D1 <= slave_drv[1];
                    vif.D0 <= slave_drv[0];
                    if (i > 0) @(negedge vif.CLK);
                end

                @(posedge vif.CS_n);
                #1;
                vif.D3 <= 1'bz; vif.D2 <= 1'bz; vif.D1 <= 1'bz; vif.D0 <= 1'bz;
            end
        end

        // ---------------------------------------------------------
        // THREAD 2: QSPI Master Automated DAC Sequence
        // ---------------------------------------------------------
        begin : master_ahb_sequence
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring Master for 4-Byte Quad DAC Mode ---");
            // Clock Divider
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx);
            
            // FIX: Explicitly configure the Address Bytes Register to 4 bytes (Placeholder: 0x34)
            tx = new(); tx.paddr = 32'h34; tx.pwdata = 32'h0000_0004; agt.send_write(tx);

            $display("[INFO] --- STEP 2: Enabling DAC & Quad Mode ---");
            // DAC Enable (0x4000) + Quad Enable (0x0400) + Reset Release (0x0004) -> 0x4404
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4404; agt.send_write(tx);

            // Allow the AHB routing matrix to settle
            repeat(2) @(posedge vif.pclk);

            $display("[INFO] --- STEP 3: Executing Direct AHB Memory Fetch ---");
            // The automated FSM injects the 4-byte address seamlessly on the AHB fetch
            tx = new(); tx.paddr = 32'h1000_0000; agt.send_read(tx);
            val = tx.prdata;
        end
    join_any

    disable fork;
    vif.D3 <= 1'bz; vif.D2 <= 1'bz; vif.D1 <= 1'bz; vif.D0 <= 1'bz;

    $display("[INFO] --- STEP 4: Final Result Evaluation ---");
    if (val === 32'h4AD0_57BE) begin
        $display("   [PASS] 4-byte address mode data captured via DAC: %h\n", val);
    end else begin
        $display("   [FAIL] Data mismatch or collision. Expected 4AD057BE, Got: %h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-DAC-BND-57");
    tb_top.scoreboard.mark_as_run("QSPI-DAC-BND-57");
    if (test_pass)
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask
