from __future__ import annotations

from dataclasses import dataclass


MAX_CONTEXT_TOKENS = 256
MAX_OUTPUT_TOKENS = 256
DEFAULT_OUTPUT_TOKENS = 8


class ProtocolError(ValueError):
    pass


def validate_prompt(prompt: str) -> str:
    prompt = prompt.strip("\r\n")
    if not prompt:
        raise ProtocolError("请输入英文提示词。")
    if "\r" in prompt or "\n" in prompt:
        raise ProtocolError("串口协议每次只接受一行输入。")
    try:
        encoded = prompt.encode("ascii")
    except UnicodeEncodeError as exc:
        raise ProtocolError("当前 Shakespeare 模型只支持 ASCII 英文字符。") from exc
    if any(byte < 32 or byte > 126 for byte in encoded):
        raise ProtocolError("输入中包含模型不支持的控制字符。")
    if len(encoded) >= MAX_CONTEXT_TOKENS:
        raise ProtocolError("输入必须少于 256 个字符。")
    return prompt


def effective_output_limit(prompt: str) -> int:
    prompt = validate_prompt(prompt)
    return min(MAX_OUTPUT_TOKENS, MAX_CONTEXT_TOKENS - len(prompt.encode("ascii")))


def build_command(prompt: str, requested_tokens: int) -> bytes:
    prompt = validate_prompt(prompt)
    if requested_tokens < 1 or requested_tokens > MAX_OUTPUT_TOKENS:
        raise ProtocolError("输出 token 数必须在 1 到 256 之间。")
    return f"{requested_tokens}:{prompt}\r".encode("ascii")


@dataclass(frozen=True)
class GenerationResult:
    text: str
    generated_tokens: int
    complete: bool


class ResponseTracker:
    """Extract streamed model text from `output: ...\n> ` responses."""

    def __init__(self) -> None:
        self._raw = ""

    def reset(self) -> None:
        self._raw = ""

    def feed(self, text: str) -> GenerationResult:
        self._raw += text
        normalized = self._raw.replace("\r\n", "\n").replace("\r", "\n")
        marker = "output: "
        start = normalized.find(marker)
        if start < 0:
            return GenerationResult("", 0, False)

        payload = normalized[start + len(marker) :]
        complete = payload.endswith("\n> ") or payload.endswith("\n>")
        if complete:
            payload = payload.rsplit("\n>", 1)[0]
        return GenerationResult(payload, len(payload), complete)
