from __future__ import annotations

import json
import os
import queue
import subprocess
import sys
import threading
import time
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass(frozen=True)
class PcRunResult:
    request_id: int
    script: str
    elapsed_seconds: float
    return_code: int
    generated_text: str
    fp32_text: str
    stdout: str
    stderr: str


def default_python_executable() -> str:
    candidates = (
        os.environ.get("NANOGPT_PYTHON", ""),
        sys.executable,
    )
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return candidate
    return "python"


def load_generated_text(script: Path, prompt: str) -> tuple[str, str]:
    report_path = script.parent / "demo_outputs" / "last_token_run.json"
    if not report_path.is_file():
        return "", ""
    report = json.loads(report_path.read_text(encoding="utf-8"))
    int8_text = str(report.get("int8_text") or "")
    fp32_text = str(report.get("fp32_text") or "")
    if int8_text.startswith(prompt):
        int8_text = int8_text[len(prompt) :]
    if fp32_text.startswith(prompt):
        fp32_text = fp32_text[len(prompt) :]
    return int8_text, fp32_text


class PcReferenceWorker:
    def __init__(self, events: queue.Queue[tuple[str, object]]) -> None:
        self.events = events
        self._process: subprocess.Popen[str] | None = None
        self._thread: threading.Thread | None = None
        self._lock = threading.Lock()

    @property
    def running(self) -> bool:
        with self._lock:
            return self._process is not None and self._process.poll() is None

    def start(
        self,
        request_id: int,
        python_executable: str,
        script_path: str,
        prompt: str,
        max_new_tokens: int,
    ) -> None:
        if self.running:
            raise RuntimeError("PC comparison is already running")
        script = Path(script_path).resolve()
        if not script.is_file():
            raise FileNotFoundError(f"Python file not found: {script}")
        self._thread = threading.Thread(
            target=self._run,
            args=(request_id, python_executable, script, prompt, max_new_tokens),
            daemon=True,
        )
        self._thread.start()

    def stop(self) -> None:
        with self._lock:
            process = self._process
        if process is not None and process.poll() is None:
            process.terminate()

    def _run(
        self,
        request_id: int,
        python_executable: str,
        script: Path,
        prompt: str,
        max_new_tokens: int,
    ) -> None:
        started = time.monotonic()
        env = os.environ.copy()
        env["PYTHONUTF8"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        command = [
            python_executable,
            "-u",
            str(script),
            "--prompt",
            prompt,
            "--max-new-tokens",
            str(max_new_tokens),
        ]
        try:
            process = subprocess.Popen(
                command,
                cwd=str(script.parent),
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                bufsize=1,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
            )
            with self._lock:
                self._process = process
            output_lines: list[str] = []
            if process.stdout is not None:
                with process.stdout:
                    for line in process.stdout:
                        output_lines.append(line)
                        self.events.put(
                            (
                                "pc_progress",
                                {
                                    "request_id": request_id,
                                    "line": line.rstrip("\r\n"),
                                    "elapsed_seconds": time.monotonic() - started,
                                    "max_new_tokens": max_new_tokens,
                                },
                            )
                        )
            return_code = process.wait()
            stdout = "".join(output_lines)
            generated_text, fp32_text = load_generated_text(script, prompt)
            result = PcRunResult(
                request_id=request_id,
                script=str(script),
                elapsed_seconds=time.monotonic() - started,
                return_code=int(return_code),
                generated_text=generated_text,
                fp32_text=fp32_text,
                stdout=stdout,
                stderr="",
            )
            self.events.put(("pc_done", asdict(result)))
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            self.events.put(("pc_error", {"request_id": request_id, "message": str(exc)}))
        finally:
            with self._lock:
                self._process = None
