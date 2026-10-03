// ============================================================================
// File: apb_crc32_top.sv
// Project: APB-Compliant Configurable CRC-32 Hardware Accelerator
// Author: Pradeep (Team 7: Bhuvanesh S, Aathithya K, Pradeep)
// Description: Top-level synthesizable module integrating APB slave FSM,
//              memory-mapped register file, and parallel CRC-32 accelerator engine.
// ============================================================================

`timescale 1ns / 1ps

/* verilator lint_off IMPORTSTAR */
import apb_crc32_pkg::*;

module apb_crc32_top (
  input  logic        pclk,
  input  logic        presetn,

  // AMBA APB Slave Interface
  input  logic [7:0]  paddr,
  input  logic        psel,
  input  logic        penable,
  input  logic        pwrite,
  input  logic [31:0] pwdata,
  input  logic [3:0]  pstrb,
  output logic [31:0] prdata,
  output logic        pready,
  output logic        pslverr,

  // Interrupt Request
  output logic        irq
);

  // Internal Wires between FSM and Regfile
  logic [7:0]  reg_addr;
  logic [31:0] reg_wdata;
  logic [3:0]  reg_strb;
  logic        reg_write;
  logic        reg_read;
  logic [31:0] reg_rdata;
  logic        reg_error;
  logic [3:0]  wait_states;
  logic [1:0]  apb_fsm_state;

  // Internal Wires between Regfile and Engine
  logic [31:0] poly;
  logic [31:0] init_val;
  logic        refin;
  logic        refout;
  logic        xorout_en;
  logic        reset_accum;
  logic        engine_valid;
  logic [3:0]  engine_byte_en;
  logic [31:0] engine_data;
  logic [31:0] crc_result;
  logic        engine_busy;
  logic        engine_done;

  // 1. APB Slave Protocol State Machine
  apb_slave_fsm u_apb_slave_fsm (
    .pclk            (pclk),
    .presetn         (presetn),
    .paddr           (paddr),
    .psel            (psel),
    .penable         (penable),
    .pwrite          (pwrite),
    .pwdata          (pwdata),
    .pstrb           (pstrb),
    .prdata          (prdata),
    .pready          (pready),
    .pslverr         (pslverr),
    .reg_addr_o      (reg_addr),
    .reg_wdata_o     (reg_wdata),
    .reg_strb_o      (reg_strb),
    .reg_write_o     (reg_write),
    .reg_read_o      (reg_read),
    .reg_rdata_i     (reg_rdata),
    .reg_error_i     (reg_error),
    .wait_states_i   (wait_states),
    .current_state_o (apb_fsm_state)
  );

  // 2. Memory-Mapped Register File
  apb_crc32_regfile u_apb_crc32_regfile (
    .clk              (pclk),
    .rst_n            (presetn),
    .reg_addr_i       (reg_addr),
    .reg_wdata_i      (reg_wdata),
    .reg_strb_i       (reg_strb),
    .reg_write_i      (reg_write),
    .reg_read_i       (reg_read),
    .reg_rdata_o      (reg_rdata),
    .reg_error_o      (reg_error),
    .wait_states_o    (wait_states),
    .poly_o           (poly),
    .init_val_o       (init_val),
    .refin_o          (refin),
    .refout_o         (refout),
    .xorout_en_o      (xorout_en),
    .reset_accum_o    (reset_accum),
    .engine_valid_o   (engine_valid),
    .engine_byte_en_o (engine_byte_en),
    .engine_data_o    (engine_data),
    .crc_result_i     (crc_result),
    .engine_busy_i    (engine_busy),
    .engine_done_i    (engine_done),
    .apb_fsm_state_i  (apb_fsm_state),
    .irq_o            (irq)
  );

  // 3. Parallel CRC-32 Computation Engine
  crc32_engine u_crc32_engine (
    .clk             (pclk),
    .rst_n           (presetn),
    .poly_i          (poly),
    .init_val_i      (init_val),
    .refin_i         (refin),
    .refout_i        (refout),
    .xorout_en_i     (xorout_en),
    .reset_accum_i   (reset_accum),
    .data_valid_i    (engine_valid),
    .byte_en_i       (engine_byte_en),
    .data_in_i       (engine_data),
    .crc_result_o    (crc_result),
    .busy_o          (engine_busy),
    .done_o          (engine_done)
  );

endmodule
