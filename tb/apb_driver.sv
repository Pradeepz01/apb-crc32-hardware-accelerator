// ============================================================================
// File: apb_driver.sv
// Project: APB-Compliant Configurable CRC-32 Hardware Accelerator
// Author: Pradeep (Team 7: Bhuvanesh S, Aathithya K, Pradeep)
// Description: APB Master BFM Driver receiving transactions from the generator
//              and driving protocol timing onto the APB interface.
// ============================================================================

`timescale 1ns / 1ps

class apb_driver;

  virtual apb_interface vif;
  mailbox #(apb_transaction) mbx;
  int trans_count;

  function new(virtual apb_interface vif, mailbox #(apb_transaction) mbx);
    this.vif         = vif;
    this.mbx         = mbx;
    this.trans_count = 0;
  endfunction

  // Reset driver pins
  task reset_signals();
    vif.paddr   = 8'h00;
    vif.psel    = 1'b0;
    vif.penable = 1'b0;
    vif.pwrite  = 1'b0;
    vif.pwdata  = 32'h0;
    vif.pstrb   = 4'b0000;
  endtask

  // Main driver execution task
  task run();
    apb_transaction tr;
    reset_signals();

    // Wait for reset to be deasserted
    while (!vif.presetn) @(posedge vif.pclk);
    @(posedge vif.pclk);

    forever begin
      mbx.get(tr);
      trans_count++;

      // Inter-transfer idle delay
      if (tr.delay > 0) begin
        repeat (tr.delay) @(posedge vif.pclk);
      end

      // 1. SETUP Phase: Drive address, control, write-data, assert PSEL
      @(posedge vif.pclk);
      #1ns;
      vif.psel    = 1'b1;
      vif.penable = 1'b0;
      vif.paddr   = tr.addr;
      vif.pwrite  = tr.write;
      vif.pwdata  = tr.data;
      vif.pstrb   = tr.strb;

      // 2. ACCESS Phase: Assert PENABLE on next clock edge
      @(posedge vif.pclk);
      #1ns;
      vif.penable = 1'b1;

      // Wait for PREADY handshake from slave
      while (!vif.pready) begin
        @(posedge vif.pclk);
        #1ns;
      end

      // Sample response
      tr.error = vif.pslverr;
      if (!tr.write) begin
        tr.rdata = vif.prdata;
      end
      tr.irq = vif.irq;

      // 3. Return bus to IDLE
      @(posedge vif.pclk);
      #1ns;
      vif.psel    = 1'b0;
      vif.penable = 1'b0;
      vif.pwrite  = 1'b0;
    end
  endtask

endclass: apb_driver
