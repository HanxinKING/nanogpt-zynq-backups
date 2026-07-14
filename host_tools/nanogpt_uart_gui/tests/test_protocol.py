from __future__ import annotations

import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from protocol import ProtocolError, ResponseTracker, build_command, effective_output_limit


class ProtocolTests(unittest.TestCase):
    def test_default_command_shape(self) -> None:
        self.assertEqual(build_command("hello world", 8), b"8:hello world\r")

    def test_maximum_command_shape(self) -> None:
        self.assertEqual(build_command("hello world", 256), b"256:hello world\r")

    def test_context_limit(self) -> None:
        prompt = "a" * 100
        self.assertEqual(effective_output_limit(prompt), 156)
        self.assertEqual(build_command(prompt, 256), b"256:" + b"a" * 100 + b"\r")
        with self.assertRaises(ProtocolError):
            build_command(prompt, 257)

    def test_longest_valid_prompt(self) -> None:
        prompt = "a" * 255
        self.assertEqual(effective_output_limit(prompt), 1)
        self.assertEqual(build_command(prompt, 256), b"256:" + b"a" * 255 + b"\r")
        with self.assertRaises(ProtocolError):
            build_command("a" * 256, 1)

    def test_non_ascii_rejected(self) -> None:
        with self.assertRaises(ProtocolError):
            build_command("你好", 8)

    def test_streamed_response(self) -> None:
        tracker = ResponseTracker()
        first = tracker.feed("hello world\r\nout")
        self.assertFalse(first.complete)
        second = tracker.feed("put:  the")
        self.assertEqual(second.text, " the")
        final = tracker.feed(" sea\r\n> ")
        self.assertTrue(final.complete)
        self.assertEqual(final.text, " the sea")
        self.assertEqual(final.generated_tokens, 8)


if __name__ == "__main__":
    unittest.main()
