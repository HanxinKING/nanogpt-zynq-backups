from __future__ import annotations

from collections import Counter
from typing import Sequence


UINT32_MASK = 0xFFFFFFFF


def xorshift32(state: int) -> int:
    state &= UINT32_MASK
    if state == 0:
        state = 1
    state ^= (state << 13) & UINT32_MASK
    state ^= state >> 17
    state ^= (state << 5) & UINT32_MASK
    return state & UINT32_MASK


def completes_repeated_ngram(history: Sequence[int], token: int, ngram_size: int) -> bool:
    if ngram_size <= 1 or len(history) + 1 < ngram_size:
        return False
    candidate = tuple(history[-(ngram_size - 1) :]) + (int(token),)
    for start in range(len(history) - ngram_size + 1):
        if tuple(history[start : start + ngram_size]) == candidate:
            return True
    return False


def select_topk_integer(
    scores: Sequence[int],
    history: Sequence[int],
    *,
    top_k: int = 5,
    temperature_q8: int = 256,
    repeat_penalty_q8: int = 192,
    repeat_window: int = 48,
    no_repeat_ngram: int = 6,
    rng_state: int = 1337,
    deterministic: bool = False,
) -> tuple[int, int, dict[str, object]]:
    if not scores:
        raise ValueError("scores must not be empty")
    if top_k <= 0:
        raise ValueError("top_k must be positive")
    if temperature_q8 <= 0:
        raise ValueError("temperature_q8 must be positive")

    k = min(int(top_k), len(scores))
    ranked = sorted(range(len(scores)), key=lambda token: (-int(scores[token]), token))[:k]
    raw_top = int(scores[ranked[0]])
    raw_bottom = int(scores[ranked[-1]])
    spread = max(raw_top - raw_bottom, 1)
    penalty_unit = max((spread * max(int(repeat_penalty_q8), 0)) >> 8, 1)
    recent = list(history[-max(int(repeat_window), 0) :]) if repeat_window > 0 else []
    counts = Counter(int(token) for token in recent)

    candidates: list[dict[str, int | bool]] = []
    for token in ranked:
        repeat_count = counts.get(token, 0)
        banned = completes_repeated_ngram(history, token, int(no_repeat_ngram))
        adjusted = int(scores[token]) - repeat_count * penalty_unit
        candidates.append(
            {
                "token": token,
                "raw_score": int(scores[token]),
                "repeat_count": repeat_count,
                "adjusted_score": adjusted,
                "banned": banned,
            }
        )

    allowed = [candidate for candidate in candidates if not bool(candidate["banned"])]
    if not allowed:
        allowed = candidates
    allowed.sort(key=lambda candidate: (-int(candidate["adjusted_score"]), int(candidate["token"])))
    best_adjusted = int(allowed[0]["adjusted_score"])

    if deterministic:
        selected = int(allowed[0]["token"])
        trace: dict[str, object] = {
            "selected": selected,
            "rng_state": int(rng_state) & UINT32_MASK,
            "draw": 0,
            "total_weight": 0,
            "spread": spread,
            "penalty_unit": penalty_unit,
            "deterministic": True,
            "candidates": candidates,
        }
        return selected, int(rng_state) & UINT32_MASK, trace

    total_weight = 0
    for candidate in allowed:
        gap = max(best_adjusted - int(candidate["adjusted_score"]), 0)
        gap_q8 = (gap << 8) // spread
        tempered_gap_q8 = (gap_q8 << 8) // int(temperature_q8)
        weight = max(1, 256 - tempered_gap_q8)
        candidate["weight"] = weight
        total_weight += weight

    next_state = xorshift32(int(rng_state))
    draw = next_state % total_weight
    selected = int(allowed[-1]["token"])
    cursor = 0
    for candidate in allowed:
        cursor += int(candidate["weight"])
        if draw < cursor:
            selected = int(candidate["token"])
            break

    trace: dict[str, object] = {
        "selected": selected,
        "rng_state": next_state,
        "draw": draw,
        "total_weight": total_weight,
        "spread": spread,
        "penalty_unit": penalty_unit,
        "deterministic": False,
        "candidates": candidates,
    }
    return selected, next_state, trace
