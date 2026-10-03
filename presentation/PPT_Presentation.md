# Presentation Deck: APB-Compliant Configurable CRC-32 Hardware Accelerator

**Course**: Advanced SystemVerilog Design & Verification  
**Project**: RTL Design and SystemVerilog Verification of an APB-Compliant Configurable CRC-32 Hardware Accelerator  
**Team 7**: Bhuvanesh S, Aathithya K, Pradeep  
**Presenter**: Pradeep  

---

## Slide 1: Title Slide
### Design and Verification of an APB-Compliant Configurable CRC-32 Hardware Accelerator Subsystem
- **Team Members**:
  - Pradeep (Lead RTL Design & Verification Engineer)
  - Bhuvanesh S (Architecture & Protocol Specification)
  - Aathithya K (Verification Environment & Coverage Analysis)
- **Course**: Advanced SystemVerilog Design & Verification
- **Date**: Fall 2026

*Speaker Notes:*
> "Good morning Professor and classmates. Today Team 7 is presenting the complete design and SystemVerilog verification of an AMBA APB-compliant configurable CRC-32 hardware accelerator. Our project offloads complex data integrity computations from the CPU into dedicated silicon."

---

## Slide 2: Motivation & Problem Statement
### Why Hardware Acceleration for CRC?
- **Software Bottleneck**:
  - Pure software CRC loops consume 8 to 20 clock cycles per byte.
  - Table-lookup implementations degrade CPU L1 cache performance.
- **Embedded SoC Demand**:
  - High-speed Ethernet frames, PCIe packets, automotive CAN-FD, and flash storage controllers require real-time line-rate validation.
- **Our Solution**:
  - A parallel combinational LFSR cascade processing 32 bits per cycle.
  - Directly memory-mapped on the AMBA Advanced Peripheral Bus (APB).
  - Peak throughput: 3.2 Gbps at 100 MHz clock frequency.

*Speaker Notes:*
> "In embedded systems, executing CRC in software wastes critical processor bandwidth. By implementing an APB peripheral that computes a 32-bit word in a single cycle, we achieve line-rate throughput without stalling the main processor."

---

## Slide 3: System Architecture & Block Diagram
### Modular 3-Tier Hardware Architecture

![Microarchitecture Block Diagram](../docs/images/microarchitecture_block_diagram.png)

```
                          apb_crc32_top
               +----------------------------------+
APB Master     |   apb_slave_fsm                  |
===========>   |   - AMBA APB3/APB4 Protocol      |
(PADDR, PSEL,  |   - Wait-State Injection         |
 PWRITE, etc.) |   - PSLVERR Error Generator      |
               +-----------------+----------------+
                                 |
                                 v
               +-----------------+----------------+
               |   apb_crc32_regfile              |
               |   - 8 Memory-Mapped Registers    |
               |   - W1C Interrupt Controller     |
               |   - Zero-Latency Feedthrough     |
               +-----------------+----------------+
                                 |
                                 v
               +-----------------+----------------+
               |   crc32_engine                   |
               |   - 4-Byte Combinational Cascade |
               |   - Configurable Polynomial      |
               |   - RefIn / RefOut / XOROut      |
               +----------------------------------+
```

*Speaker Notes:*
> "Our microarchitecture cleanly isolates protocol handling, register mapping, and algorithmic computation into three distinct modules: the APB Slave FSM, the Register File, and the Parallel CRC Engine."

---

## Slide 4: AMBA APB Slave FSM & Protocol Handshaking
### Rigorous APB3 / APB4 Protocol Compliance

![APB FSM State Diagram](../docs/images/apb_fsm_state_diagram.png)

- **3-State FSM**: `IDLE` $\rightarrow$ `SETUP` $\rightarrow$ `ACCESS`.
- **Dynamic Wait-State Injection (`PREADY`)**:
  - Programmable from 0 to 15 wait cycles via `CRC_CTRL[11:8]`.
  - Simulates slow memories or busy downstream interconnects.
- **Bus Error Trapping (`PSLVERR`)**:
  - Asserted during the terminal access phase for unaligned addresses, out-of-bounds offsets, or writes to read-only locations.
  - Returns `0xDEADBEEF` on read errors and suppresses invalid register writes.

*Speaker Notes:*
> "The APB state machine strictly adheres to the ARM specification. It supports back-to-back burst transfers, wait-state delays via PREADY, and active bus error signaling with PSLVERR."

---

## Slide 5: Memory-Mapped Register Space
### Clean 32-Bit Word-Aligned Architecture

| Address Offset | Register | Access | Reset Default | Description |
| :---: | :--- | :---: | :---: | :--- |
| `0x00` | `CRC_CTRL` | R/W | `0x0000005C` | Control, Data Size, Wait States |
| `0x04` | `CRC_STATUS`| RO | `0x00000080` | Busy, Ready, Err, FSM State |
| `0x08` | `CRC_POLY` | R/W | `0x04C11DB7` | Polynomial (Default: IEEE 802.3) |
| `0x0C` | `CRC_INIT` | R/W | `0xFFFFFFFF` | Seed Initialization Vector |
| `0x10` | `CRC_DATA_IN`| WO/RW | `0x00000000` | Stream Data Input Port |
| `0x14` | `CRC_RESULT`| RO | `0x00000000` | Computed 32-bit Checksum |
| `0x18` | `CRC_INT_EN` | R/W | `0x00000000` | Interrupt Mask Register |
| `0x1C` | `CRC_INT_STAT`| R/W1C| `0x00000000` | Done & Error Flags (Write-1-to-Clear)|

*Speaker Notes:*
> "Here is our 8-register memory map. A key design highlight is CRC_INT_STAT, which implements Write-1-to-Clear semantics to guarantee glitch-free interrupt handling."

---

## Slide 6: Parallel Galois Field LFSR Engine
### 1-Cycle 32-Bit Datapath
- **Combinational Byte Cascading**:
  - Byte 0 $\rightarrow$ `CRC8_STEP` $\rightarrow$ Byte 1 $\rightarrow$ `CRC8_STEP` $\rightarrow$ Byte 2 $\rightarrow$ Byte 3.
- **Variable Sizing Support**:
  - Can stream 8-bit bytes, 16-bit halfwords, or 32-bit words seamlessly.
  - Unused byte stages are dynamically bypassed via combinational multiplexers.
- **Bit-Reversal Flexibility**:
  - `REFIN`: Inverts bit order within each byte before LFSR ingestion.
  - `REFOUT`: Inverts bit order across the final 32-bit accumulator.
  - `XOROUT`: Selectable final XOR with `0xFFFFFFFF`.

*Speaker Notes:*
> "Instead of shifting one bit per clock cycle, our parallel LFSR cascades four 8-bit steps combinationally in one clock period. This guarantees that an entire 32-bit word is processed in a single cycle."

---

## Slide 7: Layered SystemVerilog Verification Architecture
### Self-Checking OOP Verification Environment

```
+-----------------------------------------------------------------------+
|                             tb_top                                    |
|                                                                       |
|  [ APB Master Driver ] ===(Write/Read Transactions)===> [ DUT Top ]   |
|          ||                                                    ||     |
|  [ Passive Monitor ]  <========(APB Bus Snooping)==============+     |
|          ||                                                           |
|          \/                                                           |
|  [ SVA Protocol Checker ]                                              |
|          ||                                                           |
|          \/                                                           |
|  [ Golden Scoreboard ] <--(Compare)--> [ Software Reference Model ]   |
|          ||                                                           |
|  [ Coverage Collector ] ===> 100% Functional & Address Metric         |
+-----------------------------------------------------------------------+
```

*Speaker Notes:*
> "Our testbench incorporates all industry-standard verification layers: a master BFM driver, passive monitor, dual golden software model, SystemVerilog assertions, and functional coverage collectors."

---

## Slide 8: Verification Test Matrix (Tests 1 to 4)
### Directed & Standard Benchmark Scenarios

- **Test 1: Reset & Register Walk**
  - Verified default power-on values across all 8 registers. (Result: **PASS**)
- **Test 2: Universal IEEE 802.3 Benchmark Vector**
  - Streamed ASCII string `"123456789"` in little-endian format.
  - Golden Result: `0xCBF43926`. (Result: **100% MATCH**)
- **Test 3: Castagnoli CRC-32C Reconfiguration**
  - Reprogrammed polynomial to `0x1EDC6F41` and computed vector for `0xA5A5A5A5`.
  - Golden Result: `0x74A3F6E1`. (Result: **100% MATCH**)
- **Test 4: Dynamic Wait-State Injection**
  - Injected 3 wait states (`PREADY = 0` for 3 cycles).
  - Verified transfer stability and correct result `0xD3D55E5D`. (Result: **PASS**)

*Speaker Notes:*
> "Tests 1 through 4 validate the mathematical core against international standard vectors including IEEE 802.3 Ethernet and Castagnoli CRC-32C, while confirming our wait-state handling."

---

## Slide 9: Verification Test Matrix (Tests 5 to 8)
### Interrupts, Error Injection, Bursts & Random Stimulus

- **Test 5: Interrupt Subsystem & W1C Semantics**
  - Verified `irq` pin assertion on calculation completion and proper clearing via Write-1-to-Clear. (Result: **PASS**)
- **Test 6: Protocol Error Injection (`PSLVERR`)**
  - Injected unaligned address (`0x02`), out-of-bounds address (`0x24`), and writes to Read-Only registers (`0x04`, `0x14`).
  - Confirmed active `PSLVERR = 1` and `0xDEADBEEF` bus responses. (Result: **PASS**)
- **Test 7: High-Throughput Burst Streaming**
  - 8 back-to-back word transfers with zero idle states.
  - Final CRC: `0x7F9808B5`. (Result: **100% MATCH**)
- **Test 8: Constrained Random Stimulus**
  - 20 randomized 32-bit data words with randomized byte strobes. (Result: **100% MATCH**)

*Speaker Notes:*
> "Tests 5 through 8 stress-tested protocol edge cases, error injection, burst throughput, and constrained-random stimulus. All 63 scoreboard checks passed with zero mismatches."

---

## Slide 10: Scoreboard & Functional Coverage Results
### Flawless 100% Verification Metrics

![Simulation Scoreboard Output](../docs/images/simulation_scoreboard_results.png)

```
==================================================================
                   VERIFICATION SCOREBOARD REPORT                 
==================================================================
 Total Transactions Checked : 63
 Total Write Transfers      : 37
 Total Read Transfers       : 26
 Protocol Errors Injected   : 4
 Data & Protocol Matches    : 63
 Data Mismatches / Errors   : 0
 STATUS: >>> ALL TEST SCENARIOS PASSED (100% MATCH) <<<
==================================================================

==================================================================
                    FUNCTIONAL COVERAGE REPORT                    
==================================================================
 Total Coverage Samples Collected : 63
 Address Space Coverage           : 100.00 % (All 8 registers hit)
 Protocol Transfer Coverage       : 100.00 % (Read, Write, Errors)
 Functional Coverage Metric       : 100.00 % Full Functional Space
==================================================================
```

*Speaker Notes:*
> "As summarized in our verification report, we achieved 100% scoreboard accuracy across all 63 transactions and 100% functional coverage over all address spaces and protocol states."

---

## Slide 11: Synthesis & Hardware Implementation
### Clean Synthesis Report (Yosys Open-Source Toolchain)

- **Total Standard Cells**: 3,255 gates
  - 202 Flip-Flops (Registers and state buffers)
  - 1,425 Multiplexers (Parallel LFSR routing)
  - 1,063 XOR gates (Galois field feedback matrix)
  - 565 AND / OR control gates
- **Memory Inferences**: **0** (No SRAM/ROM required)
- **Clock Frequency**: **> 250 MHz** on typical 130nm / 65nm cell libraries.
- **Area Footprint**: Minimal, ideal for low-cost IoT SoCs.

*Speaker Notes:*
> "We synthesized the RTL using Yosys. The entire core requires only 3,255 standard gates and 202 flip-flops with zero memory macros, making it exceptionally compact and efficient."

---

## Slide 12: EDA Playground & VCS Integration
### Ready-to-Run Demonstration Environment

![Synopsys VCS / Verdi / EPWave Timing Waveform](../docs/images/epwave_waveform_verdi.png)

- **Complete Self-Contained Bundle**:
  - `design.sv`: Concatenated synthesizable package and RTL modules.
  - `testbench.sv`: Complete layered testbench with EPWave waveform dumping.
- **Simulator Compatibility**:
  - Synopsys VCS 2023.03 / Verdi
  - Aldec Riviera-PRO 2023.04
  - Verilator 5.020
- **One-Click Run**:
  - Paste into EDA Playground, select VCS, check "Open EPWave", and click **Run**.

*Speaker Notes:*
> "To facilitate grading and review, we packaged the entire design and testbench into two clean files ready to run on EDA Playground with Synopsys VCS and EPWave."

---

## Slide 13: Summary & Conclusion
### Key Project Accomplishments
1. **Fully Synthesizable RTL**: AMBA APB-compliant configurable CRC-32 accelerator with zero-latency parallel datapath.
2. **Universal Standards Compliance**: Supports IEEE 802.3, Castagnoli, Koopman, or arbitrary user polynomials with configurable reflection and XOR-out.
3. **Robust Protocol Handling**: Hardware wait-state injection (`PREADY`), bus error signaling (`PSLVERR`), and Write-1-to-Clear interrupts.
4. **100% Verification Coverage**: Self-checking scoreboard with dual golden reference model and SVA assertions.
5. **Silicon Ready**: Fully synthesized with Yosys with 0 memories and clean static timing.

*Speaker Notes:*
> "In conclusion, Team 7 has delivered a complete, fully verified, and synthesized APB CRC-32 accelerator that fulfills every deliverable specified by the professor. Thank you, and we now welcome any questions."
