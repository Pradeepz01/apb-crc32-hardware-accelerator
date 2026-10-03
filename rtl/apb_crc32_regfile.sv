// ============================================================================
// File: apb_crc32_regfile.sv
// Project: APB-Compliant Configurable CRC-32 Hardware Accelerator
// Author: Pradeep (Team 7: Bhuvanesh S, Aathithya K, Pradeep)
// Description: Register file with memory-mapped APB interface, RW/RO/W1C
//              registers, error detection, interrupt generation, and
//              wait-state configuration.
// ============================================================================

`timescale 1ns / 1ps

/* verilator lint_off IMPORTSTAR */
import apb_crc32_pkg::*;

module apb_crc32_regfile (
  input  logic        clk,
  input  logic        rst_n,

  // Internal register access interface from APB Slave FSM
  input  logic [7:0]  reg_addr_i,
  input  logic [31:0] reg_wdata_i,
  input  logic [3:0]  reg_strb_i,
  input  logic        reg_write_i,
  input  logic        reg_read_i,
  output logic [31:0] reg_rdata_o,
  output logic        reg_error_o,
  output logic [3:0]  wait_states_o,

  // Interface to CRC-32 Engine
  output logic [31:0] poly_o,
  output logic [31:0] init_val_o,
  output logic        refin_o,
  output logic        refout_o,
  output logic        xorout_en_o,
  output logic        reset_accum_o,
  output logic        engine_valid_o,
  output logic [3:0]  engine_byte_en_o,
  output logic [31:0] engine_data_o,

  input  logic [31:0] crc_result_i,
  input  logic        engine_busy_i,
  input  logic        engine_done_i,
  input  logic [1:0]  apb_fsm_state_i,

  // Interrupt pin
  output logic        irq_o
);

  // Register definitions with defaults
  // CTRL default: REFIN=1, REFOUT=1, XOROUT_EN=1, DATA_SIZE=32-bit (10), WAIT_STATES=0
  // Value: 0x0000005C (bits: refin[2]=1, refout[3]=1, xorout[4]=1, data_size[6:5]=2'b10)
  logic [31:0] reg_ctrl;
  logic [31:0] reg_status;
  logic [31:0] reg_poly;
  logic [31:0] reg_init;
  logic [31:0] reg_data_in;
  logic [31:0] reg_int_en;
  logic [31:0] reg_int_stat;

  logic ready_flag;
  logic access_error;

  // Signal extraction from CTRL register
  assign refin_o        = reg_ctrl[CTRL_REFIN_BIT];
  assign refout_o       = reg_ctrl[CTRL_REFOUT_BIT];
  assign xorout_en_o    = reg_ctrl[CTRL_XOROUT_EN_BIT];
  assign wait_states_o  = reg_ctrl[CTRL_WAIT_STATES_MSB:CTRL_WAIT_STATES_LSB];
  assign poly_o         = reg_poly;
  assign init_val_o     = (reg_write_i && (reg_addr_i == ADDR_CRC_INIT) && !access_error) ? reg_wdata_i : reg_init;

  // Combinational Engine Control Signals
  assign engine_valid_o = reg_write_i && (reg_addr_i == ADDR_CRC_DATA_IN) && !access_error;
  assign engine_data_o  = reg_wdata_i;
  assign reset_accum_o  = ((reg_write_i && (reg_addr_i == ADDR_CRC_CTRL) && reg_strb_i[0] && reg_wdata_i[CTRL_RESET_ACC_BIT]) ||
                           (reg_write_i && (reg_addr_i == ADDR_CRC_INIT))) && !access_error;

  always_comb begin
    case (reg_ctrl[CTRL_DATA_SIZE_MSB:CTRL_DATA_SIZE_LSB])
      DATA_SIZE_BYTE:     engine_byte_en_o = (reg_strb_i == 4'b1111) ? 4'b0001 : reg_strb_i;
      DATA_SIZE_HALFWORD: engine_byte_en_o = (reg_strb_i == 4'b1111) ? 4'b0011 : reg_strb_i;
      default:            engine_byte_en_o = reg_strb_i;
    endcase
  end

  // Interrupt generation
  assign irq_o = (reg_int_stat[INT_DONE_BIT] & reg_int_en[INT_DONE_BIT]) |
                 (reg_int_stat[INT_ERR_BIT]  & reg_int_en[INT_ERR_BIT]);

  // Status Register composition (Read-Only)
  assign reg_status = {
    24'h0,
    apb_fsm_state_i, 2'b00, // Bits 7:4 for FSM state observability
    1'b0,                   // Bit 3
    reg_int_stat[INT_ERR_BIT], // Bit 2: Error flag
    ready_flag,             // Bit 1: Ready flag
    engine_busy_i           // Bit 0: Busy flag
  };

  // Decode and Access Error Checking
  always_comb begin
    access_error = 1'b0;
    // Unaligned address (non-multiple of 4)
    if (reg_addr_i[1:0] != 2'b00) begin
      access_error = 1'b1;
    end
    // Out of bounds address
    else if (reg_addr_i > ADDR_MAX) begin
      access_error = 1'b1;
    end
    // Write to Read-Only registers (CRC_STATUS or CRC_RESULT)
    else if (reg_write_i && (reg_addr_i == ADDR_CRC_STATUS || reg_addr_i == ADDR_CRC_RESULT)) begin
      access_error = 1'b1;
    end
  end

  assign reg_error_o = access_error;

  // Read Data Multiplexing
  always_comb begin
    reg_rdata_o = 32'h0;
    case (reg_addr_i)
      ADDR_CRC_CTRL:     reg_rdata_o = reg_ctrl;
      ADDR_CRC_STATUS:   reg_rdata_o = reg_status;
      ADDR_CRC_POLY:     reg_rdata_o = reg_poly;
      ADDR_CRC_INIT:     reg_rdata_o = reg_init;
      ADDR_CRC_DATA_IN:  reg_rdata_o = reg_data_in;
      ADDR_CRC_RESULT:   reg_rdata_o = crc_result_i;
      ADDR_CRC_INT_EN:   reg_rdata_o = reg_int_en;
      ADDR_CRC_INT_STAT: reg_rdata_o = reg_int_stat;
      default:           reg_rdata_o = 32'hDEADBEEF; // Error pattern
    endcase
  end

  // Register Write Logic & State Updates
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reg_ctrl       <= 32'h0000005C; // Default: REFIN=1, REFOUT=1, XOROUT=1, DATA_SIZE=32-bit
      reg_poly       <= POLY_IEEE_802_3;
      reg_init       <= DEFAULT_INIT;
      reg_data_in    <= 32'h0;
      reg_int_en     <= 32'h0;
      reg_int_stat   <= 32'h0;
      ready_flag     <= 1'b0;
    end else begin
      reg_ctrl[CTRL_START_BIT]     <= 1'b0;
      reg_ctrl[CTRL_RESET_ACC_BIT] <= 1'b0;

      // Track engine completion
      if (engine_done_i) begin
        ready_flag <= 1'b1;
        reg_int_stat[INT_DONE_BIT] <= 1'b1; // Trigger done interrupt flag
      end

      // Clear ready flag on reset
      if (reset_accum_o) begin
        ready_flag <= 1'b0;
      end

      // Latch error interrupt flag
      if (access_error && (reg_read_i || reg_write_i)) begin
        reg_int_stat[INT_ERR_BIT] <= 1'b1;
      end

      // APB Write Transfers
      if (reg_write_i && !access_error) begin
        case (reg_addr_i)
          ADDR_CRC_CTRL: begin
            if (reg_strb_i[0]) reg_ctrl[7:0]   <= reg_wdata_i[7:0];
            if (reg_strb_i[1]) reg_ctrl[15:8]  <= reg_wdata_i[15:8];
            if (reg_strb_i[2]) reg_ctrl[23:16] <= reg_wdata_i[23:16];
            if (reg_strb_i[3]) reg_ctrl[31:24] <= reg_wdata_i[31:24];
          end

          ADDR_CRC_POLY: begin
            if (reg_strb_i[0]) reg_poly[7:0]   <= reg_wdata_i[7:0];
            if (reg_strb_i[1]) reg_poly[15:8]  <= reg_wdata_i[15:8];
            if (reg_strb_i[2]) reg_poly[23:16] <= reg_wdata_i[23:16];
            if (reg_strb_i[3]) reg_poly[31:24] <= reg_wdata_i[31:24];
          end

          ADDR_CRC_INIT: begin
            if (reg_strb_i[0]) reg_init[7:0]   <= reg_wdata_i[7:0];
            if (reg_strb_i[1]) reg_init[15:8]  <= reg_wdata_i[15:8];
            if (reg_strb_i[2]) reg_init[23:16] <= reg_wdata_i[23:16];
            if (reg_strb_i[3]) reg_init[31:24] <= reg_wdata_i[31:24];
          end

          ADDR_CRC_DATA_IN: begin
            reg_data_in <= reg_wdata_i;
          end

          ADDR_CRC_INT_EN: begin
            if (reg_strb_i[0]) reg_int_en[7:0]   <= reg_wdata_i[7:0];
            if (reg_strb_i[1]) reg_int_en[15:8]  <= reg_wdata_i[15:8];
            if (reg_strb_i[2]) reg_int_en[23:16] <= reg_wdata_i[23:16];
            if (reg_strb_i[3]) reg_int_en[31:24] <= reg_wdata_i[31:24];
          end

          ADDR_CRC_INT_STAT: begin
            // Write-1-to-Clear (W1C) behavior
            if (reg_strb_i[0]) begin
              if (reg_wdata_i[INT_DONE_BIT]) reg_int_stat[INT_DONE_BIT] <= 1'b0;
              if (reg_wdata_i[INT_ERR_BIT])  reg_int_stat[INT_ERR_BIT]  <= 1'b0;
            end
          end

          default: ; // Unhandled write
        endcase
      end
    end
  end

endmodule
