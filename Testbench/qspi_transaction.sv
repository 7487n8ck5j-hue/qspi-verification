//=============================================================================
// Class: qspi_transaction
// Purpose:     SystemVerilog transaction object representing an APB access or
//              QSPI transfer. Carries address, write/read data, control, and
//              response fields plus test-control flags.
//
// CORRECTED: 2026-09-07
//   - Added pstrb field (was missing — DUT uses pstrb[3:0])
//   - Added constraint for pstrb default = 4'hF
//   - Added post_randomize for QSPI-specific defaults
//=============================================================================
class qspi_transaction;

  // =========================================================================
  // Control & Protocol Fields
  // =========================================================================
  rand  bit [31:0] paddr;          // APB address (word-aligned via constraint)
  rand  bit [31:0] pwdata;         // write data (APB write or TX FIFO push)
  rand  bit [3:0]  pstrb;          // byte strobes (FIXED: was missing)

        bit        pwrite = 1'b1;  // 1=write, 0=read
        bit        presetn = 1'b1; // reset state (pass-through)

        bit [31:0] prdata = 32'h0; // read data (filled by monitor / RX FIFO read)
        bit        pslverr = 1'b0; // slave error response
        bit        pready = 1'b1;  // slave ready

  // =========================================================================
  // QSPI-Specific Configuration & Operation Fields
  // =========================================================================
  rand  bit [7:0]  cmd_val;        // SPI Command byte (e.g., Fast Read, Quad Read)
  rand  bit [2:0]  dummy_cycles;   // Number of dummy wait cycles
  rand  bit        is_quad;        // 1 = Quad SPI mode, 0 = Single/Dual SPI mode
  rand  bit        is_ddr;         // 1 = Double Data Rate, 0 = SDR
  rand  bit        is_dac;         // 1 = Direct Access Controller (XIP/AHB) mode, 0 = Indirect

  // =========================================================================
  // Test Control & Violation Flags
  // =========================================================================
        bit        back_to_back = 1'b0;   // 1 = skip IDLE after transfer (burst)
        bit [1:0]  violation_mode = 0;    // 1=toggle paddr, 2=toggle pwdata, 3=toggle pwrite

  // =========================================================================
  // Constraints
  // =========================================================================
  constraint c_addr {
    paddr >= 32'h0;
    paddr <= 32'h0000_FFFF;
    paddr[1:0] == 2'b00;
  }

  constraint c_qspi_defaults {
    dummy_cycles <= 3'd7;
  }

  // FIXED: constraint for pstrb — default all bytes enabled
  constraint c_pstrb {
    pstrb inside {[4'h1:4'hF]};
  }

  function new(string name = "qspi_transaction");
    // Standalone class constructor
  endfunction

  // FIXED: post_randomize to set sensible defaults
  function void post_randomize();
    if (pstrb == 4'h0) pstrb = 4'hF;  // ensure non-zero strobe
  endfunction

endclass

