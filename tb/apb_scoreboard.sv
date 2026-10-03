// ============================================================================
// File: apb_scoreboard.sv
// Project: APB-Compliant Configurable CRC-32 Hardware Accelerator
// Author: Pradeep (Team 7: Bhuvanesh S, Aathithya K, Pradeep)
// Description: Golden Reference Model and Scoreboard verifying register accesses,
//              W1C interrupt handling, protocol errors, and parallel CRC math.
// ============================================================================

`timescale 1ns / 1ps

class apb_scoreboard;

  mailbox #(apb_transaction) mbx;

  // Mirror Registers (Software Model)
  bit [31:0] model_ctrl;
  bit [31:0] model_poly;
  bit [31:0] model_init;
  bit [31:0] model_data_in;
  bit [31:0] model_int_en;
  bit [31:0] model_int_stat;
  bit [31:0] model_accum;
  bit        model_ready;

  // Verification Statistics
  int total_trans;
  int write_count;
  int read_count;
  int match_count;
  int mismatch_count;
  int error_resp_count;

  // Bit reversal helper functions
  function bit [7:0] ref_byte(bit [7:0] in);
    bit [7:0] out;
    for (int i = 0; i < 8; i++) out[i] = in[7 - i];
    return out;
  endfunction

  function bit [31:0] ref_word(bit [31:0] in);
    bit [31:0] out;
    for (int i = 0; i < 32; i++) out[i] = in[31 - i];
    return out;
  endfunction

  // Software Step Calculation
  function bit [31:0] step_crc8_model(bit [31:0] cur, bit [7:0] b, bit [31:0] poly);
    bit [31:0] c;
    c = cur ^ {b, 24'h0};
    for (int i = 0; i < 8; i++) begin
      if (c[31]) begin
        c = {c[30:0], 1'b0} ^ poly;
      end else begin
        c = {c[30:0], 1'b0};
      end
    end
    return c;
  endfunction

  // Compute expected final CRC result
  function bit [31:0] get_expected_crc();
    bit [31:0] res;
    res = model_ctrl[3] ? ref_word(model_accum) : model_accum; // refout
    if (model_ctrl[4]) begin // xorout
      res = res ^ 32'hFFFFFFFF;
    end
    return res;
  endfunction

  // Constructor
  function new(mailbox #(apb_transaction) mbx);
    this.mbx              = mbx;
    this.model_ctrl       = 32'h0000005C; // Default: REFIN=1, REFOUT=1, XOROUT=1, 32-bit
    this.model_poly       = 32'h04C11DB7; // IEEE 802.3
    this.model_init       = 32'hFFFFFFFF;
    this.model_accum      = 32'hFFFFFFFF;
    this.model_data_in    = 32'h0;
    this.model_int_en     = 32'h0;
    this.model_int_stat   = 32'h0;
    this.model_ready      = 1'b0;
    this.total_trans      = 0;
    this.write_count      = 0;
    this.read_count       = 0;
    this.match_count      = 0;
    this.mismatch_count   = 0;
    this.error_resp_count = 0;
  endfunction

  task run();
    apb_transaction tr;
    bit is_unaligned;
    bit is_out_of_range;
    bit is_write_to_ro;
    bit expect_error;
    bit refin;
    bit [7:0] b0, b1, b2, b3;
    bit [31:0] expected_val;

    forever begin
      mbx.get(tr);
      total_trans++;

      // Check protocol error conditions
      is_unaligned    = (tr.addr[1:0] != 2'b00);
      is_out_of_range = (tr.addr > 8'h1C);
      is_write_to_ro  = (tr.write && (tr.addr == 8'h04 || tr.addr == 8'h14));
      expect_error    = is_unaligned || is_out_of_range || is_write_to_ro;

      if (expect_error) begin
        error_resp_count++;
        if (tr.error) begin
          match_count++;
          $display("[SCOREBOARD PASS] Expected error response PSLVERR=1 correctly asserted for ADDR=0x%02X (write=%0d)",
                   tr.addr, tr.write);
        end else begin
          mismatch_count++;
          $error("[SCOREBOARD MISMATCH] Expected PSLVERR=1 for ADDR=0x%02X but received PSLVERR=0!",
                 tr.addr);
        end
        continue;
      end

      // Process Valid Transfer
      if (tr.write) begin
        write_count++;
        case (tr.addr)
          8'h00: begin // CRC_CTRL
            model_ctrl = tr.data;
            if (tr.data[1]) begin // RESET_ACC
              model_accum = model_init;
              model_ready = 1'b0;
            end
          end

          8'h08: model_poly    = tr.data; // CRC_POLY
          8'h0C: model_init    = tr.data; // CRC_INIT

          8'h10: begin // CRC_DATA_IN -> Compute CRC
            model_data_in = tr.data;
            model_ready   = 1'b1;
            model_int_stat[0] = 1'b1; // Done flag

            // Apply byte stream calculation
            refin = model_ctrl[2];
            b0 = refin ? ref_byte(tr.data[7:0])   : tr.data[7:0];
            b1 = refin ? ref_byte(tr.data[15:8])  : tr.data[15:8];
            b2 = refin ? ref_byte(tr.data[23:16]) : tr.data[23:16];
            b3 = refin ? ref_byte(tr.data[31:24]) : tr.data[31:24];

            case (model_ctrl[6:5]) // data_size
              2'b00: begin // 8-bit
                if (tr.strb[0]) model_accum = step_crc8_model(model_accum, b0, model_poly);
              end
              2'b01: begin // 16-bit
                if (tr.strb[0]) model_accum = step_crc8_model(model_accum, b0, model_poly);
                if (tr.strb[1]) model_accum = step_crc8_model(model_accum, b1, model_poly);
              end
              default: begin // 32-bit
                if (tr.strb[0]) model_accum = step_crc8_model(model_accum, b0, model_poly);
                if (tr.strb[1]) model_accum = step_crc8_model(model_accum, b1, model_poly);
                if (tr.strb[2]) model_accum = step_crc8_model(model_accum, b2, model_poly);
                if (tr.strb[3]) model_accum = step_crc8_model(model_accum, b3, model_poly);
              end
            endcase
          end

          8'h18: model_int_en = tr.data; // CRC_INT_EN

          8'h1C: begin // CRC_INT_STAT (W1C)
            if (tr.data[0]) model_int_stat[0] = 1'b0;
            if (tr.data[1]) model_int_stat[1] = 1'b0;
          end
          default: ;
        endcase
      end else begin // READ TRANSFER
        read_count++;

        case (tr.addr)
          8'h00: expected_val = model_ctrl;
          8'h04: expected_val = {24'h0, 4'h0, 1'b0, model_int_stat[1], model_ready, 1'b0};
          8'h08: expected_val = model_poly;
          8'h0C: expected_val = model_init;
          8'h10: expected_val = model_data_in;
          8'h14: expected_val = get_expected_crc();
          8'h18: expected_val = model_int_en;
          8'h1C: expected_val = model_int_stat;
          default: expected_val = 32'hDEADBEEF;
        endcase

        // Status register bits check (mask out internal FSM state nibble)
        if (tr.addr == 8'h04) begin
          if ((tr.rdata & 32'h0000000F) == (expected_val & 32'h0000000F)) begin
            match_count++;
            $display("[SCOREBOARD PASS] READ ADDR=0x%02X (STATUS) DATA=0x%08X (Flags matched)",
                     tr.addr, tr.rdata);
          end else begin
            mismatch_count++;
            $error("[SCOREBOARD MISMATCH] READ ADDR=0x%02X (STATUS) Expected=0x%08X Actual=0x%08X",
                   tr.addr, expected_val, tr.rdata);
          end
        end else if (tr.addr == 8'h14) begin // CRC RESULT CHECK
          if (tr.rdata == expected_val) begin
            match_count++;
            $display("[SCOREBOARD PASS] *** CRC RESULT MATCH *** ADDR=0x14 Computed CRC=0x%08X (Expected=0x%08X)",
                     tr.rdata, expected_val);
          end else begin
            mismatch_count++;
            $error("[SCOREBOARD MISMATCH] *** CRC RESULT MISMATCH *** ADDR=0x14 Expected=0x%08X Actual=0x%08X",
                   expected_val, tr.rdata);
          end
        end else begin // Standard register check
          if (tr.rdata == expected_val) begin
            match_count++;
            $display("[SCOREBOARD PASS] READ ADDR=0x%02X DATA=0x%08X (Match)",
                     tr.addr, tr.rdata);
          end else begin
            mismatch_count++;
            $error("[SCOREBOARD MISMATCH] READ ADDR=0x%02X Expected=0x%08X Actual=0x%08X",
                   tr.addr, expected_val, tr.rdata);
          end
        end
      end
    end
  endtask

  function void print_summary();
    $display("==================================================================");
    $display("                   VERIFICATION SCOREBOARD REPORT                 ");
    $display("==================================================================");
    $display(" Total Transactions Checked : %0d", total_trans);
    $display(" Total Write Transfers      : %0d", write_count);
    $display(" Total Read Transfers       : %0d", read_count);
    $display(" Protocol Errors Injected   : %0d", error_resp_count);
    $display(" Data & Protocol Matches    : %0d", match_count);
    $display(" Data Mismatches / Errors   : %0d", mismatch_count);
    if (mismatch_count == 0 && total_trans > 0) begin
      $display(" STATUS: >>> TESTBENCH PASSED (100%% MATCH) <<<");
    end else begin
      $display(" STATUS: >>> TESTBENCH FAILED (%0d MISMATCHES) <<<", mismatch_count);
    end
    $display("==================================================================");
  endfunction

endclass: apb_scoreboard
