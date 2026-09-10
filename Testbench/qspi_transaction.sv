//=============================================================================
// Class: qspi_transaction
// Purpose:     Transaction object representing a single APB access to the QSPI
//              controller. Carries address, write/read data, byte strobes,
//              response fields and protocol-violation controls.
//
// REVISION 2026-09-08:
//   [FIX-A] pstrb is no longer `rand` and now defaults to 4'hF. Previously it
//           was a rand field left at 4'h0 whenever a test built a transaction
//           by hand instead of randomizing it. A pstrb of 0 makes the DUT
//           legitimately drop the write, so hand-built CTRL writes (including
//           start requests) were silently discarded and the transfer never
//           ran. post_randomize() could not save that path because it only
//           executes on randomize().
//   [FIX-B] Removed the dead QSPI-config fields (cmd_val, dummy_cycles,
//           is_quad, is_ddr, is_dac). No driver or scoreboard read them, and
//           is_ddr / is_dac describe hardware this DUT does not implement.
//           Kept a rand_pstrb knob for tests that *want* randomized strobes.
//   [FIX-C] Address constraint now targets the real register map instead of a
//           64 KB range, so randomized transactions land on actual registers.
//=============================================================================
class qspi_transaction;

  // =========================================================================
  // Register map (mirrors the DUT) - useful for directed tests
  // =========================================================================
  typedef enum bit [7:0] {
    ADDR_CTRL    = 8'h00,
    ADDR_TXDATA  = 8'h04,
    ADDR_RXDATA  = 8'h08,
    ADDR_CLKDIV  = 8'h0C,
    ADDR_XFERLEN = 8'h10,
    ADDR_DUMMY   = 8'h14,
    ADDR_STATUS  = 8'h18,
    ADDR_TIMEOUT = 8'h24,
    ADDR_DMA     = 8'h28
  } reg_addr_e;

  // =========================================================================
  // Control & Protocol Fields
  // =========================================================================
  rand  bit [31:0] paddr;             // APB address (word-aligned via constraint)
  rand  bit [31:0] pwdata;            // write data (APB write or TX FIFO push)

  // [FIX-A] non-rand, safe default. Set rand_pstrb = 1 before randomize() if
  // a test genuinely wants randomized byte lanes.
        bit [3:0]  pstrb   = 4'hF;    // byte strobes
        bit        rand_pstrb = 1'b0; // opt-in strobe randomization

        bit        pwrite  = 1'b1;    // 1=write, 0=read
        bit        presetn = 1'b1;    // reset state (pass-through)

        bit [31:0] prdata  = 32'h0;   // read data (filled by monitor / driver)
        bit        pslverr = 1'b0;    // slave error response
        bit        pready  = 1'b1;    // slave ready

  // =========================================================================
  // Test Control & Violation Flags
  // =========================================================================
        bit        back_to_back   = 1'b0; // 1 = keep PSEL high after transfer
        bit [1:0]  violation_mode = 0;    // 1=toggle paddr, 2=toggle pwdata, 3=toggle pwrite

  // =========================================================================
  // Constraints
  // [FIX-C] constrain to the DUT's real register offsets
  // =========================================================================
  constraint c_addr {
    paddr inside {32'h00, 32'h04, 32'h08, 32'h0C, 32'h10,
                  32'h14, 32'h18, 32'h24, 32'h28};
  }

  function new(string name = "qspi_transaction");
    // pstrb / pwrite defaults are applied at declaration so that hand-built
    // transactions are immediately usable without randomize().
  endfunction

  // [FIX-A] only touch pstrb when the test opted in; never leave it at 0.
  function void post_randomize();
    if (rand_pstrb) begin
      pstrb = 4'(  $urandom_range(1, 15) );   // never 0
    end else begin
      pstrb = 4'hF;
    end
  endfunction

  function string convert2string();
    return $sformatf("%s addr=0x%02h wdata=0x%08h strb=0x%01h rdata=0x%08h slverr=%0b",
                     pwrite ? "WR" : "RD", paddr[7:0], pwdata, pstrb, prdata, pslverr);
  endfunction

endclass

