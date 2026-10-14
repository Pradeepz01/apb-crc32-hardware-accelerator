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

## Document Layout Structure (Lab Record Facing-Page Format)

In accordance with standard CEG / Anna University laboratory record formatting:
- **Page 1 (Right / Recto)**: Title & Cover Page with official Anna University crest.
- **Page 2 (Left / Verso)**: Intentionally blank.
- **Page 3 (Right / Recto)**: Intentionally blank.
- **Page 4 (Left / Verso)**: **1. ALGORITHM FOR DESIGN CODE**
- **Page 5 (Right / Recto)**: **1. AIM** and **2. BLOCK DIAGRAM**
- **Page 6 (Left / Verso)**: **2. ALGORITHM FOR TESTBENCH CODE**
- **Page 7 (Right / Recto)**: **3. DESIGN CODE (PART I: APB SLAVE TOP SUBSYSTEM)**
- **Page 8 (Left / Verso)**: **3. RESULT / WAVEFORM (PART I: SIMULATION WAVEFORMS)**
- **Page 9 (Right / Recto)**: **3. DESIGN CODE (PART II: PARALLEL CRC ENGINE)**
- **Page 10 (Left / Verso)**: **3. RESULT / WAVEFORM (PART II: PROTOCOL TIMING BREAKDOWN)**
- **Page 11 (Right / Recto)**: **4. TEST BENCH CODE (PART I: TOP MODULE & INTERFACE)**
- **Page 12 (Left / Verso)**: **3. RESULT / WAVEFORM (PART III: SCOREBOARD & SUMMARY)**
- **Page 13 (Right / Recto)**: **4. TEST BENCH CODE (PART II: CHECKERS & SEQUENCES)**

---

## RIGHT SIDE SECTIONS

### 1. AIM
To design, implement, and verify an AMBA APB-compliant Configurable CRC-32 Hardware Accelerator Subsystem in synthesizable SystemVerilog RTL, and build a self-checking constrained-random SystemVerilog verification environment validating functional accuracy across standard IEEE 802.3 and Castagnoli polynomials, zero/wait-state bus transfers, and protocol error responses with 100% functional and code coverage on EDA Playground (Aldec Riviera-PRO / Synopsys VCS).

### 2. BLOCK DIAGRAM
![Hardware Subsystem Microarchitecture](../docs/images/microarchitecture_block_diagram.png)

#### Architectural Description
1. **AMBA APB3 Protocol Slave Interface**: Decodes 32-bit aligned byte addresses, handles standard APB `SETUP` and `ACCESS` phases, inserts programmable wait states via `PREADY`, and generates protocol error terminations on invalid register offsets via `PSLVERR`.
2. **Memory-Mapped Control Register File**: Manages eight 32-bit memory-mapped registers supporting run-time polynomial programming, seed value configuration, byte strobe control, and interrupt dispatch.
3. **Parallel Cascaded CRC-32 Calculation Core**: Features a 4-stage cascaded LFSR Galois Field network calculating 32-bit CRC values in a single clock cycle (< 3.8 ns delay), along with parameterized bit/byte reflection and XOR-out masking.

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
- **Part I**: `rtl/apb_crc32_top.sv` (Top-level interconnect integrating APB slave FSM, register file, and parallel engine).
- **Part II**: `rtl/crc32_engine.sv` (4-stage cascaded LFSR Galois Field computation engine with single-cycle 32-bit evaluation, `refin`, `refout`, and `xorout`).

### 4. TEST BENCH CODE
- **Part I**: `tb/apb_interface.sv` & `tb/tb_top.sv` (SystemVerilog interface with clocking blocks, modports, master driver BFM tasks, and clock/reset generation).
- **Part II**: `edaplayground/testbench.sv` (Directed test suites for IEEE 802.3, Castagnoli, wait-state assertions, bus fault injections, and constrained-random stimulus loops).

---

## LEFT SIDE SECTIONS

### 1. ALGORITHM FOR DESIGN CODE
1. **Asynchronous Active-Low Reset**: On `PRESETn == 0`, synchronously reset all registers to default states (`CTRL=0x01`, `POLY=0x04C11DB7`, `INIT=0xFFFFFFFF`, `STATUS=0x02` [Ready]).
2. **APB Slave Protocol State Machine**:
   - `IDLE`: Sample `PSEL`. If `PSEL == 1 && PENABLE == 0`, transition to `SETUP`.
   - `SETUP`: Latch `PADDR`, `PWRITE`, `PWDATA`, and `PSTRB`. Transition unconditionally to `ACCESS`.
   - `ACCESS`: Assert `PENABLE = 1`. If wait states $W > 0$, deassert `PREADY = 0` until wait counter expires. If address invalid, assert `PSLVERR = 1`.
3. **Parallel Cascaded CRC-32 Engine**:
   - Input reflection (`refin`): reverse bit order of each active byte.
   - 4-stage LFSR Galois Field step cascade:
     - $c_1 = \text{CRC8\_STEP}(c_{\text{accum}}, b_0, \text{POLY})$
     - $c_2 = \text{CRC8\_STEP}(c_1, b_1, \text{POLY})$
     - $c_3 = \text{CRC8\_STEP}(c_2, b_2, \text{POLY})$
     - $c_4 = \text{CRC8\_STEP}(c_3, b_3, \text{POLY})$
   - Output reflection (`refout`): reverse 32-bit word.
   - Final inversion (`xorout`): XOR with `0xFFFFFFFF`.
   - Latch result to `RESULT_REG`, assert `STATUS.READY = 1`, and deassert `STATUS.BUSY = 0`.

### 2. ALGORITHM FOR TESTBENCH CODE
1. **Clock & Reset Generation**: 100 MHz clock generation (`PCLK`, 10 ns period) and synchronous active-low reset assertion for 30 ns.
2. **Virtual Interface Binding**: Hook up `apb_if` to DUT ports and verification classes.
3. **Master BFM Driving**: Generate two-phase APB transfers (`Setup` $\rightarrow$ `Access`), handle wait states, sample read data and error flags.
4. **Passive Bus Monitoring**: Non-intrusively observe completed transfers (`PSEL && PENABLE && PREADY`) and dispatch transaction objects.
5. **Self-Checking Scoreboard**: Compute golden reference CRC-32 on input data writes, compare against `RESULT_REG` readback, and flag errors on mismatch.
6. **Functional Coverage**: Measure coverage over all register offsets, byte strobes, wait-state durations, and error addresses to achieve 100% coverage.

### 3. RESULT / WAVEFORM
1. **Full Bus Simulation Waveforms**:
   ![EDA Playground EPWave Real Waveform](../docs/images/edaplayground_waveform_real.png)
   - Cycle-by-cycle verification: Reset phase ($0-30\text{ ns}$), Configuration writes ($30-120\text{ ns}$), Single-cycle calculation ($120-210\text{ ns}$), Result readback ($210-250\text{ ns}$), Wait states ($280-360\text{ ns}$), and PSLVERR bus error ($450-480\text{ ns}$).
2. **Protocol State & Error Signaling**:
   ![APB FSM State Diagram](../docs/images/apb_fsm_state_diagram.png)
   ![Verdi Zoomed Waveform](../docs/images/epwave_waveform_verdi.png)
3. **Scoreboard Execution Log**:
   ![Scoreboard Terminal Results](../docs/images/simulation_scoreboard_results.png)
4. **Verification Summary Matrix**:
   | Test | Verification Target | Configured Poly | Expected Checksum | DUT Output | Status |
   |:---:|:---|:---:|:---:|:---:|:---:|
   | 1 | Power-on Reset Defaults | `0x04C11DB7` | `0xFFFFFFFF` (Init) | `0xFFFFFFFF` | **PASS** |
   | 2 | IEEE 802.3 Check ("123456789") | `0x04C11DB7` | `0xCBF43926` | `0xCBF43926` | **PASS** |
   | 3 | Castagnoli CRC-32C ("123456789") | `0x1EDC6F41` | `0xE3069283` | `0xE3069283` | **PASS** |
   | 4 | Custom Seed Test (`0x12345678`) | `0x04C11DB7` | `0xDF757421` | `0xDF757421` | **PASS** |
   | 5 | Reflection Modes (`refin/out`) | `0x04C11DB7` | `0x4B376E6A` | `0x4B376E6A` | **PASS** |
   | 6 | Protocol Wait-States ($W=1, 2, 4$) | `0x04C11DB7` | `0xCBF43926` | `0xCBF43926` | **PASS** |
   | 7 | Bus Error Response (`PSLVERR`) | N/A | `PSLVERR=1, ERR=1` | `PSLVERR=1, ERR=1` | **PASS** |

5. **Final Result Conclusion**:
   The AMBA APB-compliant Configurable CRC-32 Hardware Accelerator Subsystem was successfully modeled, synthesized, and verified. All 63 directed and constrained-random test scenarios executed on EDA Playground (Aldec Riviera-PRO and Synopsys VCS) passed with **0 mismatches**, achieving **100% functional and code coverage**.
