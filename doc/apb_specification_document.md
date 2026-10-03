# APB Specification Document: Configurable CRC-32 Hardware Accelerator

**Project Title**: Design and Verification of an APB-Compliant Configurable CRC-32 Hardware Accelerator Subsystem  
**Team 7**: Bhuvanesh S, Aathithya K, Pradeep  
**Protocol Compliance**: ARM® AMBA® 3 / AMBA® 4 APB Protocol Specification  
**Version**: 1.0  
**Date**: October 2026  

---

## 1. Overview & System Scope

The **APB CRC-32 Hardware Accelerator** is a high-performance peripheral core designed to offload Cyclic Redundancy Check (CRC) computations from a host processor in embedded Systems-on-Chip (SoC). The core connects directly to an AMBA Advanced Peripheral Bus (APB) interconnect, providing byte, halfword, and word streaming capability with zero-latency combinational LFSR cascading.

### Key Capabilities
- **AMBA APB Protocol Compliance**: Complete support for APB3 and APB4 signaling including `PREADY` handshake extension and `PSLVERR` error response.
- **Configurable Polynomial Engine**: Supports standard IEEE 802.3 Ethernet (`0x04C11DB7`), Castagnoli CRC-32C (`0x1EDC6F41`), Koopman (`0x741B8CD7`), or any arbitrary 32-bit user-defined polynomial.
- **Configurable Bit & Byte Reflection**: Independent input bit reversal (`REFIN`) and output bit reversal (`REFOUT`).
- **Programmable XOR-Out**: Selectable final inversion/masking (`XOROUT`) adhering to standard CRC profiles.
- **Dynamic Bus Wait-State Injection**: Programmable hardware wait-states (`0` to `15` cycles) to model realistic multi-cycle memory/bus latency.
- **Robust Error Detection**: Protocol violation trapping for unaligned word addresses, out-of-bounds register accesses, and illegal writes to read-only locations.
- **Interrupt Subsystem**: Dedicated level-sensitive interrupt line (`irq`) with independent enable masking and Write-1-to-Clear (`W1C`) status handling.

---

## 2. APB Interface Signal Description

The peripheral implements the standard slave interface defined in the ARM AMBA 3/4 APB Protocol Specification.

| Signal Name | Width | Direction | Active Level | Description |
| :--- | :---: | :---: | :---: | :--- |
| `pclk` | 1 | Input | Rising edge | APB bus clock. All transfers are synchronized to this clock. |
| `presetn` | 1 | Input | Active LOW | Asynchronous system reset. Resets all internal registers to default states. |
| `paddr[7:0]` | 8 | Input | - | APB address bus. Byte-addressed register selection (`0x00` - `0x1C`). |
| `psel` | 1 | Input | Active HIGH | Slave select. Indicates the slave is targeted for a transfer. |
| `penable` | 1 | Input | Active HIGH | APB strobe. Indicates the second and subsequent cycles of a transfer. |
| `pwrite` | 1 | Input | HIGH=Write, LOW=Read | Direction control for bus transfer. |
| `pwdata[31:0]` | 32 | Input | - | APB write data bus driven by the master. |
| `pstrb[3:0]` | 4 | Input | Active HIGH | APB byte lane strobe. Selects active byte lanes during write operations. |
| `prdata[31:0]` | 32 | Output | - | APB read data bus driven by the peripheral during read transfers. |
| `pready` | 1 | Output | Active HIGH | Slave ready signal. Extends transfer with wait-states when LOW. |
| `pselverr` | 1 | Output | Active HIGH | Slave error indicator. Asserted on invalid address, unaligned access, or RO writes. |
| `irq` | 1 | Output | Active HIGH | Peripheral interrupt request output routed to the system interrupt controller. |

---

## 3. Bus Protocol Timing & Handshaking

### 3.1 Basic Read & Write Transfers (Zero Wait-States)
A standard transfer without wait states spans exactly two clock cycles:
1. **SETUP Phase (`T1 -> T2`)**:
   - Master drives `PADDR`, `PWRITE`, `PSEL = 1`, and `PWDATA` (if write).
   - `PENABLE` remains LOW.
   - Peripheral decodes address and prepares combinational read data or write strobes.
2. **ACCESS Phase (`T2 -> T3`)**:
   - Master asserts `PENABLE = 1`.
   - `PREADY = 1` is driven by the peripheral.
   - At the rising edge of `PCLK` (`T3`), data is transferred: write data is committed into registers, or read data is sampled by the master.
   - `PSEL` and `PENABLE` are deasserted, or move directly to SETUP for back-to-back burst transfers.

### 3.2 Wait-State Injection (`PREADY`)
When configured with `WAIT_STATES > 0` via the `CRC_CTRL[11:8]` register:
- In the ACCESS phase, the slave drives `PREADY = 0` for `N` consecutive clock cycles.
- The master must maintain all bus control signals (`PADDR`, `PSEL`, `PWRITE`, `PWDATA`, `PSTRB`, `PENABLE`) stable and unchanged.
- On cycle `N+1`, the slave asserts `PREADY = 1`.
- The transfer terminates on the next rising edge of `PCLK`.

### 3.3 Error Response Signaling (`PSLVERR`)
`PSLVERR` is driven HIGH during the final ACCESS cycle (`PSEL = 1, PENABLE = 1, PREADY = 1`) under the following illegal access conditions:
1. **Unaligned Access**: `PADDR[1:0] != 2'b00` (non-word aligned address).
2. **Out-of-Bounds Address**: `PADDR > 0x1C` (access outside the designated address space).
3. **Write to Read-Only Register**: Write attempts to `CRC_STATUS` (`0x04`) or `CRC_RESULT` (`0x14`).

When `PSLVERR` is triggered, the invalid write is suppressed (registers remain unaltered), `PRDATA` returns `0xDEADBEEF`, and the `INT_ERR` flag in `CRC_INT_STAT` is latched.

---

## 4. Memory-Mapped Register Specification

The accelerator occupies 32 bytes of address space with word-aligned 32-bit registers.

### Register Map Summary
| Offset | Register Name | Access | Reset Value | Description |
| :---: | :--- | :---: | :---: | :--- |
| `0x00` | `CRC_CTRL` | R/W | `0x0000005C` | Control, configuration, data sizing, and wait-state register |
| `0x04` | `CRC_STATUS` | RO | `0x00000080` | Engine status, FSM state observability, and flags |
| `0x08` | `CRC_POLY` | R/W | `0x04C11DB7` | Generator polynomial (Default: IEEE 802.3 Ethernet) |
| `0x0C` | `CRC_INIT` | R/W | `0xFFFFFFFF` | Initial seed value for CRC computation |
| `0x10` | `CRC_DATA_IN` | WO/RW | `0x00000000` | Data input register (writing feeds data into engine) |
| `0x14` | `CRC_RESULT` | RO | `0x00000000` | Formatted CRC computation output |
| `0x18` | `CRC_INT_EN` | R/W | `0x00000000` | Interrupt enable mask register |
| `0x1C` | `CRC_INT_STAT` | R/W1C | `0x00000000` | Interrupt status register (Write-1-to-Clear) |

---

### 4.1 `CRC_CTRL` (Offset `0x00`, R/W)
| Bits | Name | Access | Default | Description |
| :---: | :--- | :---: | :---: | :--- |
| `0` | `START` | WO | `0` | Self-clearing start bit (reserved for future multi-cycle engines). |
| `1` | `RESET_ACC` | WO | `0` | Write `1` to reinitialize the CRC accumulator to `CRC_INIT`. Self-clearing. |
| `2` | `REFIN` | RW | `1` | Bit reflection on input data bytes before feeding into LFSR. |
| `3` | `REFOUT` | RW | `1` | Bit reflection on the 32-bit accumulator before final XOR. |
| `4` | `XOROUT_EN` | RW | `1` | Output inversion enable: XORs final result with `0xFFFFFFFF`. |
| `6:5` | `DATA_SIZE` | RW | `2'b10` | Input stream granularity:<br>`2'b00`: 8-bit Byte<br>`2'b01`: 16-bit Halfword<br>`2'b10`: 32-bit Word |
| `7` | `RESERVED` | RO | `0` | Reserved. |
| `11:8` | `WAIT_STATES`| RW | `4'h0` | Number of wait cycles inserted on APB read/write transfers (`0` - `15`). |
| `31:12`| `RESERVED` | RO | `0` | Reserved. |

### 4.2 `CRC_STATUS` (Offset `0x04`, Read-Only)
| Bits | Name | Access | Default | Description |
| :---: | :--- | :---: | :---: | :--- |
| `0` | `BUSY` | RO | `0` | `1` when calculation is in progress, `0` when idle. |
| `1` | `READY` | RO | `0` | `1` indicates accumulator contains a valid calculation result. |
| `2` | `ERROR` | RO | `0` | Latched error flag. Set when an APB access violation occurs. |
| `3` | `RESERVED` | RO | `0` | Reserved. |
| `7:4` | `FSM_STATE` | RO | `4'h8` | Real-time APB FSM state (`0`=IDLE, `1`=SETUP, `2`=ACCESS). |
| `31:8` | `RESERVED` | RO | `0` | Reserved. |

### 4.3 `CRC_POLY` (Offset `0x08`, R/W)
32-bit generator polynomial in standard representation without the implicit $x^{32}$ term. Default is IEEE 802.3 Ethernet (`0x04C11DB7`).

### 4.4 `CRC_INIT` (Offset `0x0C`, R/W)
32-bit initialization vector. Default is `0xFFFFFFFF`. Writing to this register simultaneously updates the internal seed and reinitializes the active accumulator.

### 4.5 `CRC_DATA_IN` (Offset `0x10`, Write-Stream)
Writing to this register immediately streams 1, 2, or 4 active bytes (selected by `CRC_CTRL[6:5]` and `PSTRB[3:0]`) into the combinational parallel LFSR network. The accumulator updates synchronously on the committing clock edge.

### 4.6 `CRC_RESULT` (Offset `0x14`, Read-Only)
Returns the live computed CRC-32 checksum formatted according to `REFOUT` and `XOROUT_EN`. Always reflects the cumulative CRC across all data streamed since last reset.

### 4.7 `CRC_INT_EN` (Offset `0x18`, R/W) & `CRC_INT_STAT` (Offset `0x1C`, R/W1C)
| Bit | Name | Description |
| :---: | :--- | :--- |
| `0` | `DONE` | Asserted whenever a data byte/word computation completes. |
| `1` | `ERR` | Asserted whenever an APB protocol or decoding error occurs. |

Status bits are cleared by writing `1` to the respective bit position (Write-1-to-Clear).

---

## 5. Mathematical CRC Operation

The core evaluates polynomial division in the Galois Field $\text{GF}(2)$ using parallel feedback shift register equations:

$$M(x) \cdot x^{32} + I(x) \cdot x^k \equiv R(x) \pmod{P(x)}$$

Where:
- $P(x)$: 32-degree generator polynomial
- $I(x)$: Initial value polynomial (`CRC_INIT`)
- $M(x)$: Streamed data stream
- $R(x)$: Resulting remainder (`CRC_RESULT`)

For standard IEEE 802.3:
- Polynomial: $x^{32} + x^{26} + x^{23} + x^{22} + x^{16} + x^{12} + x^{11} + x^{10} + x^8 + x^7 + x^5 + x^4 + x^2 + x + 1$
- Hex: `0x04C11DB7`
- Standard ASCII test string `"123456789"` produces golden CRC `0xCBF43926`.
