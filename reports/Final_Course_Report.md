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

## Document Layout Structure (Exact 10-Page Format)

- **Page 1 (Right / Recto)**: Official Cover Page (Emblem, Course EC23E34, CEG Anna University, October 2026).
- **Page 2 (Left / Verso)**: Intentionally blank.
- **Page 3 (Right / Recto)**: Intentionally blank.
- **Page 4 (Left / Verso)**: **1. ALGORITHM FOR DESIGN CODE** (Point-wise 1 to 10 sequential algorithm).
- **Page 5 (Right / Recto)**: **1. AIM** and **2. BLOCK DIAGRAM** (Aim statement, microarchitecture diagram, brief narrative, register map table).
- **Page 6 (Left / Verso)**: **2. ALGORITHM FOR TESTBENCH CODE** (Point-wise 1 to 10 verification algorithm).
- **Page 7 (Right / Recto)**: **3. DESIGN CODE** (Synthesizable RTL top module and LFSR step function).
- **Page 8 (Left / Verso)**: **3. RESULT / WAVEFORM** (EDA Playground EPWave waveform image + brief cycle-by-cycle timing paragraph).
- **Page 9 (Right / Recto)**: **4. TEST BENCH CODE** (Virtual interface, master BFM driver tasks, directed test sequence).
- **Page 10 (Left / Verso)**: **3. RESULT / WAVEFORM** (Scoreboard terminal execution log + brief verification summary and conclusion paragraph).

---

## RIGHT SIDE SECTIONS

### 1. AIM
To design, implement, and verify an AMBA APB-compliant Configurable CRC-32 Hardware Accelerator Subsystem in synthesizable SystemVerilog RTL, and build a self-checking constrained-random SystemVerilog verification environment validating functional accuracy across standard IEEE 802.3 and Castagnoli polynomials, zero/wait-state bus transfers, and protocol error responses with 100% functional and code coverage on EDA Playground (Aldec Riviera-PRO / Synopsys VCS).

### 2. BLOCK DIAGRAM
![Hardware Subsystem Microarchitecture](../docs/images/microarchitecture_block_diagram.png)

The hardware accelerator subsystem consists of three main architectural blocks: the AMBA APB3 Slave Interface for synchronous bus communication and wait-state generation, the Memory-Mapped Register File providing software access to configuration registers, and the Parallel CRC-32 Engine executing single-cycle Galois Field LFSR calculations.

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
Complete synthesizable SystemVerilog RTL integrating the top module ([`rtl/apb_crc32_top.sv`](file:///home/pradeep/System%20verilog%20project/miniproject/rtl/apb_crc32_top.sv)) and parallel step function ([`rtl/crc32_engine.sv`](file:///home/pradeep/System%20verilog%20project/miniproject/rtl/crc32_engine.sv)).

### 4. TEST BENCH CODE
SystemVerilog verification suite comprising the synchronous interface ([`tb/apb_interface.sv`](file:///home/pradeep/System%20verilog%20project/miniproject/tb/apb_interface.sv)), master driver tasks, and directed verification tests ([`edaplayground/testbench.sv`](file:///home/pradeep/System%20verilog%20project/miniproject/edaplayground/testbench.sv)).

---

## LEFT SIDE SECTIONS

### 1. ALGORITHM FOR DESIGN CODE
1. Initialize all internal registers upon active-low reset (`PRESETn = 0`) to default configurations: Control register to 32-bit streaming mode (`0x00000001`), Polynomial to IEEE 802.3 (`0x04C11DB7`), Seed to `0xFFFFFFFF`, and Status register to ready (`0x00000002`).
2. Sample all APB bus input signals synchronously at each rising edge of the 100 MHz clock (`PCLK`).
3. In the IDLE state, continuously monitor bus select (`PSEL`). When `PSEL` is high and enable (`PENABLE`) is low, detect the start of a transfer and transition to the SETUP phase.
4. In the SETUP phase, latch the transfer address (`PADDR`), direction (`PWRITE`), write data (`PWDATA`), and byte strobes (`PSTRB`), transitioning unconditionally to the ACCESS phase on the next clock edge.
5. In the ACCESS phase, assert `PENABLE = 1` and decode the register address: update configuration parameters for `CRC_CTRL` (`0x00`), program polynomial for `CRC_POLY` (`0x08`), load seed for `CRC_INIT` (`0x0C`), trigger computation for `CRC_DATA_IN` (`0x10`), drive computed checksum for `CRC_RESULT` (`0x14`), or assert `PSLVERR = 1` for any unmapped address.
6. If wait states are configured ($W > 0$), deassert `PREADY = 0` and decrement the internal wait counter until zero, then assert `PREADY = 1` to conclude the bus transfer.
7. For incoming data words, optionally reverse the bit order within each active byte if input reflection (`REFIN`) is enabled.
8. Calculate the 32-bit CRC combinatorially in a single clock cycle by cascading four 8-bit Galois Field LFSR XOR reduction steps (< 3.8 ns propagation delay).
9. Optionally reverse the resulting 32-bit vector if output reflection (`REFOUT`) is enabled, and invert bits via bitwise XOR with `0xFFFFFFFF` if `XOROUT` is enabled.
10. Latch the final computed checksum into `RESULT_REG`, set the ready status flag high, and assert an interrupt pulse (`IRQ`) if enabled.

### 2. ALGORITHM FOR TESTBENCH CODE
1. Instantiate a 100 MHz differential clock generator (`PCLK`, 10 ns period) and assert active-low synchronous reset (`PRESETn`) for 3 clock periods (30 ns).
2. Instantiate the synchronous APB virtual interface and bind physical bus signals between the testbench components and the DUT (`apb_crc32_top`).
3. Initialize the golden software reference model computing standard IEEE 802.3 and Castagnoli CRC-32 polynomials.
4. In the Master BFM driver, implement the write procedure by asserting `PSEL = 1` with address and data in the Setup phase, asserting `PENABLE = 1` in the Access phase, waiting for `PREADY = 1`, and sampling `PSLVERR`.
5. In the Master BFM driver, implement the read procedure by driving the address with `PWRITE = 0`, waiting for `PREADY = 1`, and latching read data from `PRDATA`.
6. Continuously sample bus activity with a passive monitor on rising clock edges when `PSEL`, `PENABLE`, and `PREADY` are all high, capturing address, direction, data, and response signals into transaction objects.
7. In the self-checking scoreboard, pass written data to the golden reference algorithm to compute the expected CRC-32 value, and compare it against the actual value read back from the result register.
8. Automatically increment the match counter on exact data matches, or log a detailed failure message with timestamps and expected vs. actual values on any mismatch.
9. Sample functional covergroups across all 8 register address bins, byte-enable permutations, polynomial selections, and wait-state durations ($0$ to $7$ cycles).
10. Verify that 100% functional coverage is achieved and zero mismatches are detected before issuing `$finish`.

### 3. RESULT / WAVEFORM (PAGE 8)
![EDA Playground EPWave Waveform](../docs/images/edaplayground_waveform_real.png)

The simulation was executed on EDA Playground using Aldec Riviera-PRO and Synopsys VCS simulators with a 100 MHz clock. As shown in the simulation waveform above, the APB slave initializes to default states during reset (0 to 30 ns), accepts register configuration writes in standard two-cycle transfers with zero wait states (30 to 120 ns), and calculates the 32-bit CRC in a single clock cycle when input data `0x34333231` is written (120 to 210 ns). A subsequent read transfer to the result register (210 to 250 ns) successfully retrieves the golden IEEE 802.3 checksum (`0xCBF43926`). Furthermore, the waveform demonstrates correct wait-state stalling when `PREADY` is deasserted for 2 extra cycles (280 to 360 ns), as well as immediate bus error termination via `PSLVERR` when accessing an unmapped address (450 to 480 ns).

### 3. RESULT / WAVEFORM (PAGE 10)
![Scoreboard Terminal Results](../docs/images/simulation_scoreboard_results.png)

The self-checking verification scoreboard executed 63 directed and constrained-random test scenarios covering power-on reset defaults, IEEE 802.3 standard vectors (ASCII "123456789" yielding `0xCBF43926`), Castagnoli CRC-32C polynomials (`0x1EDC6F41` yielding `0xE3069283`), custom initial seed values, bit reflection modes, programmable wait states, and protocol error responses. All 63 verification checks passed with 0 mismatches, achieving 100% functional and code coverage across all registers and transfer modes, confirming that the hardware accelerator subsystem is robust, fully compliant with the AMBA APB standard, and ready for integration.
