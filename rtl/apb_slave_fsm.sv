// ============================================================================
// File: apb_slave_fsm.sv
// Project: APB-Compliant Configurable CRC-32 Hardware Accelerator
// Author: Pradeep (Team 7: Bhuvanesh S, Aathithya K, Pradeep)
// Description: AMBA APB3/APB4 compliant slave state machine with configurable
//              wait-state injection (PREADY) and error response (PSLVERR).
// ============================================================================

`timescale 1ns / 1ps

/* verilator lint_off IMPORTSTAR */
import apb_crc32_pkg::*;

module apb_slave_fsm (
  input  logic        pclk,
  input  logic        presetn,

  // APB Slave Bus Signals
  input  logic [7:0]  paddr,
  input  logic        psel,
  input  logic        penable,
  input  logic        pwrite,
  input  logic [31:0] pwdata,
  input  logic [3:0]  pstrb,
  output logic [31:0] prdata,
  output logic        pready,
  output logic        pslverr,

  // Register File Interface
  output logic [7:0]  reg_addr_o,
  output logic [31:0] reg_wdata_o,
  output logic [3:0]  reg_strb_o,
  output logic        reg_write_o,
  output logic        reg_read_o,
  input  logic [31:0] reg_rdata_i,
  input  logic        reg_error_i,
  input  logic [3:0]  wait_states_i,
  output logic [1:0]  current_state_o
);

  logic [1:0] state, next_state;
  logic [3:0] wait_counter;

  assign current_state_o = state;

  // FSM State Transition
  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      state        <= APB_ST_IDLE;
      wait_counter <= 4'h0;
    end else begin
      state <= next_state;

      // Wait-state counter logic
      if (state == APB_ST_ACCESS && !pready) begin
        wait_counter <= wait_counter + 1'b1;
      end else begin
        wait_counter <= 4'h0;
      end
    end
  end

  // Next State Logic
  always_comb begin
    next_state = state;
    case (state)
      APB_ST_IDLE: begin
        if (psel && !penable) begin
          next_state = APB_ST_SETUP;
        end
      end

      APB_ST_SETUP: begin
        if (psel && penable) begin
          next_state = APB_ST_ACCESS;
        end else if (!psel) begin
          next_state = APB_ST_IDLE;
        end
      end

      APB_ST_ACCESS: begin
        if (pready) begin
          if (psel && !penable) begin
            next_state = APB_ST_SETUP; // Back-to-back transfer
          end else begin
            next_state = APB_ST_IDLE;
          end
        end
      end

      default: next_state = APB_ST_IDLE;
    endcase
  end

  // PREADY generation based on configured wait states
  always_comb begin
    if (psel && penable) begin
      if (wait_counter >= wait_states_i) begin
        pready = 1'b1;
      end else begin
        pready = 1'b0;
      end
    end else begin
      pready = 1'b1; // Default ready in non-access
    end
  end

  // PSLVERR is asserted only at the completion cycle of an ACCESS transfer
  always_comb begin
    if (psel && penable && pready) begin
      pslverr = reg_error_i;
    end else begin
      pslverr = 1'b0;
    end
  end

  // Register File control signals
  assign reg_addr_o  = paddr;
  assign reg_wdata_o = pwdata;
  assign reg_strb_o  = (pstrb == 4'b0000) ? 4'b1111 : pstrb; // Default all active if unset
  assign reg_write_o = psel && penable && pready && pwrite;
  assign reg_read_o  = psel && penable && pready && !pwrite;

  // Read data output
  assign prdata = (psel && penable && !pwrite) ? reg_rdata_i : 32'h0;

endmodule
