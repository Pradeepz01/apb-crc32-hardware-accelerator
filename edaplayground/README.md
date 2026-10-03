# EDA Playground Setup Instructions

Follow these exact steps to run the simulation on [EDA Playground](https://www.edaplayground.com):

1. **Left Panel (Design)**:
   - Copy and paste the entire contents of [`design.sv`](./design.sv).

2. **Right Panel (Testbench)**:
   - Copy and paste the entire contents of [`testbench.sv`](./testbench.sv).

3. **Tool & Simulator Settings**:
   - **Simulator**: `Synopsys VCS 2023.03` (or `Aldec Riviera Pro 2023.04`)
   - **Top entity**: `tb_top`
   - **Compile Options**: `-sverilog -timescale=1ns/1ps -kdb -debug_access+all`
   - **Run Options**: (leave empty or default)
   - Check the box: **"Open EPWave after run"** (to view waveforms immediately)

4. **Run**:
   - Click **Run** in the top navigation bar.
   - Simulation will execute and report 100% Scoreboard Match across all 8 test scenarios with 0 errors.
   - EPWave will launch with all APB protocol signals, CRC engine state, and accumulator registers.
