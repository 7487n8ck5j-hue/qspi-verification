//=============================================================================
// Class: qspi_sb
// Purpose:     Reference model / scoreboard for the QSPI controller's APB
//              register interface.
//
// REVISION 2026-09-08:
//   [FIX-A to FIX-D] Retained from previous fixes.
//   [FIX-E] Corrected CTRL register wmask/rmask. Previously set to 32'h0000_7FFF, 
//           which falsely included Reserved Bit 6. Modified to 32'h0000_7FBF to 
//           match RTL boundaries and prevent false read mismatch errors.
//=============================================================================
class qspi_sb;

  typedef enum int {
    RW_MASKED,    // read-write, with a write mask and read mask
    WO_FIFO,      // write-only FIFO port, reads as 0
    RO_STATUS,    // read-only, value produced by hardware
    RO_FIFO       // read-only FIFO port, value produced by hardware
  } reg_kind_e;

  typedef struct {
    string      name;
    reg_kind_e  kind;
    bit [31:0]  wmask;      // bits an APB write can change
    bit [31:0]  rmask;      // bits that read back non-zero
    bit [31:0]  w1c;        // write-1-to-clear bits
    bit [31:0]  hw_mask;    // bits driven by hardware -> excluded from compare
    bit [31:0]  reset_val;
    bit [31:0]  shadow;     // expected current value
    bit         volatile_r; // 1 = do not data-compare reads
    bit         soft_rst;   // 1 = cleared by CTRL[8] software reset
  } reg_model_t;

  reg_model_t rm[bit [7:0]];

  int compare_pass        = 0;
  int compare_fail        = 0;
  int error_handled       = 0;
  int skipped_volatile    = 0;
  int monitor_errors      = 0;
  int write_count         = 0;
  int read_count          = 0;
  int out_of_range_access = 0;
  int pslverr_mismatch    = 0;

  string current_test_id;
  qspi_test_results test_results;

  function new(string name = "qspi_sb");
    current_test_id = "UNKNOWN";
    test_results = new();
    build_reg_model();
  endfunction

  local function void add_reg(bit [7:0] off, string name, reg_kind_e kind,
                              bit [31:0] wmask, bit [31:0] rmask,
                              bit [31:0] w1c, bit [31:0] hw, bit [31:0] rst,
                              bit vol = 1'b0, bit srst = 1'b0);
    reg_model_t r;
    r.name       = name;
    r.kind       = kind;
    r.wmask      = wmask;
    r.rmask      = rmask;
    r.w1c        = w1c;
    r.hw_mask    = hw;
    r.reset_val  = rst;
    r.shadow     = rst;
    r.volatile_r = vol;
    r.soft_rst   = srst;
    rm[off]      = r;
  endfunction

  function void build_reg_model();
    rm.delete();
    // [FIX-E] Updated wmask and rmask to 0x7FBF, excluding Bit 6 (Reserved).
    //       off    name       kind       wmask         rmask         w1c           hw_mask       reset         vol   srst
    add_reg(8'h00,"CTRL",     RW_MASKED, 32'h0000_7FBF,32'h0000_7FBF,32'h0000_10B0,32'h0000_10B1,32'h0000_0004,1'b0, 1'b1);
    add_reg(8'h04,"TXDATA",   WO_FIFO,   32'h0000_0000,32'h0000_0000,32'h0,        32'h0,        32'h0,        1'b0, 1'b1);
    add_reg(8'h08,"RXDATA",   RO_FIFO,   32'h0000_0000,32'hFFFF_FFFF,32'h0,        32'hFFFF_FFFF,32'h0,        1'b1, 1'b1);
    add_reg(8'h0C,"CLKDIV",   RW_MASKED, 32'hFFFF_FFFF,32'hFFFF_FFFF,32'h0,        32'h0,        32'h0000_0001,1'b0, 1'b0);
    add_reg(8'h10,"XFERLEN",  RW_MASKED, 32'hFFFF_FFFF,32'hFFFF_FFFF,32'h0,        32'h0,        32'h0000_001F,1'b0, 1'b0);
    add_reg(8'h14,"DUMMY",    RW_MASKED, 32'h0000_00FF,32'h0000_00FF,32'h0,        32'h0,        32'h0,        1'b0, 1'b0);
    add_reg(8'h18,"STATUS",   RO_STATUS, 32'h0000_0000,32'h0010_00FF,32'h0,        32'h0010_00FF,32'h0,        1'b1, 1'b1);
    add_reg(8'h24,"TIMEOUT",  RW_MASKED, 32'hFFFF_FFFF,32'hFFFF_FFFF,32'h0,        32'h0,        32'h0,        1'b0, 1'b0);
    add_reg(8'h28,"DMA",      RW_MASKED, 32'hFFFF_FFFF,32'hFFFF_FFFF,32'h0,        32'h0,        32'h0,        1'b0, 1'b0);
  endfunction

  function void reset_model();
    foreach (rm[off]) begin
      rm[off].shadow     = rm[off].reset_val;
      rm[off].volatile_r = (rm[off].kind != RW_MASKED);
    end
  endfunction

  function void soft_reset_model();
    foreach (rm[off]) begin
      if (rm[off].soft_rst) begin
        rm[off].shadow     = rm[off].reset_val;
        rm[off].volatile_r = (rm[off].kind != RW_MASKED);
      end
    end
  endfunction

  function void set_test_id(string test_id);
    current_test_id = test_id;
    if (test_results != null) begin
      test_results.set_current_test(test_id);
    end
  endfunction

  function void set_test_result(bit passed, string status = "");
    if (test_results != null) test_results.set_test_pass(passed, status);
  endfunction

  function qspi_test_results get_test_results();
    return test_results;
  endfunction

  function void report_monitor_error(string error_msg);
    monitor_errors++;
    set_test_result(0, error_msg);
    $display("[QSPI_SB ERROR] %s", error_msg);
  endfunction

  function bit addr_is_mapped(bit [31:0] addr);
    if (addr[31:8] != 24'd0) return 0;          // out of register page
    if (addr[1:0]  != 2'b00) return 0;          // unaligned
    return ((rm.exists(addr[7:0])) != 0);
  endfunction

  function bit expect_pslverr(bit [31:0] addr);
    return !addr_is_mapped(addr);
  endfunction

  function bit check_transaction_validity(input qspi_transaction trans, input string t);
    if ($isunknown(trans.paddr)) begin
      report_monitor_error($sformatf("%s: paddr is X/Z!", t));
      return 0;
    end
    if ($isunknown(trans.pwrite)) begin
      report_monitor_error($sformatf("%s: pwrite is X/Z!", t));
      return 0;
    end
    return 1;
  endfunction

  function void set_expected(bit [31:0] addr, bit [31:0] data);
    if (((rm.exists(addr[7:0])) != 0)) rm[addr[7:0]].shadow = data & rm[addr[7:0]].rmask;
  endfunction

  function bit [31:0] get_expected(bit [31:0] addr);
    if (((rm.exists(addr[7:0])) != 0)) return rm[addr[7:0]].shadow;
    return 32'h0;
  endfunction

  local function bit [31:0] strobe_mask(bit [3:0] pstrb);
    bit [31:0] m = 32'h0;
    if (pstrb[0]) m[7:0]   = 8'hFF;
    if (pstrb[1]) m[15:8]  = 8'hFF;
    if (pstrb[2]) m[23:16] = 8'hFF;
    if (pstrb[3]) m[31:24] = 8'hFF;
    return m;
  endfunction

  virtual function void process_write(input qspi_transaction trans);
    bit [7:0]  off;
    bit [31:0] eff, newval;
    reg_kind_e knd;

    if (!check_transaction_validity(trans, "WRITE")) return;

    if (expect_pslverr(trans.paddr)) begin
      out_of_range_access++;
      if (trans.pslverr) begin
        error_handled++;
        set_test_result(1, $sformatf("PSLVERR correctly asserted on write to 0x%0h", trans.paddr));
      end else begin
        pslverr_mismatch++; compare_fail++;
        $display("[QSPI_SB ERROR] WRITE 0x%0h is illegal but PSLVERR was NOT asserted", trans.paddr);
        set_test_result(0, $sformatf("missing PSLVERR on illegal write 0x%0h", trans.paddr));
      end
      return;   
    end

    if (trans.pslverr) begin
      pslverr_mismatch++; compare_fail++;
      $display("[QSPI_SB ERROR] WRITE 0x%0h is legal but PSLVERR was asserted", trans.paddr);
      set_test_result(0, $sformatf("unexpected PSLVERR on legal write 0x%0h", trans.paddr));
      return;
    end

    if ($isunknown(trans.pwdata)) begin
      report_monitor_error($sformatf("WRITE: pwdata is X/Z at 0x%0h!", trans.paddr));
      return;
    end

    off = trans.paddr[7:0];
    write_count++;

    eff = strobe_mask(trans.pstrb);
    if (eff == 32'h0) return;

    knd = rm[off].kind;
    case (knd)
      WO_FIFO, RO_STATUS, RO_FIFO: begin
      end
      RW_MASKED: begin
        bit [31:0] wr_bits = rm[off].wmask & eff;
        newval = rm[off].shadow;
        newval = (newval & ~(wr_bits & ~rm[off].w1c)) |
                 (trans.pwdata & wr_bits & ~rm[off].w1c);
        newval = newval & ~(trans.pwdata & wr_bits & rm[off].w1c);
        rm[off].shadow = newval & rm[off].rmask;

        if (off == 8'h00) begin
          rm[8'h00].shadow[8] = 1'b0;      

          if (trans.pwdata[8] && trans.pstrb[1]) begin
            rm[8'h00].shadow[0]  = 1'b0;   
            rm[8'h00].shadow[4]  = 1'b0;   
            rm[8'h00].shadow[5]  = 1'b0;   
            rm[8'h00].shadow[7]  = 1'b0;   
            rm[8'h00].shadow[12] = 1'b0;   
          end

          if (trans.pwdata[0] && trans.pstrb[0]) rm[8'h00].volatile_r = 1'b1;
        end
      end
      default: ;
    endcase
  endfunction

  virtual function void process_read(input qspi_transaction trans);
    bit [7:0]  off;
    bit [31:0] expected;
    bit [31:0] cmp_mask;

    if (!check_transaction_validity(trans, "READ")) return;

    if (expect_pslverr(trans.paddr)) begin
      out_of_range_access++;
      if (trans.pslverr) begin
        error_handled++;
        set_test_result(1, $sformatf("PSLVERR correctly asserted on read from 0x%0h", trans.paddr));
      end else begin
        pslverr_mismatch++; compare_fail++;
        $display("[QSPI_SB ERROR] READ 0x%0h is illegal but PSLVERR was NOT asserted", trans.paddr);
        set_test_result(0, $sformatf("missing PSLVERR on illegal read 0x%0h", trans.paddr));
      end
      return;
    end

    if (trans.pslverr) begin
      pslverr_mismatch++; compare_fail++;
      $display("[QSPI_SB ERROR] READ 0x%0h is legal but PSLVERR was asserted", trans.paddr);
      set_test_result(0, $sformatf("unexpected PSLVERR on legal read 0x%0h", trans.paddr));
      return;
    end

    if ($isunknown(trans.prdata)) begin
      report_monitor_error($sformatf("READ: prdata is X/Z at 0x%0h!", trans.paddr));
      return;
    end

    off = trans.paddr[7:0];
    read_count++;

    if (rm[off].volatile_r) begin
      skipped_volatile++;
      if ((trans.prdata & ~rm[off].rmask) != 32'h0) begin
        compare_fail++;
        $display("[QSPI_SB ERROR] %s read 0x%08h sets bits outside read mask 0x%08h",
                 rm[off].name, trans.prdata, rm[off].rmask);
        set_test_result(0, $sformatf("%s read outside read mask", rm[off].name));
      end
      return;
    end

    cmp_mask = rm[off].rmask & ~rm[off].hw_mask;
    expected = rm[off].shadow & cmp_mask;

    if ((trans.prdata & cmp_mask) === expected) begin
      compare_pass++;
      set_test_result(1, $sformatf("%s readback ok", rm[off].name));
    end else begin
      compare_fail++;
      $display("[QSPI_SB ERROR] %s (0x%02h) MISMATCH: expected 0x%08h, got 0x%08h (mask 0x%08h)",
               rm[off].name, off, expected, trans.prdata & cmp_mask, cmp_mask);
      set_test_result(0, $sformatf("%s readback mismatch", rm[off].name));
    end
  endfunction

  function void ctrl_settled(bit [31:0] actual_ctrl);
    rm[8'h00].shadow     = actual_ctrl & rm[8'h00].rmask;
    rm[8'h00].volatile_r = 1'b0;
  endfunction

  function void sync_reg(bit [31:0] addr, bit [31:0] actual);
    if (((rm.exists(addr[7:0])) != 0)) begin
      rm[addr[7:0]].shadow     = actual & rm[addr[7:0]].rmask;
      rm[addr[7:0]].volatile_r = 1'b0;
    end
  endfunction

  function void print_report();
    $display("==============================================");
    $display("[QSPI_SB] REFERENCE MODEL REPORT");
    $display("  READ COMPARE PASS   : %0d", compare_pass);
    $display("  READ COMPARE FAIL   : %0d", compare_fail);
    $display("  PSLVERR MISMATCHES  : %0d", pslverr_mismatch);
    $display("  ERROR RESP HANDLED  : %0d", error_handled);
    $display("  VOLATILE SKIPPED    : %0d", skipped_volatile);
    $display("  MONITOR ERRORS      : %0d", monitor_errors);
    $display("  WRITES OBSERVED     : %0d", write_count);
    $display("  READS OBSERVED      : %0d", read_count);
    $display("  ILLEGAL ACCESSES    : %0d", out_of_range_access);
    $display("==============================================");
  endfunction

endclass
