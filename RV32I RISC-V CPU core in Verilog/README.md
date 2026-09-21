# rv32i-mini

A single-cycle RV32I CPU written in Verilog. Runs a small embedded program
(sum of 1..10) and verifies the result in a self-checking testbench.

## Files
- `rv32i_core.v` — CPU + instruction ROM + data RAM (program embedded).
- `tb_rv32i.v` — testbench with per-cycle trace and pass/fail check.

## Running on EDA Playground (no install needed)
1. Open <https://www.edaplayground.com/>.
2. Left panel:
   - **Tools & Simulators:** Icarus Verilog 12.0 (or any Icarus).
   - Check **Open EPWave after run** (to view waveforms).
3. Paste `rv32i_core.v` into the **design.sv** tab.
4. Paste `tb_rv32i.v` into the **testbench.sv** tab.
5. Click **Run**.

## Expected output (last lines)
```
Final x1 (sum)   = 55  (expected 55)
dmem[0]          = 55  (expected 55)
RESULT: PASS
```
