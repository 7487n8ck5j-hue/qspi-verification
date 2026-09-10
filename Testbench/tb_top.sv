//=============================================================================
// Testbench: tb_top
// Purpose:   Top level for the QSPI APB master. Instantiates the interface, the
//            DUT and a behavioural QSPI flash slave, generates the APB clock,
//            applies reset and runs the regression.
//
// REVISION 2026-09-08:
//   [FIX-A] Added a real QSPI slave model (qspi_flash_model). The model returns 
//           programmable data in single and quad mode for RX validation.
//   [FIX-B] Reset release moved off the clock edge to #23 to avoid simulation 
//           scheduling race conditions.
//   [FIX-G] QSPI data bus modelled on module-level wires with weak pullups 
//           to properly resolve tri-state drives between DUT and flash model.
//   [RESTORED] External test sequences (TC01-TC57) included and called 
//              sequentially. Internal tasks removed to maintain standalone files.
//   [ADDED] scoreboard handle declaration for TC access (XMRE fix).
//=============================================================================
`timescale 1ns/1ps

// Testbench infrastructure
`include "./testbench/qspi_interface.sv"
`include "./testbench/qspi_transaction.sv"
`include "./testbench/qspi_test_results.sv"
`include "./testbench/qspi_scoreboard.sv"
`include "./testbench/qspi_driver.sv"
`include "./testbench/qspi_monitor.sv"
`include "./testbench/qspi_agent.sv"

// Test sequences (TC01-TC41)
`include "./testbench/test_seq/QSPI-AHB-SDR-01.sv"
`include "./testbench/test_seq/QSPI-APB-REG-02.sv"
`include "./testbench/test_seq/QSPI-PHY-POL-03.sv"
`include "./testbench/test_seq/QSPI-APB-LVL-04.sv"
`include "./testbench/test_seq/QSPI-DAC-XIP-05.sv"
`include "./testbench/test_seq/QSPI-APB-REG-06.sv"
`include "./testbench/test_seq/QSPI-DAC-XIP-07.sv"
`include "./testbench/test_seq/QSPI-DAC-XIP-08.sv"
`include "./testbench/test_seq/QSPI-PHY-DDR-09.sv"
`include "./testbench/test_seq/QSPI-PHY-RST-10.sv"
`include "./testbench/test_seq/QSPI-PHY-SDR-11.sv"
`include "./testbench/test_seq/QSPI-PHY-RST-12.sv"
`include "./testbench/test_seq/QSPI-APB-RST-13.sv"
`include "./testbench/test_seq/QSPI-PHY-REG-14.sv"
`include "./testbench/test_seq/QSPI-PHY-SDR-15.sv"
`include "./testbench/test_seq/QSPI-PHY-RST-16.sv"
`include "./testbench/test_seq/QSPI-PHY-SDR-17.sv"
`include "./testbench/test_seq/QSPI-APB-SRD-18.sv"
`include "./testbench/test_seq/QSPI-AHB-ERR-19.sv"
`include "./testbench/test_seq/QSPI-APB-CFG-20.sv"
`include "./testbench/test_seq/QSPI-PHY-DUM-21.sv"
`include "./testbench/test_seq/QSPI-PHY-DUM-22.sv"
`include "./testbench/test_seq/QSPI-APB-PAR-23.sv"
`include "./testbench/test_seq/QSPI-PHY-POL-24.sv"
`include "./testbench/test_seq/QSPI-PHY-ERR-25.sv"
`include "./testbench/test_seq/QSPI-IND-BWC-26.sv"
`include "./testbench/test_seq/QSPI-IND-BRC-27.sv"
`include "./testbench/test_seq/QSPI-IND-QUE-28.sv"
`include "./testbench/test_seq/QSPI-DMA-HSK-29.sv"
`include "./testbench/test_seq/QSPI-DAC-MBW-30.sv"
`include "./testbench/test_seq/QSPI-DAC-PPL-31.sv"
`include "./testbench/test_seq/QSPI-IND-BND-32.sv"
`include "./testbench/test_seq/QSPI-DAC-POL-33.sv"
`include "./testbench/test_seq/QSPI-APB-PAR-34.sv"
`include "./testbench/test_seq/QSPI-AHB-DEC-35.sv"
`include "./testbench/test_seq/QSPI-PHY-ZWS-36.sv"
`include "./testbench/test_seq/QSPI-PHY-DDR-37.sv"
`include "./testbench/test_seq/QSPI-AHB-REG-38.sv"
`include "./testbench/test_seq/QSPI-IND-LVL-39.sv"
`include "./testbench/test_seq/QSPI-PHY-HSK-40.sv"
`include "./testbench/test_seq/QSPI-APB-REG-41.sv"

// Test sequences (TC42-TC57 — NEW)
`include "./testbench/test_seq/QSPI-SPI-ERA-42.sv"
`include "./testbench/test_seq/QSPI-SPI-PGM-43.sv"
`include "./testbench/test_seq/QSPI-SPI-SUS-44.sv"
`include "./testbench/test_seq/QSPI-APB-ID-45.sv"
`include "./testbench/test_seq/QSPI-APB-SFD-46.sv"
`include "./testbench/test_seq/QSPI-AHB-OTP-47.sv"
`include "./testbench/test_seq/QSPI-AHB-WPR-48.sv"
`include "./testbench/test_seq/QSPI-PHY-ERR-49.sv"
`include "./testbench/test_seq/QSPI-AHB-ERR-50.sv"
`include "./testbench/test_seq/QSPI-PHY-ERR-51.sv"
`include "./testbench/test_seq/QSPI-PHY-CLK-52.sv"
`include "./testbench/test_seq/QSPI-PHY-CLK-53.sv"
`include "./testbench/test_seq/QSPI-AHB-MCS-54.sv"
`include "./testbench/test_seq/QSPI-APB-CFG-55.sv"
`include "./testbench/test_seq/QSPI-IND-BND-56.sv"
`include "./testbench/test_seq/QSPI-DAC-BND-57.sv"

// =========================================================================
// Behavioural QSPI flash slave model (Upgraded with Clock-Edge Shift Counter)
// =========================================================================

module qspi_flash_model (
    input  wire CS_n,
    input  wire CLK,
    input  wire quad_mode,     // 1 = drive D3..D0, 0 = drive D1 only
    input  wire enable,        // 0 = fully tri-state (lines revert to pullups)
    inout  wire D3,
    inout  wire D2,
    inout  wire D1,
    inout  wire D0
);

  reg [31:0] tx_pattern = 32'hA5A5_A5A5;
  reg [31:0] sr         = 32'h0;
  int        neg_edge_cnt = 0;
  int        rx_delay     = 0;   // Clocks to skip (TX + Dummy phases) before shifting

  always @(negedge CLK or posedge CS_n) begin
    if (CS_n) begin
      sr           <= tx_pattern;
      neg_edge_cnt <= 0;
    end else begin
      if (neg_edge_cnt >= rx_delay) begin
        if (quad_mode) sr <= {sr[27:0], 4'h0};
        else           sr <= {sr[30:0], 1'b0};
      end
      neg_edge_cnt <= neg_edge_cnt + 1;
    end
  end

  wire drive = enable && !CS_n && (neg_edge_cnt >= rx_delay);

  assign D3 = (drive && quad_mode) ? sr[31] : 1'bz;
  assign D2 = (drive && quad_mode) ? sr[30] : 1'bz;
  assign D1 = drive ? (quad_mode ? sr[29] : sr[31]) : 1'bz;
  assign D0 = (drive && quad_mode) ? sr[28] : 1'bz;

  task set_pattern(input [31:0] p);
    tx_pattern = p;
    sr = p;
  endtask

  task set_delay(input int d);
    rx_delay = d;
  endtask

endmodule

module tb_top();

  // Unified interface containing both APB signals and QSPI physical lines
  qspi_if vif();

  int cycle_count = 0;
  int reset_count = 0;

  // Handle to our pure SV agent
  qspi_agent qspi_agt;

  // ADDED FOR XMRE FIX: scoreboard handle accessible from TC tasks
  qspi_test_results scoreboard;

  // Flash model controls
  logic flash_quad_mode = 1'b0;
  logic flash_enable    = 1'b1;

  // =====================================================================
  // QSPI data bus modelled on module-level wires with weak pullups
  // =====================================================================
  wire qd3, qd2, qd1, qd0;

  assign (weak0, weak1) qd3 = 1'b1;
  assign (weak0, weak1) qd2 = 1'b1;
  assign (weak0, weak1) qd1 = 1'b1;
  assign (weak0, weak1) qd0 = 1'b1;

  // Mirror the resolved bus into the interface
  assign vif.D3 = qd3;
  assign vif.D2 = qd2;
  assign vif.D1 = qd1;
  assign vif.D0 = qd0;

  // =====================================================================
  // DUT Instantiation
  // =====================================================================
  qspi_apb_master dut (
      .pclk       (vif.pclk),
      .presetn    (vif.presetn),
      .paddr      (vif.paddr),
      .psel       (vif.psel),
      .penable    (vif.penable),
      .pwrite     (vif.pwrite),
      .pwdata     (vif.pwdata),
      .pstrb      (vif.pstrb),
      .prdata     (vif.prdata),
      .pready     (vif.pready),
      .pslverr    (vif.pslverr),

      .CS_n       (vif.CS_n),
      .CLK        (vif.CLK),
      .D3         (qd3),
      .D2         (qd2),
      .D1         (qd1),
      .D0         (qd0),

      .FLASH_RST_n(vif.FLASH_RST_n),
      .irq        (vif.irq),
      .rx_dma_req (vif.rx_dma_req),
      .tx_dma_req (vif.tx_dma_req),
      .rx_dma_ack (vif.rx_dma_ack),
      .tx_dma_ack (vif.tx_dma_ack)
  );

  // =====================================================================
  // Behavioural QSPI flash slave
  // =====================================================================
  qspi_flash_model flash (
      .CS_n      (vif.CS_n),
      .CLK       (vif.CLK),
      .quad_mode (flash_quad_mode),
      .enable    (flash_enable),
      .D3        (qd3),
      .D2        (qd2),
      .D1        (qd1),
      .D0        (qd0)
  );

  // =====================================================================
  // Clock Generation - 10 ns period (100 MHz)
  // =====================================================================
  initial begin
    vif.pclk = 1'b0;
    forever begin
      #5 vif.pclk = ~vif.pclk;
      if (vif.pclk) cycle_count++;
    end
  end

  // =====================================================================
  // Reset Edge Detection
  // =====================================================================
  always @(negedge vif.presetn) begin
    reset_count++;
    $display("[QSPI_TOP INFO] ===== RESET ASSERTED (count=%0d) =====", reset_count);
  end

  always @(posedge vif.presetn) begin
    $display("[QSPI_TOP INFO] ===== RESET RELEASED =====");
  end

  // =====================================================================
  // Initial Reset & Test Execution Sequence
  // =====================================================================
  initial begin
    vif.presetn = 1'b0;

    $display("\n========================================================");
    $display("                QSPI REGRESSION START                   ");
    $display("========================================================\n");

    #23;
    vif.presetn = 1'b1;
    $display("[QSPI_TOP INFO] RESET is released. Booting Agent...\n");

    qspi_agt = new("qspi_agt", vif);
    scoreboard = qspi_agt.sb.test_results;

    fork
        qspi_agt.run();
    join_none

    // =================================================================
    // RUN REGRESSION SEQUENTIALLY (TC01-TC57)
    // =================================================================
    run_test_01(qspi_agt, vif);
    run_test_02(qspi_agt, vif);
    run_test_03(qspi_agt, vif);
    run_test_04(qspi_agt, vif);
    run_test_05(qspi_agt, vif);
    run_test_06(qspi_agt, vif);
    run_test_07(qspi_agt, vif);
    run_test_08(qspi_agt, vif);
    run_test_09(qspi_agt, vif);
    run_test_10(qspi_agt, vif);
    run_test_11(qspi_agt, vif);
    run_test_12(qspi_agt, vif);
    run_test_13(qspi_agt, vif);
    run_test_14(qspi_agt, vif);
    run_test_15(qspi_agt, vif);
    run_test_16(qspi_agt, vif);
    run_test_17(qspi_agt, vif);
    run_test_18(qspi_agt, vif);
    run_test_19(qspi_agt, vif);
    run_test_20(qspi_agt, vif);
    run_test_21(qspi_agt, vif);
    run_test_22(qspi_agt, vif);
    run_test_23(qspi_agt, vif);
    run_test_24(qspi_agt, vif);
    run_test_25(qspi_agt, vif);
    run_test_26(qspi_agt, vif);
    run_test_27(qspi_agt, vif);
    run_test_28(qspi_agt, vif);
    run_test_29(qspi_agt, vif);
    run_test_30(qspi_agt, vif);
    run_test_31(qspi_agt, vif);
    run_test_32(qspi_agt, vif);
    run_test_33(qspi_agt, vif);
    run_test_34(qspi_agt, vif);
    run_test_35(qspi_agt, vif);
    run_test_36(qspi_agt, vif);
    run_test_37(qspi_agt, vif);
    run_test_38(qspi_agt, vif);
    run_test_39(qspi_agt, vif);
    run_test_40(qspi_agt, vif);
    run_test_41(qspi_agt, vif);
    // NEW TCs (TC42-TC57)
    run_test_42(qspi_agt, vif);
    run_test_43(qspi_agt, vif);
    run_test_44(qspi_agt, vif);
    run_test_45(qspi_agt, vif);
    run_test_46(qspi_agt, vif);
    run_test_47(qspi_agt, vif);
    run_test_48(qspi_agt, vif);
    run_test_49(qspi_agt, vif);
    run_test_50(qspi_agt, vif);
    run_test_51(qspi_agt, vif);
    run_test_52(qspi_agt, vif);
    run_test_53(qspi_agt, vif);
    run_test_54(qspi_agt, vif);
    run_test_55(qspi_agt, vif);
    run_test_56(qspi_agt, vif);
    run_test_57(qspi_agt, vif);

    #1000;

    $display("\n========================================================");
    $display("                QSPI REGRESSION SUMMARY                 ");
    $display("========================================================\n");

    qspi_agt.sb.test_results.print_summary();

    $display("\n");

    $display("=================================================================");
    $display("[%s REPORT] QSPI Agent Summary", qspi_agt.agent_name);
    if (qspi_agt.drv != null)  qspi_agt.drv.print_report();
    if (qspi_agt.mon != null)  qspi_agt.mon.print_report();
    $display("=================================================================");

    $display("[QSPI_TOP INFO] ===== SIMULATION FINISHED =====");
    $display("[QSPI_TOP INFO] Total cycles = %0d", cycle_count);
    $display("[QSPI_TOP INFO] Total resets = %0d", reset_count);
    if (qspi_agt.sb.test_results.regression_passed())
      $display("[QSPI_TOP INFO] ===== REGRESSION PASSED =====");
    else
      $display("[QSPI_TOP INFO] ===== REGRESSION FAILED =====");
    $finish;
  end

  // =====================================================================
  // Wave Dump Setup
  // =====================================================================
  initial begin
`ifdef DUMP_FSDB
    $fsdbDumpfile("fsdbdump.fsdb");
    $fsdbDumpvars(0, tb_top);
`elsif DUMP_VCD
    $dumpfile("qspi_tb.vcd");
    $dumpvars(0, tb_top);
`endif
  end

endmodule
