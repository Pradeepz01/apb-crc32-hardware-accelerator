# AMBA® APB-Compliant Configurable CRC-32 Hardware Accelerator Subsystem

[![Language](https://img.shields.io/badge/Language-SystemVerilog%20IEEE%201800-blue.svg)](#)
[![Bus Protocol](https://img.shields.io/badge/Bus-AMBA%203%2F4%20APB-orange.svg)](#)
[![Synthesis](https://img.shields.io/badge/Synthesis-Yosys%20Clean%20(3255%20cells)-success.svg)](#)
[![Verification](https://img.shields.io/badge/Verification-100%25%20Pass%20(63%2F63)-brightgreen.svg)](#)
[![Coverage](https://img.shields.io/badge/Functional%20Coverage-100%25-green.svg)](#)
[![Simulator](https://img.shields.io/badge/Simulators-VCS%20%7C%20Verilator%20%7C%20Riviera-purple.svg)](#)

---

## 📌 Project Overview

This repository contains the complete synthesizable RTL design, SystemVerilog layered verification environment, simulation results, synthesis reports, and documentation for an **AMBA® APB-compliant Configurable CRC-32 Hardware Accelerator Subsystem**.

The subsystem is engineered for high-performance Systems-on-Chip (SoCs) to offload Cyclic Redundancy Check (CRC) operations from host processors for Ethernet (IEEE 802.3), storage (iSCSI, Btrfs), and automotive communications.

### 👥 Team Members
- **PRADEEP S** (Roll No: 2023105505)
- **BHUVANESH S** (Roll No: 2023105039)
- **AATHITYA K** (Roll No: 2023105060)
- **Course**: EC23E34 Design and Verification using SystemVerilog
- **Department**: Department of Electronics and Communication Engineering
- **Institution**: College of Engineering, Guindy, Anna University: Chennai 600025

---

## 🚀 Key Features

- **AMBA APB Protocol Compliance**: Complete APB3 and APB4 support, including `PREADY` handshake extension and `PSLVERR` error response.
- **Single-Cycle Parallel LFSR**: Computes up to 32 bits (4 bytes) per clock cycle via a combinational Galois field cascade (Peak throughput **3.2 Gbps @ 100 MHz**).
- **Run-Time Programmable Polynomial**: Supports standard IEEE 802.3 Ethernet (`0x04C11DB7`), Castagnoli CRC-32C (`0x1EDC6F41`), Koopman (`0x741B8CD7`), or any arbitrary 32-bit polynomial.
- **Configurable Bit & Byte Reflection**:
  - `REFIN`: Independent byte-level bit reversal.
  - `REFOUT`: 32-bit word reflection before final inversion.
  - `XOROUT`: Selectable inversion mask (`0xFFFFFFFF`).
- **Flexible Stream Sizing**: Supports 8-bit (Byte), 16-bit (Halfword), and 32-bit (Word) transfers with active byte strobes (`PSTRB[3:0]`).
- **Configurable Bus Wait-States**: Hardware-controlled wait-state injection (`0` to `15` cycles) to model realistic bus contention.
- **Protocol Error Detection**: Automatic `PSLVERR` assertion for unaligned word addresses, out-of-bounds access, and writes to read-only registers.
- **Interrupt Controller**: Dedicated `irq` line with maskable Done and Error interrupts and Write-1-to-Clear (`W1C`) status handling.

---

## 🏛 Subsystem Architecture

![Subsystem Architecture](docs/images/microarchitecture_block_diagram.png)

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

### 🔄 APB Protocol Finite State Machine
![APB FSM State Diagram](docs/images/apb_fsm_state_diagram.png)

---

## 📋 Memory-Mapped Register Space

The peripheral occupies 32 bytes of memory-mapped address space:

| Offset | Register Name | Access | Reset Default | Description |
| :---: | :--- | :---: | :---: | :--- |
| `0x00` | `CRC_CTRL` | R/W | `0x0000005C` | Control, Data Size, and Wait-State configuration |
| `0x04` | `CRC_STATUS` | RO | `0x00000080` | Busy, Ready, Error flags, and APB FSM state |
| `0x08` | `CRC_POLY` | R/W | `0x04C11DB7` | 32-bit Generator Polynomial (Default: IEEE 802.3) |
| `0x0C` | `CRC_INIT` | R/W | `0xFFFFFFFF` | Seed Initialization Vector |
| `0x10` | `CRC_DATA_IN` | WO/RW | `0x00000000` | Stream Data Input Port |
| `0x14` | `CRC_RESULT` | RO | `0x00000000` | Current Computed CRC Checksum |
| `0x18` | `CRC_INT_EN` | R/W | `0x00000000` | Interrupt Mask Register (Done & Err) |
| `0x1C` | `CRC_INT_STAT` | R/W1C | `0x00000000` | Interrupt Status Flags (Write-1-to-Clear) |

---

## 📂 Repository Directory Structure

```
miniproject/
├── README.md                           # Master Project Readme
├── rtl/                                # Synthesizable SystemVerilog RTL
│   ├── apb_crc32_pkg.sv                # Package: Register offsets, polynomials, types
│   ├── crc32_engine.sv                 # Parallel 4-byte combinational LFSR core
│   ├── apb_crc32_regfile.sv            # Memory-mapped register file & interrupt controller
│   ├── apb_slave_fsm.sv                # APB3/APB4 protocol FSM with wait-state generator
│   └── apb_crc32_top.sv                # Top-level integrated peripheral
├── tb/                                 # Layered SystemVerilog Testbench
│   ├── apb_interface.sv                # SystemVerilog APB interface & SVA assertions
│   ├── apb_transaction.sv              # Constrained-random transaction class
│   ├── apb_driver.sv                   # Master BFM driver
│   ├── apb_monitor.sv                  # Passive bus monitor
│   ├── apb_scoreboard.sv               # Golden reference model & comparator
│   ├── apb_coverage.sv                 # Functional coverage collector
│   ├── apb_environment.sv              # Top-level verification environment
│   └── tb_top.sv                       # Self-checking top module (8 test suites)
├── edaplayground/                      # Single-Bundle EDA Playground Files
│   ├── README.md                       # Setup & run instructions for EDA Playground
│   ├── design.sv                       # Concatenated synthesizable package + RTL
│   └── testbench.sv                    # Complete testbench for Synopsys VCS / EPWave
├── sim_results/                        # Simulation Logs & Waveforms
│   ├── simulation_log.txt              # Complete simulation execution output (100% pass)
│   └── crc32_apb.vcd                   # Generated VCD waveform (73 KB)
├── doc/                                # Detailed Course Technical Specifications
│   ├── apb_specification_document.md   # APB protocol compliance & register spec
│   ├── microarchitecture_spec.md       # Microarchitecture datapath & cell report
│   ├── fsm_state_diagram.md            # FSM state diagram & transition conditions
│   └── test_plan.md                    # Verification test plan & coverage matrix
├── reports/                            # Formal Course Report
│   ├── Final_Course_Report.pdf         # Complete 9-page formal academic report (LaTeX typeset PDF)
│   ├── Final_Course_Report.md          # Comprehensive formal academic project report
│   └── final_report.tex                # LaTeX publication source code
└── presentation/                       # Presentation Materials
    └── PPT_Presentation.md             # 13-slide course presentation deck
```

---

## ⚡ Simulation & Reproduction Guide

### Run with Verilator (Local Linux Shell)
```bash
cd miniproject
verilator --binary --timing --trace \
  -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
  -Irtl -Itb \
  rtl/apb_crc32_pkg.sv \
  rtl/crc32_engine.sv \
  rtl/apb_crc32_regfile.sv \
  rtl/apb_slave_fsm.sv \
  rtl/apb_crc32_top.sv \
  tb/tb_top.sv \
  --top-module tb_top -Mdir obj_dir -o sim_crc32

./obj_dir/sim_crc32
```

### Run with Synopsys VCS (on Server / EDA Playground)
```bash
vcs -sverilog -timescale=1ns/1ps -kdb -debug_access+all \
  edaplayground/design.sv edaplayground/testbench.sv -o simv
./simv
```

### Run RTL Synthesis Check (Yosys)
```bash
yosys -p "
read_verilog -sv rtl/apb_crc32_pkg.sv rtl/crc32_engine.sv rtl/apb_crc32_regfile.sv rtl/apb_slave_fsm.sv rtl/apb_crc32_top.sv;
hierarchy -top apb_crc32_top;
proc; opt; fsm; opt; memory; opt; techmap; opt;
stat;
"
```

---

## 📊 Verification Results Summary

### 📄 Formal Academic PDF Report
- **Download / View**: [**`reports/Final_Course_Report.pdf`**](./reports/Final_Course_Report.pdf) (Complete 9-page IEEE/ACM publication-grade report with microarchitecture, mathematical formulation, SVA, synthesis cell breakdown, and waveform traces)
- **LaTeX Source**: [`reports/final_report.tex`](./reports/final_report.tex)

### 📈 Authentic EDA Playground (EPWave) Simulation Waveform (0 to 1000 ns)
![EDA Playground EPWave Waveform](docs/images/edaplayground_waveform_real.png)

### 🔍 Synopsys VCS / Verdi / EPWave Timing Waveform Detail
![EPWave Verdi Waveform](docs/images/epwave_waveform_verdi.png)

### 🖥 Simulation Execution & Scoreboard Terminal Output
![Simulation Scoreboard Results](docs/images/simulation_scoreboard_results.png)

### Test Execution Matrix
| Test ID | Test Scenario | Verified Functionality | Status |
| :---: | :--- | :--- | :---: |
| **Test 1** | Register Walk | Reset values of all 8 registers (`CTRL`, `POLY`, etc.) | **PASS** |
| **Test 2** | IEEE 802.3 Benchmark | ASCII `"123456789"` produces golden `0xCBF43926` | **100% MATCH** |
| **Test 3** | Castagnoli CRC-32C | Custom poly `0x1EDC6F41` streams `0xA5A5A5A5` $\rightarrow$ `0x74A3F6E1` | **100% MATCH** |
| **Test 4** | Wait-State Injection | 3 wait cycles on `PREADY` during write & read | **100% MATCH** |
| **Test 5** | Interrupt & W1C | Interrupt assertion and Write-1-to-Clear clearing | **PASS** |
| **Test 6** | Protocol Error Injection | Unaligned (`0x02`), out-of-bounds (`0x24`), RO write (`0x04`) $\rightarrow$ `PSLVERR=1` | **PASS** |
| **Test 7** | Back-to-Back Burst | 8 consecutive word writes with zero idle cycles | **100% MATCH** |
| **Test 8** | Constrained Random | 20 randomized 32-bit data words with random strobes | **100% MATCH** |

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

---

## 🔬 Synthesis & Gate Count Report (Yosys)

- **Total Standard Cells**: 3,255
- **Sequential Flip-Flops**: 202
- **Multiplexers**: 1,425
- **XOR Logic Gates**: 1,063
- **Inferred Memories**: **0** (Pure standard cell logic, 100% synthesizable)
- **Target Operating Frequency**: **> 250 MHz**

---

## 🌐 EDA Playground Ready

To run online:
1. Open [EDA Playground](https://www.edaplayground.com).
2. Copy [`edaplayground/design.sv`](./edaplayground/design.sv) into the **Design** window.
3. Copy [`edaplayground/testbench.sv`](./edaplayground/testbench.sv) into the **Testbench** window.
4. Select **Synopsys VCS 2023.03** or **Aldec Riviera Pro 2023.04**.
5. Check **Open EPWave after run** and click **Run**.
