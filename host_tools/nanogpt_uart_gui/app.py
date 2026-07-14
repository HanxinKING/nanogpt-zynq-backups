from __future__ import annotations

import json
import os
import queue
import time
import tkinter as tk
import ctypes
from datetime import datetime
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

import serial

from protocol import (
    DEFAULT_OUTPUT_TOKENS,
    MAX_CONTEXT_TOKENS,
    ProtocolError,
    ResponseTracker,
    build_command,
    effective_output_limit,
)
from serial_worker import PortInfo, SerialWorker, available_ports
APP_NAME = "科创课堂 nanoGPT Zynq 串口平台"
APP_VERSION = "1.4.0"
COLORS = {
    "nav": "#17212B",
    "nav_2": "#22303C",
    "canvas": "#F3F5F7",
    "panel": "#FFFFFF",
    "line": "#D9E0E6",
    "text": "#18222C",
    "muted": "#667784",
    "accent": "#007C83",
    "accent_hover": "#006A70",
    "success": "#159A68",
    "warning": "#C97A16",
    "danger": "#C64545",
    "terminal": "#101820",
    "terminal_text": "#DDE7EC",
    "terminal_muted": "#7E919D",
}


def enable_high_dpi() -> None:
    """Make Tk render natively on high-DPI Windows displays."""
    if os.name != "nt":
        return
    try:
        ctypes.windll.user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
    except (AttributeError, OSError):
        try:
            ctypes.windll.shcore.SetProcessDpiAwareness(2)
        except (AttributeError, OSError):
            ctypes.windll.user32.SetProcessDPIAware()


def build_log_header(port: str, baud: str, exported_at: datetime | None = None) -> str:
    exported_at = exported_at or datetime.now()
    return (
        f"{APP_NAME}\n"
        f"导出时间: {exported_at:%Y-%m-%d %H:%M:%S}\n"
        f"串口: {port}  波特率: {baud}  格式: 8N1\n"
        + "=" * 72
        + "\n"
    )


class NanoGptHostApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(f"{APP_NAME} v{APP_VERSION}")
        dpi = max(96.0, float(self.winfo_fpixels("1i")))
        display_scale = dpi / 96.0
        self.tk.call("tk", "scaling", dpi / 72.0)
        width = min(int(1180 * display_scale), max(980, self.winfo_screenwidth() - 80))
        height = min(int(760 * display_scale), max(650, self.winfo_screenheight() - 80))
        self.geometry(f"{width}x{height}")
        self.minsize(min(980, width), min(650, height))
        self.configure(bg=COLORS["canvas"])

        self.events: queue.Queue[tuple[str, object]] = queue.Queue()
        self.worker = SerialWorker(self.events)
        self.tracker = ResponseTracker()
        self.ports: list[PortInfo] = []
        self.session_log: list[str] = []
        self.request_started: float | None = None
        self.first_output_at: float | None = None
        self.tx_bytes = 0
        self.rx_bytes = 0
        self.generated_tokens = 0
        self.request_id = 0
        self.board_complete = True
        self.settings_path = self._settings_path()

        self.port_var = tk.StringVar()
        self.baud_var = tk.StringVar(value="115200")
        self.token_var = tk.IntVar(value=DEFAULT_OUTPUT_TOKENS)
        self.prompt_var = tk.StringVar(value="hello world")
        self.status_var = tk.StringVar(value="未连接")
        self.connection_detail_var = tk.StringVar(value="选择串口后建立连接")
        self.context_var = tk.StringVar(value="上下文 11 / 256")
        self.elapsed_var = tk.StringVar(value="--")
        self.first_token_var = tk.StringVar(value="--")
        self.speed_var = tk.StringVar(value="--")
        self.count_var = tk.StringVar(value="0")
        self.bytes_var = tk.StringVar(value="TX 0  /  RX 0")
        self.auto_scroll_var = tk.BooleanVar(value=True)

        self._configure_styles()
        self._build_layout()
        self._load_settings()
        self._refresh_ports()
        self._update_context()

        self.prompt_var.trace_add("write", lambda *_: self._update_context())
        self.token_var.trace_add("write", lambda *_: self._update_context())
        self.after(40, self._process_events)
        self.after(200, self._update_timer)
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _configure_styles(self) -> None:
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure("TCombobox", padding=7, fieldbackground="#FFFFFF")
        style.configure("TSpinbox", padding=7, fieldbackground="#FFFFFF")
        style.configure("Primary.TButton", padding=(16, 10), font=("Microsoft YaHei UI", 10, "bold"))
        style.map(
            "Primary.TButton",
            background=[("active", COLORS["accent_hover"]), ("!disabled", COLORS["accent"])],
            foreground=[("!disabled", "#FFFFFF")],
        )
        style.configure("Quiet.TButton", padding=(12, 8), font=("Microsoft YaHei UI", 9))
        style.configure("Danger.TButton", padding=(12, 8), font=("Microsoft YaHei UI", 9))
        style.map(
            "Danger.TButton",
            background=[("active", "#A93838"), ("!disabled", COLORS["danger"])],
            foreground=[("!disabled", "#FFFFFF")],
        )

    def _build_layout(self) -> None:
        self.grid_rowconfigure(0, weight=1)
        self.grid_columnconfigure(1, weight=1)

        nav = tk.Frame(self, bg=COLORS["nav"], width=230)
        nav.grid(row=0, column=0, sticky="nsew")
        nav.grid_propagate(False)
        self._build_nav(nav)

        content = tk.Frame(self, bg=COLORS["canvas"])
        content.grid(row=0, column=1, sticky="nsew")
        content.grid_rowconfigure(2, weight=1)
        content.grid_columnconfigure(0, weight=1)

        self._build_header(content)
        self._build_connection_bar(content)
        self._build_workspace(content)
        self._build_input_bar(content)

    def _build_nav(self, parent: tk.Frame) -> None:
        brand = tk.Frame(parent, bg=COLORS["nav"], padx=22, pady=24)
        brand.pack(fill="x")
        mark = tk.Frame(brand, bg=COLORS["accent"], width=8, height=42)
        mark.pack(side="left", padx=(0, 12))
        mark.pack_propagate(False)
        title_box = tk.Frame(brand, bg=COLORS["nav"])
        title_box.pack(side="left")
        tk.Label(
            title_box,
            text="科创课堂",
            bg=COLORS["nav"],
            fg="#FFFFFF",
            font=("Microsoft YaHei UI", 16, "bold"),
        ).pack(anchor="w")
        tk.Label(
            title_box,
            text="nanoGPT INT8 FPGA 推理平台",
            bg=COLORS["nav"],
            fg="#8EA1AE",
            font=("Microsoft YaHei UI", 8, "bold"),
        ).pack(anchor="w", pady=(3, 0))

        tk.Frame(parent, bg="#2A3945", height=1).pack(fill="x", padx=22)

        info = tk.Frame(parent, bg=COLORS["nav"], padx=22, pady=22)
        info.pack(fill="x")
        self._nav_item(info, "平台", "nanoGPT 串口终端")
        self._nav_item(info, "模型", "Shakespeare INT8")
        self._nav_item(info, "硬件", "XC7Z020 / 100 MHz")
        self._nav_item(info, "协议", "ASCII / 115200 8N1")

        spacer = tk.Frame(parent, bg=COLORS["nav"])
        spacer.pack(fill="both", expand=True)

        footer = tk.Frame(parent, bg=COLORS["nav_2"], padx=22, pady=18)
        footer.pack(fill="x", side="bottom")
        tk.Label(
            footer,
            text="上下文上限 256 token",
            bg=COLORS["nav_2"],
            fg="#D6E0E6",
            font=("Microsoft YaHei UI", 9),
        ).pack(anchor="w")
        tk.Label(
            footer,
            text=f"Desktop Host v{APP_VERSION}",
            bg=COLORS["nav_2"],
            fg="#80929F",
            font=("Segoe UI", 8),
        ).pack(anchor="w", pady=(5, 0))

    @staticmethod
    def _nav_item(parent: tk.Frame, label: str, value: str) -> None:
        row = tk.Frame(parent, bg=COLORS["nav"])
        row.pack(fill="x", pady=8)
        tk.Label(
            row,
            text=label,
            width=5,
            anchor="w",
            bg=COLORS["nav"],
            fg="#80929F",
            font=("Microsoft YaHei UI", 9),
        ).pack(side="left")
        tk.Label(
            row,
            text=value,
            anchor="w",
            bg=COLORS["nav"],
            fg="#E4EBEF",
            font=("Microsoft YaHei UI", 9),
        ).pack(side="left")

    def _build_header(self, parent: tk.Frame) -> None:
        header = tk.Frame(parent, bg=COLORS["canvas"], padx=26, pady=20)
        header.grid(row=0, column=0, sticky="ew")
        header.grid_columnconfigure(0, weight=1)
        title_box = tk.Frame(header, bg=COLORS["canvas"])
        title_box.grid(row=0, column=0, sticky="w")
        tk.Label(
            title_box,
            text="nanoGPT Zynq 串口交互平台",
            bg=COLORS["canvas"],
            fg=COLORS["text"],
            font=("Microsoft YaHei UI", 18, "bold"),
        ).pack(anchor="w")
        tk.Label(
            title_box,
            text="字符级 INT8 推理 · 流式输出 · 性能记录",
            bg=COLORS["canvas"],
            fg=COLORS["muted"],
            font=("Microsoft YaHei UI", 9),
        ).pack(anchor="w", pady=(4, 0))

        status_box = tk.Frame(header, bg=COLORS["canvas"])
        status_box.grid(row=0, column=1, sticky="e")
        self.status_dot = tk.Canvas(status_box, width=12, height=12, bg=COLORS["canvas"], highlightthickness=0)
        self.status_dot.pack(side="left", padx=(0, 8))
        self.status_dot.create_oval(2, 2, 10, 10, fill=COLORS["muted"], outline="")
        tk.Label(
            status_box,
            textvariable=self.status_var,
            bg=COLORS["canvas"],
            fg=COLORS["text"],
            font=("Microsoft YaHei UI", 10, "bold"),
        ).pack(side="left")

    def _build_connection_bar(self, parent: tk.Frame) -> None:
        outer = tk.Frame(parent, bg=COLORS["canvas"], padx=26)
        outer.grid(row=1, column=0, sticky="ew")
        bar = tk.Frame(outer, bg=COLORS["panel"], highlightbackground=COLORS["line"], highlightthickness=1, padx=16, pady=13)
        bar.pack(fill="x")
        bar.grid_columnconfigure(1, weight=1)

        tk.Label(bar, text="串口", bg=COLORS["panel"], fg=COLORS["muted"], font=("Microsoft YaHei UI", 9)).grid(row=0, column=0, sticky="w", padx=(0, 8))
        self.port_combo = ttk.Combobox(bar, textvariable=self.port_var, state="readonly", width=34)
        self.port_combo.grid(row=0, column=1, sticky="ew", padx=(0, 8))
        ttk.Button(bar, text="刷新", command=self._refresh_ports, style="Quiet.TButton").grid(row=0, column=2, padx=(0, 18))

        tk.Label(bar, text="波特率", bg=COLORS["panel"], fg=COLORS["muted"], font=("Microsoft YaHei UI", 9)).grid(row=0, column=3, padx=(0, 8))
        self.baud_combo = ttk.Combobox(bar, textvariable=self.baud_var, values=("9600", "57600", "115200", "230400"), state="readonly", width=10)
        self.baud_combo.grid(row=0, column=4, padx=(0, 12))
        self.connect_button = ttk.Button(bar, text="连接设备", command=self._toggle_connection, style="Primary.TButton")
        self.connect_button.grid(row=0, column=5)

    def _build_workspace(self, parent: tk.Frame) -> None:
        workspace = tk.Frame(parent, bg=COLORS["canvas"], padx=26, pady=18)
        workspace.grid(row=2, column=0, sticky="nsew")
        workspace.grid_rowconfigure(0, weight=1)
        workspace.grid_columnconfigure(0, weight=1)

        terminal_panel = tk.Frame(workspace, bg=COLORS["terminal"], highlightbackground="#0A1117", highlightthickness=1)
        terminal_panel.grid(row=0, column=0, sticky="nsew", padx=(0, 16))
        terminal_panel.grid_rowconfigure(1, weight=1)
        terminal_panel.grid_columnconfigure(0, weight=1)

        terminal_header = tk.Frame(terminal_panel, bg="#18232C", padx=14, pady=10)
        terminal_header.grid(row=0, column=0, sticky="ew")
        terminal_header.grid_columnconfigure(0, weight=1)
        tk.Label(
            terminal_header,
            text="实时串口终端",
            bg="#18232C",
            fg="#E2EAEE",
            font=("Microsoft YaHei UI", 10, "bold"),
        ).grid(row=0, column=0, sticky="w")
        ttk.Checkbutton(terminal_header, text="自动滚动", variable=self.auto_scroll_var).grid(row=0, column=1, padx=(0, 8))
        ttk.Button(terminal_header, text="清空", command=self._clear_terminal, style="Quiet.TButton").grid(row=0, column=2, padx=(0, 8))
        ttk.Button(terminal_header, text="导出日志", command=self._export_log, style="Quiet.TButton").grid(row=0, column=3)

        text_frame = tk.Frame(terminal_panel, bg=COLORS["terminal"])
        text_frame.grid(row=1, column=0, sticky="nsew")
        text_frame.grid_rowconfigure(0, weight=1)
        text_frame.grid_columnconfigure(0, weight=1)
        self.terminal = tk.Text(
            text_frame,
            bg=COLORS["terminal"],
            fg=COLORS["terminal_text"],
            insertbackground="#FFFFFF",
            selectbackground="#285765",
            relief="flat",
            wrap="word",
            padx=16,
            pady=14,
            font=("Cascadia Mono", 10),
            state="disabled",
        )
        self.terminal.grid(row=0, column=0, sticky="nsew")
        scroll = ttk.Scrollbar(text_frame, orient="vertical", command=self.terminal.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        self.terminal.configure(yscrollcommand=scroll.set)
        self.terminal.tag_configure("system", foreground="#78909C")
        self.terminal.tag_configure("tx", foreground="#65D6C3")
        self.terminal.tag_configure("error", foreground="#FF8A80")
        self._append_terminal("[系统] 等待连接 nanoGPT Zynq 设备。\n", "system")

        side = tk.Frame(workspace, bg=COLORS["canvas"], width=350)
        side.grid(row=0, column=1, sticky="nsew")
        side.grid_propagate(False)
        self._build_metrics_card(side)
        self._build_status_card(side)
        self._build_protocol_card(side)

    def _build_status_card(self, parent: tk.Frame) -> None:
        card = self._card(parent, "设备状态")
        tk.Label(card, textvariable=self.status_var, bg=COLORS["panel"], fg=COLORS["text"], font=("Microsoft YaHei UI", 14, "bold")).pack(anchor="w")
        tk.Label(card, textvariable=self.connection_detail_var, bg=COLORS["panel"], fg=COLORS["muted"], font=("Microsoft YaHei UI", 9), wraplength=230, justify="left").pack(anchor="w", pady=(5, 0))

    def _build_metrics_card(self, parent: tk.Frame) -> None:
        card = self._card(parent, "本次生成")
        grid = tk.Frame(card, bg=COLORS["panel"])
        grid.pack(fill="x")
        self._metric(grid, 0, 0, "生成字符", self.count_var)
        self._metric(grid, 0, 1, "生成耗时", self.elapsed_var)
        self._metric(grid, 1, 0, "首字等待", self.first_token_var)
        self._metric(grid, 1, 1, "生成速度", self.speed_var)
        tk.Frame(card, bg=COLORS["line"], height=1).pack(fill="x", pady=12)
        tk.Label(card, textvariable=self.bytes_var, bg=COLORS["panel"], fg=COLORS["muted"], font=("Cascadia Mono", 9)).pack(anchor="w")

    def _build_protocol_card(self, parent: tk.Frame) -> None:
        card = self._card(parent, "协议参数")
        items = (
            ("数据格式", "ASCII"),
            ("串口格式", "115200 / 8N1"),
            ("请求范围", "1 - 256 token"),
            ("上下文", "最大 256 token"),
            ("发送结尾", "CR"),
        )
        for key, value in items:
            row = tk.Frame(card, bg=COLORS["panel"])
            row.pack(fill="x", pady=3)
            tk.Label(row, text=key, bg=COLORS["panel"], fg=COLORS["muted"], font=("Microsoft YaHei UI", 9)).pack(side="left")
            tk.Label(row, text=value, bg=COLORS["panel"], fg=COLORS["text"], font=("Microsoft YaHei UI", 9, "bold")).pack(side="right")

    @staticmethod
    def _card(parent: tk.Frame, title: str) -> tk.Frame:
        outer = tk.Frame(parent, bg=COLORS["panel"], highlightbackground=COLORS["line"], highlightthickness=1, padx=16, pady=15)
        outer.pack(fill="x", pady=(0, 12))
        tk.Label(outer, text=title, bg=COLORS["panel"], fg=COLORS["muted"], font=("Microsoft YaHei UI", 9, "bold")).pack(anchor="w", pady=(0, 10))
        return outer

    @staticmethod
    def _metric(parent: tk.Frame, row: int, column: int, label: str, variable: tk.StringVar) -> None:
        box = tk.Frame(parent, bg=COLORS["panel"], width=115, height=58)
        box.grid(row=row, column=column, sticky="nsew", padx=(0 if column == 0 else 8, 8 if column == 0 else 0), pady=5)
        parent.grid_columnconfigure(column, weight=1)
        box.grid_propagate(False)
        tk.Label(box, text=label, bg=COLORS["panel"], fg=COLORS["muted"], font=("Microsoft YaHei UI", 8)).pack(anchor="w")
        tk.Label(box, textvariable=variable, bg=COLORS["panel"], fg=COLORS["text"], font=("Segoe UI", 13, "bold")).pack(anchor="w", pady=(4, 0))

    def _build_input_bar(self, parent: tk.Frame) -> None:
        outer = tk.Frame(parent, bg=COLORS["canvas"], padx=26)
        outer.grid(row=3, column=0, sticky="ew", pady=(0, 24))
        panel = tk.Frame(outer, bg=COLORS["panel"], highlightbackground=COLORS["line"], highlightthickness=1, padx=16, pady=14)
        panel.pack(fill="x")
        panel.grid_columnconfigure(0, weight=1)

        prompt_box = tk.Frame(panel, bg=COLORS["panel"])
        prompt_box.grid(row=0, column=0, sticky="ew", padx=(0, 14))
        prompt_box.grid_columnconfigure(0, weight=1)
        tk.Label(prompt_box, text="英文提示词", bg=COLORS["panel"], fg=COLORS["muted"], font=("Microsoft YaHei UI", 9)).grid(row=0, column=0, sticky="w")
        self.prompt_entry = tk.Entry(
            prompt_box,
            textvariable=self.prompt_var,
            bg="#F8FAFB",
            fg=COLORS["text"],
            insertbackground=COLORS["text"],
            relief="solid",
            bd=1,
            highlightthickness=0,
            font=("Cascadia Mono", 11),
        )
        self.prompt_entry.grid(row=1, column=0, sticky="ew", ipady=10, pady=(6, 0))
        self.prompt_entry.bind("<Return>", lambda _event: self._send_prompt())

        token_box = tk.Frame(panel, bg=COLORS["panel"])
        token_box.grid(row=0, column=1, sticky="ns", padx=(0, 14))
        tk.Label(token_box, text="输出 token", bg=COLORS["panel"], fg=COLORS["muted"], font=("Microsoft YaHei UI", 9)).pack(anchor="w")
        self.token_spin = ttk.Spinbox(token_box, from_=1, to=256, textvariable=self.token_var, width=9, justify="center")
        self.token_spin.pack(fill="x", pady=(6, 0), ipady=4)

        action_box = tk.Frame(panel, bg=COLORS["panel"])
        action_box.grid(row=0, column=2, sticky="ns")
        tk.Label(action_box, textvariable=self.context_var, bg=COLORS["panel"], fg=COLORS["muted"], font=("Microsoft YaHei UI", 8)).pack(anchor="e")
        self.send_button = ttk.Button(action_box, text="发送并生成", command=self._send_prompt, style="Primary.TButton", state="disabled")
        self.send_button.pack(fill="x", pady=(7, 0))

    def _refresh_ports(self) -> None:
        current_device = self._selected_device()
        self.ports = available_ports()
        labels = [item.label for item in self.ports]
        self.port_combo["values"] = labels
        if not labels:
            self.port_var.set("")
            self.connection_detail_var.set("未发现可用串口，请检查 USB 驱动")
            return
        selected_index = 0
        if current_device:
            for index, item in enumerate(self.ports):
                if item.device == current_device:
                    selected_index = index
                    break
        else:
            for index, item in enumerate(self.ports):
                if item.device.upper() == "COM11" or "FTDI" in item.label.upper():
                    selected_index = index
                    break
        self.port_combo.current(selected_index)
        if not self.worker.connected:
            self.connection_detail_var.set(f"发现 {len(labels)} 个串口设备")

    def _selected_device(self) -> str:
        label = self.port_var.get()
        for item in self.ports:
            if item.label == label:
                return item.device
        return label.split()[0] if label else ""

    def _toggle_connection(self) -> None:
        if self.worker.connected:
            self._disconnect()
            return
        port = self._selected_device()
        if not port:
            messagebox.showwarning("未选择串口", "请刷新并选择板卡对应的串口。", parent=self)
            return
        try:
            baud = int(self.baud_var.get())
            self.worker.connect(port, baud)
        except (ValueError, serial.SerialException, OSError) as exc:
            messagebox.showerror("连接失败", str(exc), parent=self)
            self._set_status("连接失败", COLORS["danger"], str(exc))
            return
        self._set_status("已连接", COLORS["success"], f"{port} · {baud} baud · 8N1")
        self.connect_button.configure(text="断开连接", style="Danger.TButton")
        self.send_button.configure(state="normal")
        self._append_terminal(f"[{self._clock()}] 已连接 {port} @ {baud} 8N1\n", "system")
        self._save_settings()

    def _disconnect(self) -> None:
        device = self._selected_device()
        self.worker.disconnect()
        self._set_status("未连接", COLORS["muted"], "选择串口后建立连接")
        self.connect_button.configure(text="连接设备", style="Primary.TButton")
        self.send_button.configure(state="disabled")
        self.request_started = None
        self.first_output_at = None
        self._append_terminal(f"[{self._clock()}] 已断开 {device or '串口'}\n", "system")

    def _send_prompt(self) -> None:
        if not self.worker.connected:
            messagebox.showwarning("设备未连接", "请先连接串口设备。", parent=self)
            return
        try:
            requested = int(self.token_var.get())
            prompt = self.prompt_var.get()
            payload = build_command(prompt, requested)
            self.worker.write(payload)
        except (ProtocolError, ValueError, serial.SerialException, OSError) as exc:
            messagebox.showerror("发送失败", str(exc), parent=self)
            return

        self.tracker.reset()
        self.request_id += 1
        self.board_complete = False
        self.request_started = time.monotonic()
        self.first_output_at = None
        self.generated_tokens = 0
        self.elapsed_var.set("--")
        self.first_token_var.set("--")
        self.speed_var.set("--")
        self.count_var.set("0")
        self.tx_bytes += len(payload)
        self._update_bytes()
        command = payload.decode("ascii").rstrip("\r")
        self._append_terminal(f"\n[{self._clock()}] TX  {command}\n", "tx")
        self.status_var.set("生成中")
        self.connection_detail_var.set("模型正在执行六层 INT8 推理")
        self.send_button.configure(state="disabled")

    def _process_events(self) -> None:
        while True:
            try:
                event, payload = self.events.get_nowait()
            except queue.Empty:
                break
            if event == "data":
                self._handle_data(payload if isinstance(payload, bytes) else bytes())
            elif event == "error":
                self._append_terminal(f"\n[串口错误] {payload}\n", "error")
                self._disconnect()
        self.after(40, self._process_events)

    def _handle_data(self, data: bytes) -> None:
        self.rx_bytes += len(data)
        self._update_bytes()
        text = data.decode("ascii", errors="replace")
        self.session_log.append(text)
        self._append_terminal(text)
        result = self.tracker.feed(text)
        if result.generated_tokens > 0 and self.first_output_at is None:
            self.first_output_at = time.monotonic()
            self.elapsed_var.set("0.00 s")
            if self.request_started is not None:
                self.first_token_var.set(f"{self.first_output_at - self.request_started:.2f} s")
        self.generated_tokens = result.generated_tokens
        self.count_var.set(str(result.generated_tokens))
        if result.complete:
            if self.first_output_at is not None:
                elapsed = max(0.001, time.monotonic() - self.first_output_at)
                self.elapsed_var.set(f"{elapsed:.2f} s")
                self.speed_var.set(f"{result.generated_tokens / elapsed:.2f} 字符/s")
            self.board_complete = True
            self.board_output = result.text
            self.request_started = None
            self._finish_request_if_ready()

    def _finish_request_if_ready(self) -> None:
        if self.board_complete:
            self.status_var.set("已连接")
            self.connection_detail_var.set("板卡生成完成")
            self.send_button.configure(state="normal")

    def _update_timer(self) -> None:
        if self.request_started is not None and self.first_output_at is not None:
            elapsed = time.monotonic() - self.first_output_at
            self.elapsed_var.set(f"{elapsed:.2f} s")
            if self.generated_tokens > 0:
                self.speed_var.set(f"{self.generated_tokens / max(elapsed, 0.001):.2f} 字符/s")
        self.after(200, self._update_timer)

    def _update_context(self) -> None:
        prompt = self.prompt_var.get()
        try:
            prompt_length = len(prompt.encode("ascii"))
            limit = effective_output_limit(prompt) if prompt else 256
            requested = int(self.token_var.get())
            total = min(MAX_CONTEXT_TOKENS, prompt_length + max(0, requested))
            self.context_var.set(f"上下文 {total} / 256 · 实际最多 {limit}")
        except (UnicodeEncodeError, ProtocolError, ValueError):
            self.context_var.set("请检查英文输入和 token 数")

    def _set_status(self, status: str, color: str, detail: str) -> None:
        self.status_var.set(status)
        self.connection_detail_var.set(detail)
        self.status_dot.delete("all")
        self.status_dot.create_oval(2, 2, 10, 10, fill=color, outline="")

    def _append_terminal(self, text: str, tag: str | None = None) -> None:
        self.terminal.configure(state="normal")
        self.terminal.insert("end", text, tag or ())
        self.terminal.configure(state="disabled")
        if self.auto_scroll_var.get():
            self.terminal.see("end")

    def _clear_terminal(self) -> None:
        self.terminal.configure(state="normal")
        self.terminal.delete("1.0", "end")
        self.terminal.configure(state="disabled")
        self.session_log.clear()
        self._append_terminal("[系统] 终端记录已清空。\n", "system")

    def _export_log(self) -> None:
        default_name = f"nanogpt_uart_{datetime.now():%Y%m%d_%H%M%S}.txt"
        path = filedialog.asksaveasfilename(
            parent=self,
            title="导出串口日志",
            defaultextension=".txt",
            initialfile=default_name,
            filetypes=(("文本文件", "*.txt"), ("所有文件", "*.*")),
        )
        if not path:
            return
        header = build_log_header(self._selected_device(), self.baud_var.get())
        content = self.terminal.get("1.0", "end-1c")
        Path(path).write_text(header + content, encoding="utf-8")
        self._append_terminal(f"[{self._clock()}] 日志已导出：{Path(path).name}\n", "system")

    def _update_bytes(self) -> None:
        self.bytes_var.set(f"TX {self.tx_bytes}  /  RX {self.rx_bytes}")

    @staticmethod
    def _clock() -> str:
        return datetime.now().strftime("%H:%M:%S")

    @staticmethod
    def _settings_path() -> Path:
        root = Path(os.environ.get("APPDATA", Path.home())) / "KeChuangNanoGPT"
        root.mkdir(parents=True, exist_ok=True)
        return root / "settings.json"

    def _load_settings(self) -> None:
        if not self.settings_path.exists():
            return
        try:
            data = json.loads(self.settings_path.read_text(encoding="utf-8"))
            self.baud_var.set(str(data.get("baud", "115200")))
            self.token_var.set(int(data.get("tokens", DEFAULT_OUTPUT_TOKENS)))
            self.prompt_var.set(str(data.get("prompt", "hello world")))
        except (OSError, ValueError, json.JSONDecodeError):
            pass

    def _save_settings(self) -> None:
        data = {
            "baud": self.baud_var.get(),
            "tokens": self.token_var.get(),
            "prompt": self.prompt_var.get(),
            "port": self._selected_device(),
        }
        try:
            self.settings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        except OSError:
            pass

    def _on_close(self) -> None:
        self._save_settings()
        self.worker.disconnect()
        self.destroy()


if __name__ == "__main__":
    enable_high_dpi()
    NanoGptHostApp().mainloop()
