# Verification Test Plan: APB CRC-32 Hardware Accelerator

**Subsystem**: `apb_crc32_top`  
**Team 7**: Bhuvanesh S, Aathithya K, Pradeep  
**Methodology**: Layered SystemVerilog Testbench with Self-Checking Scoreboard, SVA Assertions, and Functional Coverage  
**Version**: 1.0  

---

## 1. Verification Strategy & Objectives

The primary verification goal is to achieve **100% functional coverage** and **100% scoreboard data match** across all operational modes of the APB CRC-32 Hardware Accelerator.

### Verification Principles
- **Dual Independent Golden Models**: Hardware computation is continuously compared cycle-by-cycle against a bit-accurate software reference model implemented in SystemVerilog.
- **Protocol Assertion Suite**: SystemVerilog Assertions (SVA) check compliance with the ARM AMBA APB specification on every clock cycle.
- **Constrained-Random Stimulus**: In addition to standard directed vectors (IEEE 802.3 and Castagnoli), pseudorandom bursts are streamed to uncover corner-case state corruptions.

---

## 2. Feature Verification Matrix

| Feature ID | Feature Name | Description | Test Scenario | Expected Outcome |
| :---: | :--- | :--- | :---: | :--- |
| **F-01** | Power-On Reset | Verify all registers reset to specified default values. | Test 1 | All registers return reset defaults (`CTRL=0x5C`, `POLY=0x04C11DB7`, etc.). |
| **F-02** | IEEE 802.3 CRC-32 | Stream ASCII string `"123456789"` in 32-bit and 8-bit modes. | Test 2 | Result matches golden Ethernet standard `0xCBF43926`. |
| **F-03** | Castagnoli CRC-32C | Program custom polynomial `0x1EDC6F41` and calculate checksum. | Test 3 | Result matches golden vector `0x74A3F6E1`. |
| **F-04** | APB Wait-States | Configure `WAIT_STATES=3` and verify `PREADY` extension. | Test 4 | Slave holds `PREADY=0` for 3 cycles; transfer finishes cleanly with match. |
| **F-05** | Interrupt & W1C | Enable Done and Err interrupts; verify latching and W1C clear. | Test 5 | `irq` asserts on done; clears to `0` when writing `1` to `CRC_INT_STAT`. |
| **F-06** | Protocol Error | Inject unaligned addresses, out-of-bounds, and RO writes. | Test 6 | Slave asserts `PSLVERR=1`; register file remains uncorrupted. |
| **F-07** | Burst Transfers | Back-to-back sequential word writes with zero idle cycles. | Test 7 | 8 consecutive writes processed without state stall or data loss. |
| **F-08** | Constrained Random | Randomized 32-bit streaming data with random strobes. | Test 8 | 100% data match against software model over 20 random transactions. |

---

## 3. Test Scenarios Description

### Test 1: Register Readout & Default State Verification
- **Goal**: Verify reset defaults and basic read operations.
- **Actions**: Read all registers from `0x00` through `0x1C`.
- **Checks**:
  - `CRC_CTRL` == `0x0000005C`
  - `CRC_STATUS` == `0x00000080` (FSM IDLE)
  - `CRC_POLY` == `0x04C11DB7`
  - `CRC_INIT` == `0xFFFFFFFF`
  - `CRC_RESULT` == `0x00000000`
  - `CRC_INT_EN` == `0x00000000`
  - `CRC_INT_STAT` == `0x00000000`

### Test 2: IEEE 802.3 Standard Vector (ASCII `"123456789"`)
- **Goal**: Verify mathematical accuracy against the universal industry CRC-32 benchmark.
- **Actions**:
  1. Write `0x0000005E` to `CRC_CTRL` (Reset accumulator).
  2. Write `0x0000005C` to `CRC_CTRL` (32-bit word mode, `REFIN=1`, `REFOUT=1`, `XOROUT=1`).
  3. Write `0x34333231` (`"1234"` in little-endian) with `PSTRB=4'b1111`.
  4. Write `0x38373635` (`"5678"` in little-endian) with `PSTRB=4'b1111`.
  5. Write `0x0000001C` to `CRC_CTRL` (Switch to 8-bit byte mode).
  6. Write `0x00000039` (`"9"`) with `PSTRB=4'b0001`.
  7. Read `CRC_RESULT`.
- **Pass Metric**: `CRC_RESULT == 32'hCBF43926`.

### Test 3: Castagnoli CRC-32C Polynomial Verification
- **Goal**: Verify reconfigurability of generator polynomial.
- **Actions**:
  1. Program `CRC_POLY = 0x1EDC6F41` (Castagnoli polynomial used in iSCSI/Btrfs).
  2. Read back `CRC_POLY` to verify register retention.
  3. Reset accumulator and stream word `0xA5A5A5A5`.
  4. Read `CRC_RESULT` and compare against reference model (`0x74A3F6E1`).
  5. Restore default IEEE polynomial.

### Test 4: Dynamic APB Wait-State Injection
- **Goal**: Verify `PREADY` delay generator and bus slave stability.
- **Actions**:
  1. Set `CRC_CTRL[11:8] = 4'h3` (3 wait states).
  2. Write `0x11223344` to `CRC_DATA_IN`.
  3. Verify master observes `PREADY=0` for exactly 3 clock cycles.
  4. Read `CRC_RESULT` with 3 wait cycles; verify computed CRC matches `0xD3D55E5D`.
  5. Restore `WAIT_STATES = 0`.

### Test 5: Interrupt Subsystem & W1C Clearing
- **Goal**: Verify interrupt generation and Write-1-to-Clear semantics.
- **Actions**:
  1. Write `0x03` to `CRC_INT_EN` (Enable Done and Error interrupts).
  2. Stream `0xCAFEBABE` into `CRC_DATA_IN`.
  3. Verify `irq` pin drives HIGH and `CRC_INT_STAT[0] == 1`.
  4. Write `1` to `CRC_INT_STAT[0]`.
  5. Verify `CRC_INT_STAT[0] == 0` and `irq` drops to `0`.

### Test 6: Protocol Error Injection & PSLVERR
- **Goal**: Verify protocol robustness and error reporting.
- **Actions**:
  1. Read unaligned address `0x02` $\rightarrow$ Expect `PSLVERR=1`, `PRDATA=0xDEADBEEF`.
  2. Read out-of-bounds address `0x24` $\rightarrow$ Expect `PSLVERR=1`, `PRDATA=0xDEADBEEF`.
  3. Write to Read-Only `CRC_STATUS` (`0x04`) $\rightarrow$ Expect `PSLVERR=1`.
  4. Write to Read-Only `CRC_RESULT` (`0x14`) $\rightarrow$ Expect `PSLVERR=1`.

### Test 7: High-Throughput Burst Streaming
- **Goal**: Verify zero-stall back-to-back pipeline operation.
- **Actions**: Stream 8 consecutive words (`0x10000000` to `0x10000007`) in back-to-back ACCESS-to-SETUP cycles without idle states.
- **Checks**: Final CRC matches reference model `0x7F9808B5`.

### Test 8: Constrained Random Stimulus
- **Goal**: Stress test with pseudorandom data operands.
- **Actions**: 20 randomized 32-bit words streamed; scoreboard checks every transaction.

---

## 4. SystemVerilog Assertions (SVA) Matrix

| Assertion Name | Scope | Expression / Description |
| :--- | :---: | :--- |
| `SVA_PENABLE_AFTER_PSEL` | APB Bus | `psel && !penable \|=> penable` |
| `SVA_PADDR_STABLE_IN_ACCESS` | APB Bus | `psel && penable && !pready \|=> $stable(paddr)` |
| `SVA_PWDATA_STABLE_IN_ACCESS`| APB Bus | `psel && penable && pwrite && !pready \|=> $stable(pwdata)` |
| `SVA_PWRITE_STABLE_IN_ACCESS`| APB Bus | `psel && penable && !pready \|=> $stable(pwrite)` |
| `SVA_PSLVERR_ONLY_IN_ACCESS` | APB Bus | `pslverr \|-> (psel && penable && pready)` |

---

## 5. Functional Coverage Model

```systemverilog
covergroup apb_coverage_cg @(posedge pclk);
  // Address Space Coverage
  cp_addr: coverpoint paddr {
    bins reg_ctrl     = {ADDR_CRC_CTRL};
    bins reg_status   = {ADDR_CRC_STATUS};
    bins reg_poly     = {ADDR_CRC_POLY};
    bins reg_init     = {ADDR_CRC_INIT};
    bins reg_data_in  = {ADDR_CRC_DATA_IN};
    bins reg_result   = {ADDR_CRC_RESULT};
    bins reg_int_en   = {ADDR_CRC_INT_EN};
    bins reg_int_stat = {ADDR_CRC_INT_STAT};
  }

  // Direction Coverage
  cp_write: coverpoint pwrite {
    bins read  = {1'b0};
    bins write = {1'b1};
  }

  // Strobe Coverage
  cp_strb: coverpoint pstrb {
    bins byte0     = {4'b0001};
    bins byte1     = {4'b0010};
    bins halfword  = {4'b0011};
    bins full_word = {4'b1111};
  }

  // Error Response Coverage
  cp_error: coverpoint pslverr {
    bins no_error = {1'b0};
    bins error    = {1'b1};
  }

  // Cross Coverage
  cross_addr_dir: cross cp_addr, cp_write;
endgroup
```

**Target Metric**: 100% address bin coverage, 100% direction coverage, 100% error response coverage.
