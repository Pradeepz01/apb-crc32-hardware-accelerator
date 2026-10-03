// ============================================================================
// File: apb_generator.sv
// Project: APB-Compliant Configurable CRC-32 Hardware Accelerator
// Author: Pradeep (Team 7: Bhuvanesh S, Aathithya K, Pradeep)
// Description: Test sequence generator implementing Directed Tests, Standard
//              Verification Vectors (Ethernet/Castagnoli), Error Injection,
//              Wait-State Verification, and Constrained Random Sequences.
// ============================================================================

`timescale 1ns / 1ps

class apb_generator;

  mailbox #(apb_transaction) mbx;
  event gen_done;
  int trans_count;

  function new(mailbox #(apb_transaction) mbx, event gen_done);
    this.mbx         = mbx;
    this.gen_done    = gen_done;
    this.trans_count = 0;
  endfunction

  // Helper task to send a single transfer
  task send_trans(bit [7:0] addr, bit [31:0] data, bit write, bit [3:0] strb = 4'hF, int delay = 0);
    apb_transaction tr = new(addr, data, write);
    tr.strb  = strb;
    tr.delay = delay;
    mbx.put(tr);
    trans_count++;
  endtask

  // Comprehensive Test Sequence
  task run();
    $display("\n>>> [GENERATOR] Starting APB CRC-32 Comprehensive Verification Suite <<<");

    // ========================================================================
    // TEST 1: Power-on Reset & Default Register Walk
    // ========================================================================
    $display("\n--- TEST 1: Register Readout & Default State Verification ---");
    send_trans(8'h00, 32'h0, 1'b0); // Read CTRL
    send_trans(8'h04, 32'h0, 1'b0); // Read STATUS
    send_trans(8'h08, 32'h0, 1'b0); // Read POLY
    send_trans(8'h0C, 32'h0, 1'b0); // Read INIT
    send_trans(8'h14, 32'h0, 1'b0); // Read RESULT
    send_trans(8'h18, 32'h0, 1'b0); // Read INT_EN
    send_trans(8'h1C, 32'h0, 1'b0); // Read INT_STAT

    // ========================================================================
    // TEST 2: Standard IEEE 802.3 Ethernet CRC-32 Vector ("123456789")
    // Golden Result: 0xCBF43926
    // ========================================================================
    $display("\n--- TEST 2: IEEE 802.3 Standard Vector (ASCII '123456789') ---");
    // 1. Reset Accumulator via CTRL[1]
    send_trans(8'h00, 32'h0000005E, 1'b1); // Write CTRL (REFIN=1, REFOUT=1, XOROUT=1, RESET_ACC=1)
    send_trans(8'h00, 32'h0000005C, 1'b1); // Restore CTRL

    // 2. Stream word 0: '1234' = 0x34333231 in little-endian
    send_trans(8'h10, 32'h34333231, 1'b1, 4'hF);

    // 3. Stream word 1: '5678' = 0x38373635 in little-endian
    send_trans(8'h10, 32'h38373635, 1'b1, 4'hF);

    // 4. Stream byte 2: '9' = 0x00000039 with strb=4'b0001
    // Configure data_size to byte mode
    send_trans(8'h00, 32'h0000001C, 1'b1); // data_size = 2'b00 (Byte)
    send_trans(8'h10, 32'h00000039, 1'b1, 4'h1);

    // 5. Read computed result (Must match 0xCBF43926)
    send_trans(8'h14, 32'h0, 1'b0);

    // ========================================================================
    // TEST 3: CRC-32C Castagnoli Polynomial (0x1EDC6F41)
    // ========================================================================
    $display("\n--- TEST 3: Castagnoli CRC-32C Polynomial Verification ---");
    send_trans(8'h08, 32'h1EDC6F41, 1'b1); // Program Castagnoli Poly
    send_trans(8'h08, 32'h0,        1'b0); // Verify readback
    send_trans(8'h00, 32'h0000005E, 1'b1); // Reset accumulator
    send_trans(8'h00, 32'h0000005C, 1'b1); // 32-bit word mode
    send_trans(8'h10, 32'hA5A5A5A5, 1'b1, 4'hF); // Stream test pattern
    send_trans(8'h14, 32'h0,        1'b0); // Read result

    // Restore IEEE Poly
    send_trans(8'h08, 32'h04C11DB7, 1'b1);

    // ========================================================================
    // TEST 4: Configurable APB Wait-State Injection (PREADY verification)
    // ========================================================================
    $display("\n--- TEST 4: Wait-State Injection (PREADY = 0 for 3 cycles) ---");
    // Set WAIT_STATES = 3 in CTRL[11:8]
    send_trans(8'h00, 32'h0000035C, 1'b1); 
    send_trans(8'h10, 32'h11223344, 1'b1); // Write with wait states
    send_trans(8'h14, 32'h0,        1'b0); // Read with wait states
    send_trans(8'h00, 32'h0000005C, 1'b1); // Clear wait states

    // ========================================================================
    // TEST 5: Interrupt Generation and Write-1-to-Clear (W1C)
    // ========================================================================
    $display("\n--- TEST 5: Interrupt Enable & W1C Clearing Verification ---");
    send_trans(8'h18, 32'h00000003, 1'b1); // Enable DONE and ERR interrupts
    send_trans(8'h10, 32'hDEADCAFE, 1'b1); // Trigger calculation
    send_trans(8'h1C, 32'h0,        1'b0); // Check INT_STAT[0] == 1
    send_trans(8'h1C, 32'h00000001, 1'b1); // Clear bit 0 via W1C
    send_trans(8'h1C, 32'h0,        1'b0); // Verify bit 0 is cleared to 0

    // ========================================================================
    // TEST 6: PSLVERR Protocol & Access Error Injection
    // ========================================================================
    $display("\n--- TEST 6: Error Injection (Unaligned, Out-of-bounds, Write to RO) ---");
    send_trans(8'h02, 32'h0, 1'b0); // Unaligned address -> PSLVERR expected
    send_trans(8'h24, 32'h0, 1'b0); // Out of bounds address -> PSLVERR expected
    send_trans(8'h04, 32'hFFFFFFFF, 1'b1); // Write to RO STATUS -> PSLVERR expected
    send_trans(8'h14, 32'hFFFFFFFF, 1'b1); // Write to RO RESULT -> PSLVERR expected

    // ========================================================================
    // TEST 7: Back-to-Back Burst Transfers (Stress Testing)
    // ========================================================================
    $display("\n--- TEST 7: Back-to-Back Burst Transfers (Zero Delay) ---");
    for (int i = 0; i < 8; i++) begin
      send_trans(8'h10, 32'h10000000 + i, 1'b1, 4'hF, 0); // No inter-transfer delay
    end
    send_trans(8'h14, 32'h0, 1'b0);

    // ========================================================================
    // TEST 8: Constrained Random Transfers
    // ========================================================================
    $display("\n--- TEST 8: Constrained Random Transfers ---");
    for (int i = 0; i < 30; i++) begin
      apb_transaction rand_tr = new();
      if (!rand_tr.randomize()) begin
        $error("[GENERATOR ERROR] Randomization failed!");
      end else begin
        // Prevent writing to RO registers in random mode
        if (rand_tr.write && (rand_tr.addr == 8'h04 || rand_tr.addr == 8'h14)) begin
          rand_tr.write = 1'b0;
        end
        mbx.put(rand_tr);
        trans_count++;
      end
    end

    #100ns;
    -> gen_done;
    $display(">>> [GENERATOR] Stimulus generation completed (%0d total transfers) <<<\n", trans_count);
  endtask

endclass: apb_generator
