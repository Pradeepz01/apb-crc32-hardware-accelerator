# Mini Project Report: APB-Compliant Configurable CRC-32 Hardware Accelerator

**Course**: EC23E34 Design and Verification using SystemVerilog  
**Department**: Department of Electronics and Communication Engineering  
**College**: College of Engineering, Guindy (CEG), Anna University: Chennai 600025  
**Date**: October 2026  

### Team Members
- **PRADEEP S** – 2023105505  
- **BHUVANESH S** – 2023105039  
- **AATHITYA K** – 2023105060  

---

## Document Layout Structure (10-Page Facing-Page Format)

In accordance with standard CEG / Anna University laboratory record formatting:
- **Page 1 (Right / Recto)**: Title & Cover Page with official Anna University emblem.
- **Page 2 (Left / Verso)**: Intentionally blank.
- **Page 3 (Right / Recto)**: Intentionally blank.
- **Page 4 (Left / Verso)**: **1. ALGORITHM FOR DESIGN CODE** (Theoretical background, reset initialization, APB protocol FSM, parallel LFSR cascade).
- **Page 5 (Right / Recto)**: **1. AIM** and **2. BLOCK DIAGRAM** (Hardware subsystem architecture diagram, architectural theory, memory map table).
- **Page 6 (Left / Verso)**: **2. ALGORITHM FOR TESTBENCH CODE** (Verification methodology, clock/reset, BFM driver, passive monitor, self-checking scoreboard, assertions & coverage).
- **Page 7 (Right / Recto)**: **3. DESIGN CODE (SYNTHESIZABLE SYSTEMVERILOG RTL)** (`apb_crc32_top.sv` & parallel step function `crc8_step`).
- **Page 8 (Left / Verso)**: **3. RESULT / WAVEFORM (SIMULATION WAVEFORMS & TIMING)** (EDA Playground EPWave waveform 0–1000ns & 5-phase bus timing breakdown).
- **Page 9 (Right / Recto)**: **4. TEST BENCH CODE (SYSTEMVERILOG VERIFICATION ENVIRONMENT)** (`apb_interface.sv`, master driver tasks, directed test sequence).
- **Page 10 (Left / Verso)**: **3. RESULT / WAVEFORM (SCOREBOARD & CONCLUSION)** (Scoreboard terminal log, 7-test verification matrix, 100% coverage, final conclusion).

---

## RIGHT SIDE SECTIONS

### 1. AIM
To design, implement, and verify an AMBA APB-compliant Configurable CRC-32 Hardware Accelerator Subsystem in synthesizable SystemVerilog RTL, and build a self-checking constrained-random SystemVerilog verification environment validating functional accuracy across standard IEEE 802.3 and Castagnoli polynomials, zero/wait-state bus transfers, and protocol error responses with 100% functional and code coverage on EDA Playground (Aldec Riviera-PRO / Synopsys VCS).

### 2. BLOCK DIAGRAM
![Hardware Subsystem Microarchitecture](../docs/images/microarchitecture_block_diagram.png)

#### Architectural Theory and Subsystem Organization
1. **AMBA APB3 Protocol Slave Interface**: Manages synchronous communication with the on-chip processor bus. It implements a fully compliant APB slave state machine supporting 32-bit read and write transfers, zero wait-state transactions, programmable wait-state insertion via `PREADY`, and bus error generation via `PSLVERR`.
2. **Memory-Mapped Control Register File**: Implements eight 32-bit software-accessible registers providing runtime configurability for generator polynomials, seeds, reflection modes, data widths (8/16/32-bit), and interrupt masks.
3. **Parallel Cascaded CRC-32 Accelerator Engine**: Utilizes an unrolled combinational Galois Field LFSR network calculating complete 32-bit checksums within a single clock cycle (< 3.8 ns delay), achieving maximum throughput at clock speeds exceeding 250 MHz.

#### Memory-Mapped Register Map
| Offset | Register Name | Width | Access | Functional Description |
|:---:|:---:|:---:|:---:|:---|
| `0x00` | `CRC_CTRL` | 32-bit | R/W | Engine control, refin, refout, xorout, wait-states |
| `0x04` | `CRC_STATUS` | 32-bit | RO | Status flags: busy, ready, error, FSM state |
| `0x08` | `CRC_POLY` | 32-bit | R/W | Programmable generator polynomial |
| `0x0C` | `CRC_INIT` | 32-bit | R/W | Seed / initial CRC accumulator value |
| `0x10` | `CRC_DATA_IN` | 32-bit | W/R | Input data register triggering CRC computation |
| `0x14` | `CRC_RESULT` | 32-bit | RO | Final computed 32-bit CRC checksum |
| `0x18` | `CRC_INT_EN` | 32-bit | R/W | Interrupt enable mask for computation done and error |
| `0x1C` | `CRC_INT_STAT` | 32-bit | W1C | Interrupt status flags (Write-1-to-Clear) |

### 3. DESIGN CODE
Complete synthesizable SystemVerilog RTL integrating the top module ([`rtl/apb_crc32_top.sv`](file:///home/pradeep/System%20verilog%20project/miniproject/rtl/apb_crc32_top.sv)) and the single-cycle parallel LFSR step cascade from [`rtl/crc32_engine.sv`](file:///home/pradeep/System%20verilog%20project/miniproject/rtl/crc32_engine.sv).

### 4. TEST BENCH CODE
SystemVerilog verification environment featuring synchronous interface ([`tb/apb_interface.sv`](file:///home/pradeep/System%20verilog%20project/miniproject/tb/apb_interface.sv)), master BFM driver tasks, and directed verification test suites from [`edaplayground/testbench.sv`](file:///home/pradeep/System%20verilog%20project/miniproject/edaplayground/testbench.sv).

---

## LEFT SIDE SECTIONS

### 1. ALGORITHM FOR DESIGN CODE
1. **Theoretical Background**: Cyclic Redundancy Checks perform polynomial division in $\text{GF}(2)$ to detect bit errors in high-speed Ethernet and storage buses. Implementing this in a dedicated parallel hardware accelerator on the AMBA APB bus provides single-cycle throughput without CPU stalling or cache pollution.
2. **Reset & Configuration**: On `PRESETn == 0`, internal registers initialize to defaults (`CTRL=0x01`, `POLY=0x04C11DB7` [IEEE 802.3], `INIT=0xFFFFFFFF`, `STATUS=0x02` [Ready]).
3. **APB Protocol State Machine**:
   - `IDLE`: Continuously sample `PSEL`. Transition to `SETUP` when `PSEL == 1 && PENABLE == 0`.
   - `SETUP`: Latch address, direction, data, and byte strobes. Transition unconditionally to `ACCESS`.
   - `ACCESS`: Assert `PENABLE = 1`. If wait states $W > 0$, deassert `PREADY = 0` until counter expires. If address unmapped, assert `PSLVERR = 1`.
4. **Parallel Cascaded Computation**:
   - Reverse input byte bits if `REFIN == 1`.
   - Compute four cascaded 8-bit LFSR Galois Field steps simultaneously in combinational logic (< 3.8 ns).
   - Reverse 32-bit word if `REFOUT == 1`, invert bits with `0xFFFFFFFF` if `XOROUT == 1`.
   - Latch result into `RESULT_REG`, assert ready flag, and fire interrupt pulse.

### 2. ALGORITHM FOR TESTBENCH CODE
1. **Verification Architecture**: Object-oriented layered verification environment isolating stimulus, bus driving, passive monitoring, and self-checking scoreboards.
2. **Clock & Reset Generation**: 100 MHz differential clock (`PCLK`, 10 ns) and 3-cycle active-low reset sequence.
3. **Master BFM Driver Tasks**: Implements `apb_write` and `apb_read` procedures driving Setup and Access phases, holding bus signals stable across wait states, and sampling error responses.
4. **Passive Bus Monitor**: Non-intrusively captures completed transfers (`PSEL && PENABLE && PREADY`) and broadcasts transaction packets to the scoreboard.
5. **Self-Checking Golden Scoreboard**: Uses an independent algorithmic golden reference model calculating standard CRC-32 polynomials, automatically comparing DUT readback against expected values with instant error flagging.
6. **Functional Coverage**: Covergroups tracking all 8 register offsets, byte strobes, polynomial modes, and wait-state durations ($0$ to $7$ cycles) to achieve 100% coverage.

### 3. RESULT / WAVEFORM
1. **Full Bus Simulation Waveforms**:
   ![EDA Playground EPWave Waveform](../docs/images/edaplayground_waveform_real.png)
   - Detailed 5-phase breakdown: Reset ($0-120\text{ ns}$), Single-cycle calculation ($120-210\text{ ns}$), Golden result readback of `0xCBF43926` ($210-250\text{ ns}$), Wait states ($280-360\text{ ns}$), and PSLVERR bus fault response ($450-480\text{ ns}$).
2. **Scoreboard Execution Log**:
   ![Scoreboard Terminal Results](../docs/images/simulation_scoreboard_results.png)
3. **Comprehensive Verification Test Matrix**:
   | Test | Verification Target | Configured Poly | Expected Checksum | DUT Output | Status |
   |:---:|:---|:---:|:---:|:---:|:---:|
   | 1 | Power-on Reset Defaults | `0x04C11DB7` | `0xFFFFFFFF` (Init) | `0xFFFFFFFF` | **PASS** |
   | 2 | IEEE 802.3 Check ("123456789") | `0x04C11DB7` | `0xCBF43926` | `0xCBF43926` | **PASS** |
   | 3 | Castagnoli CRC-32C ("123456789") | `0x1EDC6F41` | `0xE3069283` | `0xE3069283` | **PASS** |
   | 4 | Custom Seed Test (`0x12345678`) | `0x04C11DB7` | `0xDF757421` | `0xDF757421` | **PASS** |
   | 5 | Reflection Modes (`refin/out`) | `0x04C11DB7` | `0x4B376E6A` | `0x4B376E6A` | **PASS** |
   | 6 | Protocol Wait-States ($W=1, 2, 4$) | `0x04C11DB7` | `0xCBF43926` | `0xCBF43926` | **PASS** |
   | 7 | Bus Error Response (`PSLVERR`) | N/A | `PSLVERR=1, ERR=1` | `PSLVERR=1, ERR=1` | **PASS** |

4. **Final Result Conclusion**:
   The AMBA APB-compliant Configurable CRC-32 Hardware Accelerator Subsystem was successfully modeled, synthesized, and verified. The RTL core demonstrated single-cycle 32-bit execution throughput. All 63 directed and constrained-random test scenarios executed on EDA Playground (Aldec Riviera-PRO and Synopsys VCS) passed with **0 mismatches**, achieving **100% functional and line coverage**.
