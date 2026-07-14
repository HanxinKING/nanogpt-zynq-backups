#!/usr/bin/env python3
"""Exercise the board UART through the unused FT2232H D2XX channel."""

from __future__ import annotations

import argparse
import ctypes
import sys
import time
from dataclasses import dataclass
from pathlib import Path


FT_OK = 0
FT_BITS_8 = 8
FT_STOP_BITS_1 = 0
FT_PARITY_NONE = 0
FT_FLOW_NONE = 0


class FtdiError(RuntimeError):
    pass


@dataclass
class Device:
    index: int
    flags: int
    device_type: int
    device_id: int
    location: int
    serial: str
    description: str

    @property
    def is_open(self) -> bool:
        return bool(self.flags & 1)


class D2xx:
    def __init__(self, dll_path: str) -> None:
        self.lib = ctypes.WinDLL(dll_path)
        u32_p = ctypes.POINTER(ctypes.c_uint32)
        handle_p = ctypes.POINTER(ctypes.c_void_p)
        self.lib.FT_CreateDeviceInfoList.argtypes = [u32_p]
        self.lib.FT_CreateDeviceInfoList.restype = ctypes.c_uint32
        self.lib.FT_GetDeviceInfoDetail.argtypes = [
            ctypes.c_uint32,
            u32_p,
            u32_p,
            u32_p,
            u32_p,
            ctypes.c_void_p,
            ctypes.c_void_p,
            handle_p,
        ]
        self.lib.FT_GetDeviceInfoDetail.restype = ctypes.c_uint32
        self.lib.FT_Open.argtypes = [ctypes.c_int, handle_p]
        self.lib.FT_Open.restype = ctypes.c_uint32
        self.lib.FT_Close.argtypes = [ctypes.c_void_p]
        self.lib.FT_Close.restype = ctypes.c_uint32
        self.lib.FT_SetBaudRate.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        self.lib.FT_SetBaudRate.restype = ctypes.c_uint32
        self.lib.FT_SetDataCharacteristics.argtypes = [
            ctypes.c_void_p,
            ctypes.c_uint8,
            ctypes.c_uint8,
            ctypes.c_uint8,
        ]
        self.lib.FT_SetDataCharacteristics.restype = ctypes.c_uint32
        self.lib.FT_SetFlowControl.argtypes = [
            ctypes.c_void_p,
            ctypes.c_uint16,
            ctypes.c_uint8,
            ctypes.c_uint8,
        ]
        self.lib.FT_SetFlowControl.restype = ctypes.c_uint32
        self.lib.FT_SetTimeouts.argtypes = [
            ctypes.c_void_p,
            ctypes.c_uint32,
            ctypes.c_uint32,
        ]
        self.lib.FT_SetTimeouts.restype = ctypes.c_uint32
        self.lib.FT_SetLatencyTimer.argtypes = [ctypes.c_void_p, ctypes.c_uint8]
        self.lib.FT_SetLatencyTimer.restype = ctypes.c_uint32
        self.lib.FT_GetQueueStatus.argtypes = [ctypes.c_void_p, u32_p]
        self.lib.FT_GetQueueStatus.restype = ctypes.c_uint32
        self.lib.FT_Read.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_uint32,
            u32_p,
        ]
        self.lib.FT_Read.restype = ctypes.c_uint32
        self.lib.FT_Write.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_uint32,
            u32_p,
        ]
        self.lib.FT_Write.restype = ctypes.c_uint32

    @staticmethod
    def _check(status: int, operation: str) -> None:
        if status != FT_OK:
            raise FtdiError(f"{operation} failed with FT_STATUS={status}")

    def devices(self) -> list[Device]:
        count = ctypes.c_uint32()
        self._check(self.lib.FT_CreateDeviceInfoList(ctypes.byref(count)), "enumerate")
        result: list[Device] = []
        for index in range(count.value):
            flags = ctypes.c_uint32()
            device_type = ctypes.c_uint32()
            device_id = ctypes.c_uint32()
            location = ctypes.c_uint32()
            serial = ctypes.create_string_buffer(64)
            description = ctypes.create_string_buffer(64)
            handle = ctypes.c_void_p()
            self._check(
                self.lib.FT_GetDeviceInfoDetail(
                    index,
                    ctypes.byref(flags),
                    ctypes.byref(device_type),
                    ctypes.byref(device_id),
                    ctypes.byref(location),
                    serial,
                    description,
                    ctypes.byref(handle),
                ),
                f"inspect device {index}",
            )
            result.append(
                Device(
                    index=index,
                    flags=flags.value,
                    device_type=device_type.value,
                    device_id=device_id.value,
                    location=location.value,
                    serial=serial.value.decode("ascii", errors="replace"),
                    description=description.value.decode("ascii", errors="replace"),
                )
            )
        return result

    def open(self, index: int, baud: int) -> ctypes.c_void_p:
        handle = ctypes.c_void_p()
        self._check(self.lib.FT_Open(index, ctypes.byref(handle)), f"open device {index}")
        try:
            self._check(self.lib.FT_SetBaudRate(handle, baud), "set baud")
            self._check(
                self.lib.FT_SetDataCharacteristics(
                    handle, FT_BITS_8, FT_STOP_BITS_1, FT_PARITY_NONE
                ),
                "set 8N1",
            )
            self._check(
                self.lib.FT_SetFlowControl(handle, FT_FLOW_NONE, 0, 0),
                "disable flow control",
            )
            self._check(self.lib.FT_SetTimeouts(handle, 100, 1000), "set timeouts")
            self._check(self.lib.FT_SetLatencyTimer(handle, 2), "set latency")
            return handle
        except Exception:
            self.lib.FT_Close(handle)
            raise

    def close(self, handle: ctypes.c_void_p) -> None:
        self._check(self.lib.FT_Close(handle), "close")

    def read(self, handle: ctypes.c_void_p) -> bytes:
        queued = ctypes.c_uint32()
        self._check(self.lib.FT_GetQueueStatus(handle, ctypes.byref(queued)), "queue status")
        if queued.value == 0:
            return b""
        buffer = ctypes.create_string_buffer(queued.value)
        received = ctypes.c_uint32()
        self._check(
            self.lib.FT_Read(handle, buffer, queued.value, ctypes.byref(received)),
            "read",
        )
        return buffer.raw[: received.value]

    def write(self, handle: ctypes.c_void_p, data: bytes) -> None:
        buffer = ctypes.create_string_buffer(data)
        written = ctypes.c_uint32()
        self._check(
            self.lib.FT_Write(handle, buffer, len(data), ctypes.byref(written)),
            "write",
        )
        if written.value != len(data):
            raise FtdiError(f"short write: {written.value}/{len(data)} bytes")


def print_devices(devices: list[Device]) -> None:
    for dev in devices:
        state = "open" if dev.is_open else "free"
        print(
            f"index={dev.index} state={state} id=0x{dev.device_id:08x} "
            f"loc=0x{dev.location:08x} serial={dev.serial!r} "
            f"description={dev.description!r}"
        )


def select_device(devices: list[Device], requested: int | None) -> Device:
    if requested is not None:
        try:
            selected = next(dev for dev in devices if dev.index == requested)
        except StopIteration as exc:
            raise FtdiError(f"D2XX index {requested} does not exist") from exc
        if selected.is_open:
            raise FtdiError(f"D2XX index {requested} is already open")
        return selected

    free = [dev for dev in devices if not dev.is_open and dev.device_id == 0x04036010]
    channel_b = [
        dev
        for dev in free
        if dev.description.rstrip().upper().endswith(" B")
        or dev.serial.rstrip().upper().endswith("B")
    ]
    if channel_b:
        return channel_b[0]
    if len(free) == 1:
        return free[0]
    raise FtdiError("cannot choose the UART channel automatically; pass --index")


def stream_test(
    d2xx: D2xx,
    handle: ctypes.c_void_p,
    line: str,
    startup_timeout: float,
    result_timeout: float,
    output_path: Path | None,
) -> bytes:
    startup = bytearray()
    startup_deadline = time.monotonic() + startup_timeout
    while time.monotonic() < startup_deadline:
        chunk = d2xx.read(handle)
        if chunk:
            startup.extend(chunk)
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
            if b"> " in startup:
                break
        time.sleep(0.02)

    payload = line.encode("ascii") + b"\r"
    print(f"\nTX {line!r}", flush=True)
    d2xx.write(handle, payload)

    response = bytearray()
    saw_output = False
    deadline = time.monotonic() + result_timeout
    while time.monotonic() < deadline:
        chunk = d2xx.read(handle)
        if chunk:
            response.extend(chunk)
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
            if b"output: " in response:
                saw_output = True
            if saw_output and response.endswith(b"\n> "):
                break
        time.sleep(0.02)
    else:
        raise TimeoutError(f"UART response timed out after {result_timeout:.1f} s")

    if output_path is not None:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(bytes(response))
    return bytes(response)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dll", default=r"C:\Windows\System32\ftd2xx.dll")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--index", type=int)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--line", default="hello world")
    parser.add_argument("--startup-timeout", type=float, default=10.0)
    parser.add_argument("--timeout", type=float, default=900.0)
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    d2xx = D2xx(args.dll)
    devices = d2xx.devices()
    print_devices(devices)
    if args.list:
        return 0
    selected = select_device(devices, args.index)
    print(f"UART_DEVICE index={selected.index} serial={selected.serial!r}", flush=True)
    handle = d2xx.open(selected.index, args.baud)
    try:
        response = stream_test(
            d2xx,
            handle,
            args.line,
            args.startup_timeout,
            args.timeout,
            args.output,
        )
    finally:
        d2xx.close(handle)
    print(f"\nUART_PASS bytes={len(response)}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FtdiError, TimeoutError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
