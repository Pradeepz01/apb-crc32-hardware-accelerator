// ============================================================================
// File: apb_transaction.sv
// Project: APB-Compliant Configurable CRC-32 Hardware Accelerator
// Author: Pradeep (Team 7: Bhuvanesh S, Aathithya K, Pradeep)
// Description: SystemVerilog Transaction item representing an APB transfer
//              with randomization constraints and formatting methods.
// ============================================================================

`timescale 1ns / 1ps

class apb_transaction;

  // Stimulus fields (Randomized)
  rand bit [7:0]  addr;
  rand bit [31:0] data;
  rand bit        write; // 1 = Write, 0 = Read
  rand bit [3:0]  strb;
  rand int        delay; // Cycles before next transfer

  // Response fields (Collected from DUT)
  bit [31:0]      rdata;
  bit             error;
  bit             irq;

  // Constraints for compliant APB transfers
  constraint c_aligned_addr {
    addr[1:0] == 2'b00;
  }

  constraint c_valid_range {
    addr inside {8'h00, 8'h04, 8'h08, 8'h0C, 8'h10, 8'h14, 8'h18, 8'h1C};
  }

  constraint c_valid_strb {
    strb inside {4'b0001, 4'b0011, 4'b1111};
  }

  constraint c_delay_range {
    delay inside {[0:3]};
  }

  // Constructor
  function new(bit [7:0] a = 8'h00, bit [31:0] d = 32'h0, bit wr = 1'b0);
    this.addr  = a;
    this.data  = d;
    this.write = wr;
    this.strb  = 4'b1111;
    this.delay = 0;
  endfunction

  // Copy method
  function void copy(apb_transaction rhs);
    this.addr  = rhs.addr;
    this.data  = rhs.data;
    this.write = rhs.write;
    this.strb  = rhs.strb;
    this.rdata = rhs.rdata;
    this.error = rhs.error;
    this.irq   = rhs.irq;
    this.delay = rhs.delay;
  endfunction

  // Clone method
  function apb_transaction clone();
    apb_transaction tr = new();
    tr.copy(this);
    return tr;
  endfunction

  // String display
  function string convert2string();
    return $sformatf("[%s] ADDR=0x%02X DATA=0x%08X STRB=0x%X | RDATA=0x%08X ERR=%b IRQ=%b",
                     write ? "WRITE" : "READ ", addr, data, strb, rdata, error, irq);
  endfunction

endclass: apb_transaction
