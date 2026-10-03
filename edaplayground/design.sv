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
