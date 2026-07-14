# 科创课堂 nanoGPT Zynq 串口上位机

## 功能

- 自动扫描 Windows 串口并优先选择 COM11 或 FTDI 设备。
- 使用 115200 baud、8N1、ASCII 与开发板通信。
- 支持 1 至 256 token 输出请求；实际生成量受 256 token 总上下文限制。
- 自动发送 `输出数:英文提示词` 协议，例如 `200:hello world`。
- 实时显示模型返回字符、首字符延迟、总耗时和生成速度。
- 检查 256 token 上下文上限和 ASCII 输入范围。
- 支持清空终端、自动滚动和导出测试日志。

## 使用

1. 连接 Smart Zynq SP2 V1.2 的 USB 串口。
2. 运行 `dist/KeChuangNanoGPT.exe`。
3. 选择板卡串口，通常为 COM11，波特率选择 115200。
4. 点击“连接设备”。
5. 输入英文提示词和输出 token 数，点击“发送并生成”。

板端正常返回格式：

```text
hello world
output:  the sea
>
```

## 源码运行

```powershell
python .\app.py
```

## 打包

```powershell
.\build.ps1
```
