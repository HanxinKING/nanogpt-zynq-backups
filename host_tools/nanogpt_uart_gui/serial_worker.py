from __future__ import annotations

import queue
import threading
import time
from dataclasses import dataclass

import serial
from serial.tools import list_ports


@dataclass(frozen=True)
class PortInfo:
    device: str
    label: str


def available_ports() -> list[PortInfo]:
    result: list[PortInfo] = []
    for port in sorted(list_ports.comports(), key=lambda item: item.device):
        description = port.description or "串口设备"
        result.append(PortInfo(port.device, f"{port.device}  {description}"))
    return result


class SerialWorker:
    def __init__(self, events: queue.Queue[tuple[str, object]]) -> None:
        self.events = events
        self._serial: serial.Serial | None = None
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()
        self._write_lock = threading.Lock()

    @property
    def connected(self) -> bool:
        return self._serial is not None and self._serial.is_open

    def connect(self, port: str, baud: int) -> None:
        if self.connected:
            return
        self._serial = serial.Serial(
            port=port,
            baudrate=baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.1,
            write_timeout=1.0,
        )
        self._stop.clear()
        self._thread = threading.Thread(target=self._read_loop, daemon=True)
        self._thread.start()

    def disconnect(self) -> None:
        self._stop.set()
        serial_port = self._serial
        self._serial = None
        if serial_port is not None:
            try:
                serial_port.close()
            except serial.SerialException:
                pass

    def write(self, payload: bytes) -> None:
        if not self.connected or self._serial is None:
            raise serial.SerialException("串口尚未连接。")
        with self._write_lock:
            written = self._serial.write(payload)
            self._serial.flush()
        if written != len(payload):
            raise serial.SerialTimeoutException(f"串口只发送了 {written}/{len(payload)} 字节。")

    def _read_loop(self) -> None:
        while not self._stop.is_set():
            serial_port = self._serial
            if serial_port is None:
                return
            try:
                data = serial_port.read(serial_port.in_waiting or 1)
                if data:
                    self.events.put(("data", data))
                else:
                    time.sleep(0.01)
            except (serial.SerialException, OSError) as exc:
                if not self._stop.is_set():
                    self.events.put(("error", str(exc)))
                return
