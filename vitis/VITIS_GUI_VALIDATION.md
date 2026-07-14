# Vitis GUI 手动验证记录

验证日期：2026-07-13  
工具：Vitis Classic 2025.2  
工作区：仓库内 `vitis/workspace`

## 已手动执行

1. 使用 `open_vitis_classic.cmd` 打开 Vitis IDE。
2. 在 Assistant 中点击 `ps_mailbox_runner_vitis`。
3. 点击 **Project -> Clean...**，选择 **Clean all projects** 和 **Start a build immediately**。
4. 点击 **Clean**，完成 C、汇编、链接和 Size 步骤。
5. 再次选择应用工程并按 `Ctrl+B`，验证增量构建。

## 结果

- GUI 日志结尾：`Build Finished (took 1s.122ms)`。
- 错误匹配数：`0`。
- 应用 ELF：`Debug/ps_mailbox_runner_vitis.elf`，55968 字节。
- Size 报告：text `13552`、data `8`、bss `16392`、dec `29952`。
- SHA256：`1F828C34C4C58A42D4C2897FA01FEB662F40C34DDBFD5B9B8111E2F2C36278E9`。

## 已解决的问题

Vitis Classic 的托管构建会把 Size 步骤写为 `arm-none-eabi-size ... | tee ...`，当前 Windows 构建环境不能稳定解析工具 PATH 和 `tee`。工程现使用 ARM Size 的绝对路径，并把输出模式改为直接重定向到 `.elf.size`，因此 GUI 点击构建不再报错。

## 尚需真实硬件的验证

下载 ELF、启动 PS、由 PS 触发 PL、JTAG 调试以及 UART token 输出，需要连接目标 Zynq 板。该记录只确认本机 GUI 工程、平台/BSP和 ARM ELF 编译链闭环。
