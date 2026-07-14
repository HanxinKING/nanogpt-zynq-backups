from datetime import datetime
from pathlib import Path
import tempfile
import unittest

from app import APP_NAME, DEFAULT_PC_SCRIPT, NanoGptHostApp, build_log_header, normalize_script_path


class AppHelperTests(unittest.TestCase):
    def test_export_header_is_written_once(self) -> None:
        header = build_log_header("COM11", "115200", datetime(2026, 7, 13, 20, 37, 42))

        self.assertEqual(header.count(APP_NAME), 1)
        self.assertEqual(header.count("导出时间:"), 1)
        self.assertEqual(header.count("="), 72)
        self.assertTrue(header.endswith("=" * 72 + "\n"))

    def test_pasted_quoted_script_path_is_normalized(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / "reference model.py"
            script.write_text("", encoding="utf-8")
            self.assertEqual(normalize_script_path(f'  "{script}"  '), str(script.resolve()))

    def test_fixed_pc_reference_and_streamed_output(self) -> None:
        self.assertTrue(DEFAULT_PC_SCRIPT.is_file())
        self.assertEqual(
            NanoGptHostApp._streamed_output("INT8 完整输出: 'hello world the'", "INT8 完整输出:"),
            "hello world the",
        )


if __name__ == "__main__":
    unittest.main()
