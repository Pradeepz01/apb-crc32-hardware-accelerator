# EDA Playground Setup Instructions

Follow these exact steps to run the simulation on [EDA Playground](https://www.edaplayground.com):

1. **Left Panel (Design)**:
   - Copy and paste the entire contents of [`design.sv`](./design.sv).

2. **Right Panel (Testbench)**:
   - Copy and paste the entire contents of [`testbench.sv`](./testbench.sv).

3. **Tool & Simulator Settings**:
   - **For Aldec Riviera Pro**:
     - **Simulator**: `Aldec Riviera Pro 2023.04`
     - **Compile Options**: (leave empty or `-timescale 1ns/1ps`)
     - Check: **"Open EPWave after run"**
   - **For Synopsys VCS**:
     - **Simulator**: `Synopsys VCS 2023.03`
     - **Compile Options**: `-sverilog -timescale=1ns/1ps -kdb -debug_access+all`
     - Check: **"Open EPWave after run"**
   - **Top entity**: `tb_top` (or leave default)

4. **Run**:
   - Click **Run** in the top navigation bar.
   - Simulation will execute and report:
     `>>> ALL TEST SCENARIOS PASSED (100% MATCH) <<<`
     `Functional Coverage Metric: 100.00 %`
   - EPWave will automatically launch with the full waveform hierarchy.
