// ============================================================================
// File: apb_environment.sv
// Project: APB-Compliant Configurable CRC-32 Hardware Accelerator
// Author: Pradeep (Team 7: Bhuvanesh S, Aathithya K, Pradeep)
// Description: Verification environment container instantiating and connecting
//              Generator, Driver, Monitor, Scoreboard, and Coverage components.
// ============================================================================

`timescale 1ns / 1ps

class apb_environment;

  virtual apb_interface vif;

  // Communication channels
  mailbox #(apb_transaction) mbx_gen2drv;
  mailbox #(apb_transaction) mbx_mon2scb;
  mailbox #(apb_transaction) mbx_mon2cov;
  event gen_done;

  // Verification components
  apb_generator  gen;
  apb_driver     drv;
  apb_monitor    mon;
  apb_scoreboard scb;
  apb_coverage   cov;

  function new(virtual apb_interface vif);
    this.vif = vif;

    // Instantiate mailboxes
    mbx_gen2drv = new(1); // Bounded mailbox so generator synchronizes with driver
    mbx_mon2scb = new();
    mbx_mon2cov = new();

    // Instantiate components
    gen = new(mbx_gen2drv, gen_done);
    drv = new(vif, mbx_gen2drv);
    mon = new(vif, mbx_mon2scb, mbx_mon2cov);
    scb = new(mbx_mon2scb);
    cov = new(mbx_mon2cov);
  endfunction

  task run();
    fork
      drv.run();
      mon.run();
      scb.run();
      cov.run();
      gen.run();
    join_any

    // Wait until generator finishes
    @(gen_done);
    #200ns;

    // Report results
    scb.print_summary();
    cov.print_coverage();
  endtask

endclass: apb_environment
