# Microarchitecture Specification: Configurable CRC-32 Accelerator Subsystem

**Module**: `apb_crc32_top`  
**Team 7**: Bhuvanesh S, Aathithya K, Pradeep  
**Architecture Version**: 1.0  
**Target Technologies**: Synopsys VCS, Yosys Generic Gates, OpenLane / SkyWater 130nm  

---

## 1. Top-Level Subsystem Architecture

The accelerator is organized into three decoupled hardware functional blocks:
1. **APB Slave Protocol Controller (`apb_slave_fsm`)**: Handles bus handshaking, state transitions, wait-state injection, and error response.
2. **Memory-Mapped Register File (`apb_crc32_regfile`)**: Contains all configuration, status, data buffers, and interrupt logic.
3. **High-Speed Parallel CRC-32 Engine (`crc32_engine`)**: Pure combinational parallel LFSR cascade core with bit-reflection logic and dynamic accumulator register.

![Microarchitecture Block Diagram](../docs/images/microarchitecture_block_diagram.png)

```
                           +-------------------------------------------------------+
                           |                   apb_crc32_top                       |
                           |                                                       |
  APB Bus Master           |   +--------------------+     +---------------------+  |
-------------------------> |   |                    |     |                     |  |
  - PCLK, PRESETn          |   |   apb_slave_fsm    |====>|  apb_crc32_regfile  |  |
  - PSEL, PENABLE          |   |                    |     |                     |  |
  - PWRITE, PADDR[7:0]     |   | - 3-State FSM      |     | - Config Registers  |  |
  - PWDATA[31:0]           |   | - Wait Generator   |     | - Address Decoder   |  |
  - PSTRB[3:0]             |   | - PSLVERR Logic    |     | - W1C Interrupts    |  |
<------------------------- |   +--------------------+     +---------------------+  |
  - PRDATA[31:0]           |                                       ||              |
  - PREADY, PSLVERR        |                                       || (Data/Poly/  |
  - IRQ                    |                                       \/  Control)    |
                           |                              +---------------------+  |
                           |                              |                     |  |
                           |                              |    crc32_engine     |  |
                           |                              |                     |  |
                           |                              | - 4-Byte Cascaded   |  |
                           |                              |   Combinational     |  |
                           |                              |   LFSR Network      |  |
                           |                              | - Bit Reversal      |  |
                           |                              | - CRC Accumulator   |  |
                           |                              +---------------------+  |
                           +-------------------------------------------------------+
```

---

## 2. Submodule Decomposition

### 2.1 APB Slave Protocol Controller (`apb_slave_fsm.sv`)
- **Role**: Mediates between high-level APB master transfers and the synchronous internal register file.
- **States**:
  - `APB_ST_IDLE (2'b00)`: Default unselected state. Low power consumption.
  - `APB_ST_SETUP (2'b01)`: Entered when `PSEL = 1, PENABLE = 0`. Address and write data are decoded.
  - `APB_ST_ACCESS (2'b10)`: Entered when `PSEL = 1, PENABLE = 1`. Handshake commits when `PREADY = 1`.
- **Wait-State Counter**: A 4-bit synchronous counter (`wait_counter`) increments in `APB_ST_ACCESS` while `PREADY` is suppressed. When `wait_counter == wait_states_i`, `PREADY` asserts HIGH, concluding the transfer on the next clock edge.
- **Error Assertion**: Evaluates `pslverr = reg_error_i` strictly during the terminal cycle of the access phase.

### 2.2 Memory-Mapped Register File (`apb_crc32_regfile.sv`)
- **Address Decoder**: Fully combinational 8-bit comparator network verifying word alignment (`PADDR[1:0] == 2'b00`) and valid boundaries (`PADDR <= 0x1C`).
- **Storage Elements**:
  - `reg_ctrl`: 32-bit control register holding reflection switches, data size, and wait state configurations.
  - `reg_poly`: 32-bit register holding the active polynomial.
  - `reg_init`: 32-bit initial seed vector.
  - `reg_data_in`: 32-bit holding buffer for streamed operands.
  - `reg_int_en`: 2-bit mask register for Done and Error interrupts.
  - `reg_int_stat`: 2-bit interrupt status register implementing Write-1-to-Clear (W1C) toggle avoidance.
- **Zero-Latency Feedthrough**: Data writes to `CRC_DATA_IN` combinatorially trigger `engine_valid_o = 1` and forward `engine_data_o = reg_wdata_i` simultaneously, guaranteeing zero idle cycles between APB commit and CRC accumulator update.

### 2.3 Parallel CRC-32 Engine (`crc32_engine.sv`)
- **Parallel LFSR Architecture**:
  Rather than serial bit-by-bit shifting requiring 32 cycles per word, the engine processes up to 4 bytes (32 bits) in a **single clock cycle**.
- **Combinational Byte Cascading**:
  The calculation is factored into 4 cascaded Galois LFSR functions:
  ```
  Byte 0 (bits 7:0)   ---> [ CRC8_STEP ] ---> step0_crc
                                 ||
  Byte 1 (bits 15:8)  ---> [ CRC8_STEP ] ---> step1_crc
                                 ||
  Byte 2 (bits 23:16) ---> [ CRC8_STEP ] ---> step2_crc
                                 ||
  Byte 3 (bits 31:24) ---> [ CRC8_STEP ] ---> step3_crc ===> next_accum
  ```
- **Byte Enable Multiplexing**: If the host writes a single byte or halfword, unused stages are bypassed combinatorially (`stepN_crc = step(N-1)_crc`), maintaining the exact CRC intermediate state.
- **Bit Reflection (`REFIN` / `REFOUT`)**:
  - Input: Combinational byte bit-reversal ($D_{\text{in}}[i] \leftrightarrow D_{\text{in}}[7-i]$).
  - Output: Full 32-bit word reflection ($R[j] \leftrightarrow R[31-j]$).
- **XOR-Out Masking**: Bitwise XOR with `0xFFFFFFFF` enabled via `CRC_CTRL[4]`.

---

## 3. Dataflow & Timing Pipeline

```
Cycle 1 (T1)       Cycle 2 (T2)       Cycle 3 (T3)
------------------------------------------------------------
SETUP Phase        ACCESS Phase       COMMIT / IDLE
PSEL = 1           PENABLE = 1        PENABLE = 0
PWRITE = 1         PREADY = 1         psel = 0
PADDR = 0x10       engine_valid = 1   
PWDATA = Data      LFSR Combinational
                   Cascades 4 Bytes   crc_accum <= next_accum
                                      CRC_RESULT available
```

---

## 4. Synthesis & Gate Count Report (Yosys Open-Source Synthesis)

Synthesis targeted generic gate technology and SkyWater standard cells:
- **Total Logic Cells**: 3,255 gates
- **Flip-Flops**: 202 sequential storage registers
- **Multiplexers**: 1,425 cells (parallel LFSR feedback selection)
- **XOR Gates**: 1,063 cells (Galois polynomial feedback matrix)
- **Inferred Memory**: 0 (Fully distributed logic, 100% synthesizable)
- **Maximum Operating Frequency**: > 250 MHz on typical TSMC / Sky130 standard cell libraries.
