// ============================================================================
// File: apb_interface.sv
// Project: APB-Compliant Configurable CRC-32 Hardware Accelerator
// Author: Pradeep (Team 7: Bhuvanesh S, Aathithya K, Pradeep)
// Description: SystemVerilog Interface for AMBA APB bus with clocking blocks,
//              modports, and SystemVerilog Assertions (SVA) for protocol compliance.
// ============================================================================

`timescale 1ns / 1ps

interface apb_interface (input logic pclk, input logic presetn);

  logic [7:0]  paddr   = 8'h00;
  logic        psel    = 1'b0;
  logic        penable = 1'b0;
  logic        pwrite  = 1'b0;
  logic [31:0] pwdata  = 32'h0;
  logic [3:0]  pstrb   = 4'b0000;
  logic [31:0] prdata;
  logic        pready;
  logic        pslverr;
  logic        irq;

`if !defined(VERILATOR) && !defined(__ICARUS__)
  // Master Clocking Block for Driver (VCS / Verdi / Questa)
  clocking master_cb @(posedge pclk);
    default input #1ns output #1ns;
    output paddr;
    output psel;
    output penable;
    output pwrite;
    output pwdata;
    output pstrb;
    input  prdata;
    input  pready;
    input  pslverr;
    input  irq;
  endclocking

  // Monitor Clocking Block for Passive Bus Sampling (VCS / Verdi / Questa)
  clocking monitor_cb @(posedge pclk);
    default input #1ns;
    input paddr;
    input psel;
    input penable;
    input pwrite;
    input pwdata;
    input pstrb;
    input prdata;
    input pready;
    input pslverr;
    input irq;
  endclocking

  // Modports
  modport master_mp  (
    output paddr, psel, penable, pwrite, pwdata, pstrb,
    input  prdata, pready, pslverr, irq, pclk, presetn
  );
  modport monitor_mp (
    input  paddr, psel, penable, pwrite, pwdata, pstrb,
           prdata, pready, pslverr, irq, pclk, presetn
  );
  modport slave_mp   (
    input  pclk, presetn, paddr, psel, penable, pwrite, pwdata, pstrb,
    output prdata, pready, pslverr, irq
  );

  // --------------------------------------------------------------------------
  // SystemVerilog Assertions (SVA) for APB Protocol Compliance (VCS / Verdi)
  // --------------------------------------------------------------------------

  // Property 1: PENABLE must be asserted exactly 1 cycle after PSEL (Setup -> Access)
  property p_penable_after_psel;
    @(posedge pclk) disable iff (!presetn)
    (psel && !penable) |=> penable;
  endproperty
  assert_penable_after_psel: assert property (p_penable_after_psel)
    else $error("[SVA ERROR] PENABLE was not asserted 1 cycle after PSEL!");

  // Property 2: PADDR must remain stable during wait states (while PREADY is low)
  property p_paddr_stable_during_wait;
    @(posedge pclk) disable iff (!presetn)
    (psel && penable && !pready) |=> $stable(paddr);
  endproperty
  assert_paddr_stable_during_wait: assert property (p_paddr_stable_during_wait)
    else $error("[SVA ERROR] PADDR changed during wait states (PREADY == 0)!");

  // Property 3: PWDATA must remain stable during write wait states
  property p_pwdata_stable_during_wait;
    @(posedge pclk) disable iff (!presetn)
    (psel && penable && pwrite && !pready) |=> $stable(pwdata);
  endproperty
  assert_pwdata_stable_during_wait: assert property (p_pwdata_stable_during_wait)
    else $error("[SVA ERROR] PWDATA changed during write wait states (PREADY == 0)!");

  // Property 4: PWRITE must remain stable during wait states
  property p_pwrite_stable_during_wait;
    @(posedge pclk) disable iff (!presetn)
    (psel && penable && !pready) |=> $stable(pwrite);
  endproperty
  assert_pwrite_stable_during_wait: assert property (p_pwrite_stable_during_wait)
    else $error("[SVA ERROR] PWRITE changed during wait states (PREADY == 0)!");

  // Property 5: PSLVERR must only be asserted when PSEL, PENABLE, and PREADY are high
  property p_pslverr_only_when_ready;
    @(posedge pclk) disable iff (!presetn)
    pslverr |-> (psel && penable && pready);
  endproperty
  assert_pslverr_only_when_ready: assert property (p_pslverr_only_when_ready)
    else $error("[SVA ERROR] PSLVERR asserted outside of valid ready transfer cycle!");
`endif

endinterface: apb_interface
