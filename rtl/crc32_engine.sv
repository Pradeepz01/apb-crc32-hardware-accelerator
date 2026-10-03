// ============================================================================
// File: crc32_engine.sv
// Project: APB-Compliant Configurable CRC-32 Hardware Accelerator
// Author: Pradeep (Team 7: Bhuvanesh S, Aathithya K, Pradeep)
// Description: Parallel CRC-32 Hardware Accelerator core.
//              Supports programmable polynomial, 8/16/32-bit streaming,
//              configurable bit-reflection (refin/refout), and XOR-out.
// ============================================================================

`timescale 1ns / 1ps

/* verilator lint_off IMPORTSTAR */
import apb_crc32_pkg::*;

module crc32_engine (
  input  logic        clk,
  input  logic        rst_n,

  // Configuration
  input  logic [31:0] poly_i,
  input  logic [31:0] init_val_i,
  input  logic        refin_i,
  input  logic        refout_i,
  input  logic        xorout_en_i,

  // Control & Data Interface
  input  logic        reset_accum_i,
  input  logic        data_valid_i,
  input  logic [3:0]  byte_en_i,
  input  logic [31:0] data_in_i,

  // Status & Outputs
  output logic [31:0] crc_result_o,
  output logic        busy_o,
  output logic        done_o
);

  logic [31:0] crc_accum;

  // Single-byte CRC-32 LFSR computation step
  function [31:0] crc8_step;
    input [31:0] current_crc;
    input [7:0]  byte_val;
    input [31:0] poly;
    reg   [31:0] c;
    integer i;
    begin
      c = current_crc ^ {byte_val, 24'h0};
      for (i = 0; i < 8; i = i + 1) begin
        if (c[31]) begin
          c = {c[30:0], 1'b0} ^ poly;
        end else begin
          c = {c[30:0], 1'b0};
        end
      end
      crc8_step = c;
    end
  endfunction

  // Function to reflect an 8-bit byte
  function [7:0] reflect_byte;
    input [7:0] in_b;
    integer i;
    begin
      for (i = 0; i < 8; i = i + 1) begin
        reflect_byte[i] = in_b[7 - i];
      end
    end
  endfunction

  // Function to reflect a 32-bit word
  function [31:0] reflect_word;
    input [31:0] in_w;
    integer j;
    begin
      for (j = 0; j < 32; j = j + 1) begin
        reflect_word[j] = in_w[31 - j];
      end
    end
  endfunction

  // Combinatorial next accumulator calculation
  logic [31:0] next_accum;
  logic [31:0] step0_crc, step1_crc, step2_crc, step3_crc;
  logic [7:0]  b0, b1, b2, b3;

  always_comb begin
    // Prepare input bytes with optional bit reflection (refin)
    b0 = refin_i ? reflect_byte(data_in_i[7:0])   : data_in_i[7:0];
    b1 = refin_i ? reflect_byte(data_in_i[15:8])  : data_in_i[15:8];
    b2 = refin_i ? reflect_byte(data_in_i[23:16]) : data_in_i[23:16];
    b3 = refin_i ? reflect_byte(data_in_i[31:24]) : data_in_i[31:24];

    // Cascade through each active byte in little-endian byte order
    step0_crc = byte_en_i[0] ? crc8_step(crc_accum, b0, poly_i) : crc_accum;
    step1_crc = byte_en_i[1] ? crc8_step(step0_crc, b1, poly_i) : step0_crc;
    step2_crc = byte_en_i[2] ? crc8_step(step1_crc, b2, poly_i) : step1_crc;
    step3_crc = byte_en_i[3] ? crc8_step(step2_crc, b3, poly_i) : step2_crc;

    next_accum = step3_crc;
  end

  // Sequential Accumulator Register Update
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      crc_accum <= DEFAULT_INIT;
      busy_o    <= 1'b0;
      done_o    <= 1'b0;
    end else begin
      done_o <= 1'b0; // Default pulse
      if (reset_accum_i) begin
        crc_accum <= init_val_i;
        busy_o    <= 1'b0;
      end else if (data_valid_i) begin
        crc_accum <= next_accum;
        busy_o    <= 1'b0;
        done_o    <= 1'b1;
      end else begin
        busy_o    <= 1'b0;
      end
    end
  end

  // Output formatting: optional bit reflection (refout) and XORout
  logic [31:0] reflected_crc;
  assign reflected_crc = refout_i ? reflect_word(crc_accum) : crc_accum;
  assign crc_result_o  = reflected_crc ^ (xorout_en_i ? DEFAULT_XOROUT : 32'h00000000);

endmodule
