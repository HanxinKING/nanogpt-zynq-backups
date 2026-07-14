from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "ps" / "build"
EMB = ROOT / "reference" / "ps_ddr_embedding_tables"

PROMPT = "hello world"
D_MODEL = 384
BLOCK_SIZE = 256
VOCAB_SIZE = 65
SPACE_TOKEN = 1

STOI = {ch: i for i, ch in enumerate(
    "\n !$&',-.3:;?ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
)}


def s8(value: int) -> int:
    return value - 256 if value >= 128 else value


def u8_from_s8(value: int) -> int:
    return value & 0xFF


def clamp_i8(value: int) -> int:
    if value > 127:
        return 127
    if value < -128:
        return -128
    return value


def main() -> int:
    got_path = BUILD / "embedding_hidden_dump.bin"
    if not got_path.exists():
        raise SystemExit(f"missing dump: {got_path}")

    tok_emb = (EMB / "token_embedding_i8.bin").read_bytes()
    pos_emb = (EMB / "position_embedding_i8.bin").read_bytes()
    got = got_path.read_bytes()

    expected = bytearray(BLOCK_SIZE * D_MODEL)
    tokens = [STOI.get(ch, SPACE_TOKEN) for ch in PROMPT]
    for pos in range(BLOCK_SIZE):
        tok = tokens[pos] if pos < len(tokens) else SPACE_TOKEN
        for dim in range(D_MODEL):
            tv = s8(tok_emb[tok * D_MODEL + dim])
            pv = s8(pos_emb[pos * D_MODEL + dim])
            expected[pos * D_MODEL + dim] = u8_from_s8(clamp_i8(tv + pv))

    mismatch = 0
    first = -1
    for i, (g, e) in enumerate(zip(got, expected)):
        if g != e:
            mismatch += 1
            if first < 0:
                first = i
                first_got = g
                first_exp = e

    print(f"EMBED_COMPARE bytes={len(expected)} mismatch={mismatch} first={first}")
    if first >= 0:
        print(f"FIRST got=0x{first_got:02x} expected=0x{first_exp:02x}")
    print("TOKENS", tokens)
    return 0 if mismatch == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
