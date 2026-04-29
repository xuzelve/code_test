# code_test

## GD9Fx1GxF2A NAND 控制器 RTL（初版）

- 需求说明：`docs/requirements-GD9Fx1GxF2A-Kintex7-driver.md`（§5.3 端口）
- 源码：`rtl/verilog/`
  - `gd9f_nand_ctrl.v` — 顶层控制器（擦除 / 页写 / 页读 + 同步 FIFO）
  - `sync_fifo_16.v` — 单时钟 16bit FIFO
  - `nand_flash_model_gd9f.v` — 仿真用简易 NAND 行为模型
  - `tb_gd9f_nand.v` — 擦除最小仿真 testbench

**v1 约束**：写/读 FIFO 与主状态机同域，请将 `i_clk_wr_fifo`、`i_clk_rd_fifo` 与 `i_clk_in` 短接；数据需在发 `i_wr_en` 前写入写 FIFO。

仿真（需安装 Icarus Verilog）：

```bash
iverilog -g2012 -o sim.out rtl/verilog/sync_fifo_16.v rtl/verilog/gd9f_nand_ctrl.v rtl/verilog/nand_flash_model_gd9f.v rtl/verilog/tb_gd9f_nand.v && vvp sim.out
```
