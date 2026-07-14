from __future__ import annotations

import json
import queue
import sys
import tempfile
import unittest
from pathlib import Path

from pc_runner import PcReferenceWorker, load_generated_text


class PcRunnerTests(unittest.TestCase):
    def test_load_generated_text_removes_prompt(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "reference.py"
            script.write_text("", encoding="utf-8")
            output = root / "demo_outputs"
            output.mkdir()
            (output / "last_token_run.json").write_text(
                json.dumps(
                    {
                        "int8_text": "hello world the sea",
                        "fp32_text": "hello world.\n",
                    }
                ),
                encoding="utf-8",
            )
            int8_text, fp32_text = load_generated_text(script, "hello world")
            self.assertEqual(int8_text, " the sea")
            self.assertEqual(fp32_text, ".\n")

    def test_missing_report_returns_empty_text(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / "reference.py"
            self.assertEqual(load_generated_text(script, "hello"), ("", ""))

    def test_worker_runs_selected_script_with_same_request(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "reference.py"
            script.write_text(
                "import argparse, json\n"
                "from pathlib import Path\n"
                "p = argparse.ArgumentParser()\n"
                "p.add_argument('--prompt', required=True)\n"
                "p.add_argument('--max-new-tokens', type=int, required=True)\n"
                "a = p.parse_args()\n"
                "out = Path(__file__).parent / 'demo_outputs'\n"
                "out.mkdir(exist_ok=True)\n"
                "text = a.prompt + ('x' * a.max_new_tokens)\n"
                "(out / 'last_token_run.json').write_text(json.dumps({\n"
                "    'int8_text': text, 'fp32_text': a.prompt + 'f'\n"
                "}), encoding='utf-8')\n"
                "print(text)\n",
                encoding="utf-8",
            )
            events: queue.Queue[tuple[str, object]] = queue.Queue()
            worker = PcReferenceWorker(events)
            worker.start(17, sys.executable, str(script), "hello", 3)
            progress_lines: list[str] = []
            while True:
                event, payload = events.get(timeout=10)
                if event == "pc_progress":
                    progress_lines.append(payload["line"])
                    continue
                self.assertEqual(event, "pc_done")
                break
            self.assertIn("helloxxx", progress_lines)
            self.assertEqual(payload["request_id"], 17)
            self.assertEqual(payload["return_code"], 0)
            self.assertEqual(payload["generated_text"], "xxx")
            self.assertEqual(payload["fp32_text"], "f")


if __name__ == "__main__":
    unittest.main()
