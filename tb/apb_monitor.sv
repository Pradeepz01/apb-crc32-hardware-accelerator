// ============================================================================
// File: apb_monitor.sv
// Project: APB-Compliant Configurable CRC-32 Hardware Accelerator
// Author: Pradeep (Team 7: Bhuvanesh S, Aathithya K, Pradeep)
// Description: Passive APB bus monitor sampling valid transfers on
//              (PSEL && PENABLE && PREADY) and forwarding to Scoreboard & Coverage.
// ============================================================================

`timescale 1ns / 1ps

class apb_monitor;

  virtual apb_interface vif;
  mailbox #(apb_transaction) mbx_scb;
  mailbox #(apb_transaction) mbx_cov;
  int sample_count;

  function new(virtual apb_interface vif, 
               mailbox #(apb_transaction) mbx_scb,
               mailbox #(apb_transaction) mbx_cov = null);
    this.vif          = vif;
    this.mbx_scb      = mbx_scb;
    this.mbx_cov      = mbx_cov;
    this.sample_count = 0;
  endfunction

  task run();
    apb_transaction tr;

    while (!vif.presetn) @(posedge vif.pclk);
    @(posedge vif.pclk);

    forever begin
      @(posedge vif.pclk);
      #1ns;
      // Capture transfer when slave asserts PREADY during ACCESS phase
      if (vif.psel && vif.penable && vif.pready) begin
        tr       = new();
        tr.addr  = vif.paddr;
        tr.write = vif.pwrite;
        tr.strb  = vif.pstrb;
        tr.data  = vif.pwdata;
        tr.rdata = vif.prdata;
        tr.error = vif.pslverr;
        tr.irq   = vif.irq;

        sample_count++;

        // Send clone to scoreboard
        if (mbx_scb != null) begin
          mbx_scb.put(tr.clone());
        end

        // Send clone to coverage
        if (mbx_cov != null) begin
          mbx_cov.put(tr.clone());
        end
      end
    end
  endtask

endclass: apb_monitor
