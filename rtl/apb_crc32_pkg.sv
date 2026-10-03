// ============================================================================
// File: apb_crc32_pkg.sv
// Project: APB-Compliant Configurable CRC-32 Hardware Accelerator
// Author: Pradeep (Team 7: Bhuvanesh S, Aathithya K, Pradeep)
// Description: Package defining register offsets, bitfields, default values,
//              and FSM types for the APB CRC-32 peripheral.
// ============================================================================

`timescale 1ns / 1ps

/* verilator lint_off UNUSEDPARAM */
package apb_crc32_pkg;

  // Address Map (32-bit aligned byte offsets)
  localparam bit [7:0] ADDR_CRC_CTRL     = 8'h00; // Control Register (R/W)
  localparam bit [7:0] ADDR_CRC_STATUS   = 8'h04; // Status Register (RO)
  localparam bit [7:0] ADDR_CRC_POLY     = 8'h08; // Polynomial Register (R/W)
  localparam bit [7:0] ADDR_CRC_INIT     = 8'h0C; // Initial Seed Register (R/W)
  localparam bit [7:0] ADDR_CRC_DATA_IN  = 8'h10; // Data Input Register (W/R)
  localparam bit [7:0] ADDR_CRC_RESULT   = 8'h14; // Computed CRC Result Register (RO)
  localparam bit [7:0] ADDR_CRC_INT_EN   = 8'h18; // Interrupt Enable Register (R/W)
  localparam bit [7:0] ADDR_CRC_INT_STAT = 8'h1C; // Interrupt Status & Clear (W1C)
  localparam bit [7:0] ADDR_MAX          = 8'h1C;

  // Default Standard Polynomials
  localparam bit [31:0] POLY_IEEE_802_3  = 32'h04C11DB7; // Ethernet, ZIP, PNG, POSIX
  localparam bit [31:0] POLY_CASTAGNOLI  = 32'h1EDC6F41; // iSCSI, SCTP, Btrfs (CRC-32C)
  localparam bit [31:0] POLY_KOOPMAN     = 32'h741B8CD7; // CRC-32K
  localparam bit [31:0] DEFAULT_INIT     = 32'hFFFFFFFF;
  localparam bit [31:0] DEFAULT_XOROUT   = 32'hFFFFFFFF;

  // Control Register Bit Field Positions
  localparam int CTRL_START_BIT       = 0;
  localparam int CTRL_RESET_ACC_BIT   = 1;
  localparam int CTRL_REFIN_BIT       = 2;
  localparam int CTRL_REFOUT_BIT      = 3;
  localparam int CTRL_XOROUT_EN_BIT   = 4;
  localparam int CTRL_DATA_SIZE_LSB   = 5;
  localparam int CTRL_DATA_SIZE_MSB   = 6;
  localparam int CTRL_AUTO_PRESET_BIT = 7;
  localparam int CTRL_WAIT_STATES_LSB = 8;
  localparam int CTRL_WAIT_STATES_MSB = 11;

  // Data Size Encoding
  localparam bit [1:0] DATA_SIZE_BYTE     = 2'b00; // 8-bit stream
  localparam bit [1:0] DATA_SIZE_HALFWORD = 2'b01; // 16-bit stream
  localparam bit [1:0] DATA_SIZE_WORD     = 2'b10; // 32-bit stream

  // Status Register Bit Field Positions
  localparam int STAT_BUSY_BIT        = 0;
  localparam int STAT_READY_BIT       = 1;
  localparam int STAT_ERR_BIT         = 2;
  localparam int STAT_FSM_LSB         = 4;
  localparam int STAT_FSM_MSB         = 7;

  // Interrupt Register Bits
  localparam int INT_DONE_BIT         = 0;
  localparam int INT_ERR_BIT          = 1;

  // APB Slave Protocol FSM States
  localparam bit [1:0] APB_ST_IDLE   = 2'b00;
  localparam bit [1:0] APB_ST_SETUP  = 2'b01;
  localparam bit [1:0] APB_ST_ACCESS = 2'b10;

  // Function to reflect/reverse an 8-bit byte (LSB <-> MSB)
  function [7:0] reflect_byte;
    input [7:0] in_b;
    integer i;
    begin
      for (i = 0; i < 8; i = i + 1) begin
        reflect_byte[i] = in_b[7 - i];
      end
    end
  endfunction

  // Function to reflect/reverse a 32-bit word
  function [31:0] reflect_word;
    input [31:0] in_w;
    integer j;
    begin
      for (j = 0; j < 32; j = j + 1) begin
        reflect_word[j] = in_w[31 - j];
      end
    end
  endfunction

endpackage
