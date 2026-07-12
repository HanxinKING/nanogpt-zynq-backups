#include <stdint.h>
#include "../../../generated/int8_alignment/hardware_params/ps_bittrue_params.h"

#define PL_BASE            0x40000000u
#define REG_CONTROL        0x00u
#define REG_STATUS         0x04u
#define REG_MODE           0x30u
#define REG_FULL_INPUT     0x40u
#define REG_FULL_OUTPUT    0x44u
#define REG_FULL_WEIGHTS   0x48u
#define REG_FULL_SCALES    0x4cu
#define REG_FULL_DEBUG     0x50u
#define REG_FULL_STATUS    0x54u
#define REG_FULL_STAGE     0x58u
#define REG_HLS_SIGNATURE  0x60u
#define REG_ARGMAX_BASE    0x64u
#define REG_FFN_MID_SHIFT  0x68u
#define REG_FFN_SHIFT      0x6cu
#define REG_ATTN_LAYER     0x70u
#define REG_UART_STATUS    0x74u
#define REG_UART_RX_DATA   0x78u
#define REG_UART_TX_DATA   0x7cu
#define REG_ACTIVE_ROWS    0x80u
#define REG_ROW_START      0x84u

#define CTRL_START         0x00000001u
#define CTRL_CLEAR         0x00000002u

#define MODE_MATMUL_LN     0x00000003u
#define MODE_ATTN          0x00000004u
#define MODE_RES1          0x00000008u
#define MODE_LN            0x00000010u
#define MODE_FFN_FINAL     0x00000040u
#define MODE_LM_HEAD       0x00000080u
#define MODE_LM_HEAD_FAST  0x00000400u
#define MODE_FFN_ONLY      0x00000020u
#define MODE_PROJ_ONLY     0x00000208u

#define LAYER_A_BASE       0x10000000u
#define LAYER_B_BASE       0x10020000u
#define QBUF_BASE          0x10040000u
#define KBUF_BASE          0x10060000u
#define VBUF_BASE          0x10080000u
#define ATTNBUF_BASE       0x100A0000u
#define RES1BUF_BASE       0x100C0000u
#define LN2BUF_BASE        0x100E0000u
#define LN_F_BASE          0x10120000u
#define WEIGHTS_BASE       0x11000000u
#define DEBUG_BASE         0x12E00000u
#define ARGMAX_OUT_BASE    0x10140000u
#define K_CACHE_BASE       0x10200000u
#define V_CACHE_BASE       0x10400000u
#define KV_CACHE_STRIDE    0x00020000u
#define TOK_EMB_I8_BASE    0x13000000u
#define POS_EMB_I8_BASE    0x13010000u
#define TOK_EMB_SCALE_Q30_BASE 0x13028000u
#define POS_EMB_SCALE_Q30_BASE 0x13028400u
#define MAILBOX_BASE       0x00020000u
#define GLOBAL_TIMER_BASE  0xF8F00200u

/* Profiling words are outside the normal command/result mailbox layout. */
#define PROFILE_BASE_WORD  0x500u
#define PROFILE_LAYER_WORDS 16u
#define PROFILE_LM_WORD    0x560u
#define PROFILE_EMBED_WORD 0x561u
#define PROFILE_GUARD_WORD 0x562u

#define UART_STATUS_RX_VALID 0x00000001u
#define UART_STATUS_TX_READY 0x00000002u
#define UART_STATUS_SIGNATURE 0x55000000u

#define CMD_FULL           0u
#define CMD_EMBED_ONLY     1u
#define CMD_FULL6_ONLY     2u
#define CMD_LN1_ONLY       3u
#define CMD_LN1_JTAG_INPUT 4u
#define CMD_LAYER0_ONLY    5u

#define LAYER_STRIDE       0x001B0000u
#define OFF_WQ             0x000000u
#define OFF_WK             0x024000u
#define OFF_WV             0x048000u
#define OFF_WO             0x06C000u
#define OFF_W1             0x090000u
#define OFF_LM_HEAD        0x00A20000u

#define BLOCK_SIZE         256u
#define VOCAB_SIZE         65u
#define D_MODEL            384u
#define SPACE_TOKEN        1u
#define DEFAULT_MAX_NEW_TOKENS 8u
#define MAX_NEW_TOKENS     200u
#define MAILBOX_TOKEN_WORD_BASE 0x100u
#define MAILBOX_CHAR_WORD_BASE  0x240u
#define POLL_LIMIT         10000000u
#define START_GUARD_CYCLES 1000u
#define POLL_BACKOFF_CYCLES 1000u
#define MAGIC              0x4E475054u

static const char g_itos[VOCAB_SIZE] = {
    '\n', ' ', '!', '$', '&', '\'', ',', '-', '.', '3', ':', ';', '?',
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
    'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
};

static const uint32_t q_shifts[6] = {13u, 12u, 12u, 12u, 12u, 12u};
static const uint32_t k_shifts[6] = {13u, 13u, 13u, 12u, 12u, 12u};
static const uint32_t v_shifts[6] = {13u, 13u, 12u, 12u, 12u, 12u};
static const uint32_t attn_proj_shifts[6] = {10u, 10u, 11u, 10u, 10u, 10u};
static const uint32_t ffn_mid_shifts[6] = {13u, 13u, 13u, 12u, 12u, 13u};
static const uint32_t ffn_shifts[6] = {11u, 11u, 11u, 12u, 11u, 10u};

static inline void wr32(uint32_t addr, uint32_t value) { *(volatile uint32_t *)addr = value; }
static inline uint32_t rd32(uint32_t addr) { return *(volatile uint32_t *)addr; }
static inline void barrier(void) { __asm__ volatile ("dsb sy\nisb sy" ::: "memory"); }
static uint32_t g_uart_console;
static uint32_t g_active_rows = BLOCK_SIZE;
static uint32_t g_row_start;

static void mailbox_write(uint32_t index, uint32_t value);

static uint64_t global_timer_read(void)
{
    uint32_t high_before;
    uint32_t low;
    uint32_t high_after;

    do {
        high_before = rd32(GLOBAL_TIMER_BASE + 4u);
        low = rd32(GLOBAL_TIMER_BASE);
        high_after = rd32(GLOBAL_TIMER_BASE + 4u);
    } while (high_before != high_after);
    return ((uint64_t)high_after << 32) | low;
}

static void profile_stage(uint32_t layer, uint32_t stage, uint64_t started)
{
    mailbox_write(PROFILE_BASE_WORD + layer * PROFILE_LAYER_WORDS + stage,
                  (uint32_t)(global_timer_read() - started));
}

static void uart_init(void)
{
    wr32(PL_BASE + REG_UART_STATUS, 1u);
    barrier();
    while ((rd32(PL_BASE + REG_UART_STATUS) & 0xff000000u) != UART_STATUS_SIGNATURE) {}
}

static void uart_putc(char c)
{
    while ((rd32(PL_BASE + REG_UART_STATUS) & UART_STATUS_TX_READY) == 0u) {}
    wr32(PL_BASE + REG_UART_TX_DATA, (uint32_t)(uint8_t)c);
}

static char uart_getc(void)
{
    while ((rd32(PL_BASE + REG_UART_STATUS) & UART_STATUS_RX_VALID) == 0u) {}
    return (char)(rd32(PL_BASE + REG_UART_RX_DATA) & 0xffu);
}

static void uart_puts(const char *s)
{
    while (*s != '\0') {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

static void delay_cycles(uint32_t cycles)
{
    volatile uint32_t i;
    for (i = 0; i < cycles; ++i) {
        __asm__ volatile ("nop");
    }
}

static int encode_char(char c)
{
    if (c == '\n') return 0;
    if (c == ' ') return 1;
    if (c == '!') return 2;
    if (c == '$') return 3;
    if (c == '&') return 4;
    if (c == '\'') return 5;
    if (c == ',') return 6;
    if (c == '-') return 7;
    if (c == '.') return 8;
    if (c == '3') return 9;
    if (c == ':') return 10;
    if (c == ';') return 11;
    if (c == '?') return 12;
    if (c >= 'A' && c <= 'Z') return 13 + (c - 'A');
    if (c >= 'a' && c <= 'z') return 39 + (c - 'a');
    return -1;
}

static int8_t clamp_i8(int32_t value)
{
    if (value > 127) return 127;
    if (value < -128) return -128;
    return (int8_t)value;
}

static int8_t read_s8(uint32_t addr)
{
    uint32_t word = rd32(addr & ~3u);
    uint32_t shift = (addr & 3u) * 8u;
    return (int8_t)((word >> shift) & 0xffu);
}

static int32_t read_s32(uint32_t addr)
{
    return (int32_t)rd32(addr);
}

static uint32_t round_embedding_ratio(int32_t value, uint32_t max_abs)
{
    uint32_t absolute = (value < 0) ? (uint32_t)(-value) : (uint32_t)value;
    uint64_t numerator = ((uint64_t)absolute * 127u) + (max_abs >> 1);
    uint32_t quotient = 0u;
    int32_t bit;

    for (bit = 7; bit >= 0; --bit) {
        uint64_t shifted = ((uint64_t)max_abs) << (uint32_t)bit;
        if (numerator >= shifted) {
            numerator -= shifted;
            quotient |= 1u << (uint32_t)bit;
        }
    }
    if (quotient > 127u) quotient = 127u;
    return (value < 0) ? (uint32_t)(uint8_t)(-(int32_t)quotient) : quotient;
}

static void mailbox_write(uint32_t index, uint32_t value)
{
    wr32(MAILBOX_BASE + (index << 2), value);
}

static uint32_t mailbox_read(uint32_t index)
{
    return rd32(MAILBOX_BASE + (index << 2));
}

static uint32_t embedding_max_abs(const uint16_t *tokens, uint32_t n)
{
    uint32_t pos;
    uint32_t max_abs = 1u;

    for (pos = 0; pos < BLOCK_SIZE; ++pos) {
        uint16_t token = (pos < n) ? tokens[pos] : SPACE_TOKEN;
        int32_t token_scale;
        int32_t position_scale;
        uint32_t dim;
        if (token >= VOCAB_SIZE) token = SPACE_TOKEN;
        token_scale = read_s32(TOK_EMB_SCALE_Q30_BASE + ((uint32_t)token << 2));
        position_scale = read_s32(POS_EMB_SCALE_Q30_BASE + (pos << 2));
        for (dim = 0; dim < D_MODEL; ++dim) {
            int32_t tok = read_s8(TOK_EMB_I8_BASE + ((uint32_t)token * D_MODEL) + dim);
            int32_t posv = read_s8(POS_EMB_I8_BASE + (pos * D_MODEL) + dim);
            int32_t value = (tok * token_scale) + (posv * position_scale);
            uint32_t absolute = (value < 0) ? (uint32_t)(-value) : (uint32_t)value;
            if (absolute > max_abs) max_abs = absolute;
        }
    }

    return max_abs;
}

static void build_hidden_range_scaled(const uint16_t *tokens, uint32_t n,
                                      uint32_t row_start, uint32_t row_count,
                                      uint32_t max_abs)
{
    uint32_t pos;
    uint32_t row_end = row_start + row_count;

    if (row_end > BLOCK_SIZE) row_end = BLOCK_SIZE;

    for (pos = row_start; pos < row_end; ++pos) {
        uint16_t token = (pos < n) ? tokens[pos] : SPACE_TOKEN;
        int32_t token_scale;
        int32_t position_scale;
        uint32_t dim;
        if (token >= VOCAB_SIZE) token = SPACE_TOKEN;
        token_scale = read_s32(TOK_EMB_SCALE_Q30_BASE + ((uint32_t)token << 2));
        position_scale = read_s32(POS_EMB_SCALE_Q30_BASE + (pos << 2));
        for (dim = 0; dim < D_MODEL; dim += 4u) {
            uint32_t packed = 0u;
            uint32_t lane;
            for (lane = 0; lane < 4u; ++lane) {
                uint32_t d = dim + lane;
                int32_t tok = read_s8(TOK_EMB_I8_BASE + ((uint32_t)token * D_MODEL) + d);
                int32_t posv = read_s8(POS_EMB_I8_BASE + (pos * D_MODEL) + d);
                int32_t value = (tok * token_scale) + (posv * position_scale);
                packed |= (round_embedding_ratio(value, max_abs) & 0xffu) << (lane * 8u);
            }
            wr32(LAYER_A_BASE + (pos * D_MODEL) + dim, packed);
        }
    }
    barrier();
}

static void build_hidden(const uint16_t *tokens, uint32_t n)
{
    uint32_t max_abs = embedding_max_abs(tokens, n);
    build_hidden_range_scaled(tokens, n, 0u, BLOCK_SIZE, max_abs);
}

static uint32_t isqrt_u64(uint64_t value)
{
    uint64_t result = 0u;
    uint64_t bit = (uint64_t)1u << 62;

    while (bit > value) bit >>= 2;
    while (bit != 0u) {
        if (value >= result + bit) {
            value -= result + bit;
            result = (result >> 1) + bit;
        } else {
            result >>= 1;
        }
        bit >>= 2;
    }
    return (uint32_t)result;
}

static int32_t round_div_s64_u64_small(int64_t numerator, uint64_t denominator)
{
    uint64_t absolute;
    uint32_t quotient = 0u;
    int32_t bit;

    if (denominator == 0u) return 0;
    absolute = (numerator < 0) ? (uint64_t)(-numerator) : (uint64_t)numerator;
    absolute += denominator >> 1;
    for (bit = 7; bit >= 0; --bit) {
        uint64_t shifted = denominator << (uint32_t)bit;
        if (absolute >= shifted) {
            absolute -= shifted;
            quotient |= 1u << (uint32_t)bit;
        }
    }
    if (quotient > 127u) quotient = 127u;
    return (numerator < 0) ? -(int32_t)quotient : (int32_t)quotient;
}

static void ps_layernorm(uint32_t input_base, uint32_t output_base,
                         uint32_t coefficient_base, uint32_t rows)
{
    uint32_t row;
    for (row = 0u; row < rows; ++row) {
        int32_t sum = 0;
        uint32_t square_sum = 0u;
        uint32_t dim;
        uint64_t variance_numerator;
        uint32_t sqrt_q16;
        uint64_t denominator_q24;

        for (dim = 0u; dim < D_MODEL; ++dim) {
            int32_t value = (int32_t)read_s8(input_base + row * D_MODEL + dim);
            sum += value;
            square_sum += (uint32_t)(value * value);
        }
        variance_numerator = ((uint64_t)D_MODEL * square_sum) - ((int64_t)sum * sum);
        if (variance_numerator == 0u) variance_numerator = 1u;
        sqrt_q16 = isqrt_u64(variance_numerator << 32);
        denominator_q24 = ((uint64_t)sqrt_q16) << 8;
        if (row == 0u && rows == BLOCK_SIZE) {
            mailbox_write(0x300u, (uint32_t)sum);
            mailbox_write(0x301u, square_sum);
            mailbox_write(0x302u, (uint32_t)variance_numerator);
            mailbox_write(0x303u, (uint32_t)(variance_numerator >> 32));
            mailbox_write(0x304u, sqrt_q16);
            mailbox_write(0x305u, (uint32_t)denominator_q24);
            mailbox_write(0x306u, (uint32_t)(denominator_q24 >> 32));
        }

        for (dim = 0u; dim < D_MODEL; dim += 4u) {
            uint32_t packed = 0u;
            uint32_t lane;
            for (lane = 0u; lane < 4u; ++lane) {
                uint32_t d = dim + lane;
                int32_t value = (int32_t)read_s8(input_base + row * D_MODEL + d);
                int32_t centered = (int32_t)D_MODEL * value - sum;
                int32_t coefficient = read_s32(coefficient_base + (d << 2));
                int64_t numerator = (int64_t)centered * coefficient;
                int32_t quantized = round_div_s64_u64_small(numerator, denominator_q24);
                packed |= ((uint32_t)(uint8_t)clamp_i8(quantized)) << (lane * 8u);
            }
            wr32(output_base + row * D_MODEL + dim, packed);
        }
    }
    barrier();
}

static int8_t requant_add_q30(int8_t a, uint32_t a_mult,
                              int8_t b, uint32_t b_mult)
{
    int64_t scaled = ((int64_t)a * (int64_t)a_mult) + ((int64_t)b * (int64_t)b_mult);
    int64_t rounded;
    if (scaled >= 0) rounded = (scaled + ((int64_t)1 << 29)) >> 30;
    else rounded = -(((-scaled) + ((int64_t)1 << 29)) >> 30);
    return clamp_i8((int32_t)rounded);
}

static void ps_residual_add(uint32_t a_base, uint32_t b_base, uint32_t output_base,
                            uint32_t rows, uint32_t a_mult, uint32_t b_mult)
{
    uint32_t offset;
    for (offset = 0u; offset < rows * D_MODEL; offset += 4u) {
        uint32_t packed = 0u;
        uint32_t lane;
        for (lane = 0u; lane < 4u; ++lane) {
            int8_t a = read_s8(a_base + offset + lane);
            int8_t b = read_s8(b_base + offset + lane);
            int8_t value = requant_add_q30(a, a_mult, b, b_mult);
            packed |= ((uint32_t)(uint8_t)value) << (lane * 8u);
        }
        wr32(output_base + offset, packed);
    }
    barrier();
}

static int wait_done(uint32_t stage_mask)
{
    uint32_t i;
    uint32_t busy_seen = 0u;
    for (i = 0; i < POLL_LIMIT; ++i) {
        uint32_t status = rd32(PL_BASE + REG_STATUS);
        if ((status & 0x4u) != 0u) return -2;
        if ((status & 0x2u) != 0u) busy_seen = 1u;
        if (busy_seen != 0u && (status & 0x1u) != 0u) {
            uint32_t stage = rd32(PL_BASE + REG_FULL_STAGE);
            return ((stage & stage_mask) == stage_mask) ? 0 : -3;
        }
        if ((i & 0x3ffu) == 0u) {
            mailbox_write(4, status);
            mailbox_write(5, rd32(PL_BASE + REG_FULL_STATUS));
            mailbox_write(6, rd32(PL_BASE + REG_FULL_STAGE));
            mailbox_write(7, rd32(PL_BASE + REG_HLS_SIGNATURE));
        }
        delay_cycles(POLL_BACKOFF_CYCLES);
    }
    return -1;
}

static int run_mode(uint32_t mode, uint32_t input, uint32_t output, uint32_t weight,
                    uint32_t reg4c, uint32_t reg50, uint32_t stage_mask,
                    uint32_t reg64, uint32_t reg68, uint32_t reg6c)
{
    wr32(PL_BASE + REG_CONTROL, CTRL_CLEAR);
    barrier();
    delay_cycles(START_GUARD_CYCLES);
    wr32(PL_BASE + REG_MODE, mode);
    wr32(PL_BASE + REG_FULL_INPUT, input);
    wr32(PL_BASE + REG_FULL_OUTPUT, output);
    wr32(PL_BASE + REG_FULL_WEIGHTS, weight);
    wr32(PL_BASE + REG_FULL_SCALES, reg4c);
    wr32(PL_BASE + REG_FULL_DEBUG, reg50);
    wr32(PL_BASE + REG_ACTIVE_ROWS, g_active_rows);
    wr32(PL_BASE + REG_ROW_START, g_row_start);
    if (reg64 != 0u) wr32(PL_BASE + REG_ARGMAX_BASE, reg64);
    if (reg68 != 0u) wr32(PL_BASE + REG_FFN_MID_SHIFT, reg68);
    if (reg6c != 0u) wr32(PL_BASE + REG_FFN_SHIFT, reg6c);
    barrier();
    wr32(PL_BASE + REG_CONTROL, CTRL_START);
    return wait_done(stage_mask);
}

static int run_attn(uint32_t layer, uint32_t k_cache, uint32_t v_cache)
{
    wr32(PL_BASE + REG_CONTROL, CTRL_CLEAR);
    barrier();
    delay_cycles(START_GUARD_CYCLES);
    wr32(PL_BASE + REG_MODE, MODE_ATTN);
    wr32(PL_BASE + REG_FULL_OUTPUT, ATTNBUF_BASE);
    wr32(PL_BASE + REG_FULL_WEIGHTS, QBUF_BASE);
    wr32(PL_BASE + REG_FULL_SCALES, k_cache);
    wr32(PL_BASE + REG_FULL_DEBUG, v_cache);
    wr32(PL_BASE + REG_ATTN_LAYER, layer);
    wr32(PL_BASE + REG_ACTIVE_ROWS, g_active_rows);
    wr32(PL_BASE + REG_ROW_START, g_row_start);
    barrier();
    wr32(PL_BASE + REG_CONTROL, CTRL_START);
    return wait_done(0x7u);
}

static int run_layer(uint32_t layer)
{
    uint32_t input = (layer & 1u) ? LAYER_B_BASE : LAYER_A_BASE;
    uint32_t output = (layer & 1u) ? LAYER_A_BASE : LAYER_B_BASE;
    uint32_t wbase = WEIGHTS_BASE + (layer * LAYER_STRIDE);
    uint32_t k_cache = K_CACHE_BASE + (layer * KV_CACHE_STRIDE);
    uint32_t v_cache = V_CACHE_BASE + (layer * KV_CACHE_STRIDE);
    uint32_t row_offset = g_row_start * D_MODEL;
    uint32_t row_count = g_active_rows - g_row_start;
    uint64_t started;
    int rc;

    mailbox_write(8, layer);
    wr32(PL_BASE + REG_ATTN_LAYER, layer);
    started = global_timer_read();
    ps_layernorm(input + row_offset, LN2BUF_BASE + row_offset,
                 BITTRUE_LN_COEFF_BASE + (layer * 2u) * BITTRUE_LN_STAGE_BYTES,
                 row_count);
    profile_stage(layer, 0u, started);
    started = global_timer_read();
    rc = run_mode(MODE_MATMUL_LN, LN2BUF_BASE, QBUF_BASE, wbase + OFF_WQ, 0u,
                  DEBUG_BASE + 1u, 0x3u, 0u, 0u, 0u);
    profile_stage(layer, 1u, started);
    if (rc) return rc;
    started = global_timer_read();
    rc = run_mode(MODE_MATMUL_LN, LN2BUF_BASE, k_cache, wbase + OFF_WK, 0u,
                  DEBUG_BASE + 2u, 0x3u, 0u, 0u, 0u);
    profile_stage(layer, 2u, started);
    if (rc) return rc;
    started = global_timer_read();
    rc = run_mode(MODE_MATMUL_LN, LN2BUF_BASE, v_cache, wbase + OFF_WV, 0u,
                  DEBUG_BASE + 3u, 0x3u, 0u, 0u, 0u);
    profile_stage(layer, 3u, started);
    if (rc) return rc;
    started = global_timer_read();
    rc = run_attn(layer, k_cache, v_cache);
    profile_stage(layer, 4u, started);
    if (rc) return rc;
    started = global_timer_read();
    rc = run_mode(MODE_PROJ_ONLY, ATTNBUF_BASE, RES1BUF_BASE, wbase + OFF_WO,
                  0u, 0u, 0xfu, 0u, 0u, 0u);
    profile_stage(layer, 5u, started);
    if (rc) return rc;
    started = global_timer_read();
    ps_residual_add(input + row_offset, RES1BUF_BASE + row_offset,
                    RES1BUF_BASE + row_offset, row_count,
                    g_res1_input_mult_q30[layer], g_res1_proj_mult_q30[layer]);
    profile_stage(layer, 6u, started);
    started = global_timer_read();
    ps_layernorm(RES1BUF_BASE + row_offset, LN2BUF_BASE + row_offset,
                 BITTRUE_LN_COEFF_BASE + (layer * 2u + 1u) * BITTRUE_LN_STAGE_BYTES,
                 row_count);
    profile_stage(layer, 7u, started);
    started = global_timer_read();
    rc = run_mode(MODE_FFN_ONLY, LN2BUF_BASE, output, wbase + OFF_W1,
                  0u, 0u, 0x3fu, 0u, 0u, 0u);
    profile_stage(layer, 8u, started);
    if (rc) return rc;
    started = global_timer_read();
    ps_residual_add(RES1BUF_BASE + row_offset, output + row_offset,
                    output + row_offset, row_count,
                    g_final_res1_mult_q30[layer], g_final_ffn_mult_q30[layer]);
    profile_stage(layer, 9u, started);
    return 0;
}

static int run_full_model_range(uint32_t active_rows, uint32_t row_start)
{
    uint32_t layer;
    if (active_rows == 0u || active_rows > BLOCK_SIZE || row_start >= active_rows) return -4;
    g_active_rows = active_rows;
    g_row_start = row_start;
    wr32(PL_BASE + REG_ACTIVE_ROWS, active_rows);
    wr32(PL_BASE + REG_ROW_START, row_start);
    for (layer = 0; layer < 6u; ++layer) {
        int rc = run_layer(layer);
        if (rc) return rc;
    }
    return 0;
}

static int run_full_model(uint32_t active_rows)
{
    return run_full_model_range(active_rows, 0u);
}

static int run_layer0_ln1_only(void)
{
    mailbox_write(8, 0u);
    ps_layernorm(LAYER_A_BASE, LN2BUF_BASE, BITTRUE_LN_COEFF_BASE, BLOCK_SIZE);
    return 0;
}

static int32_t div_toward_zero(int32_t value, int32_t denom)
{
    if (value < 0) return -((-value) / denom);
    return value / denom;
}

static int8_t center_i8(int32_t value, int32_t mean)
{
    return clamp_i8(value - mean);
}

static uint16_t __attribute__((unused)) ps_lm_head_argmax_row_reference(uint32_t row_base)
{
    int64_t best_score = -((int64_t)1 << 62);
    uint16_t best_token = 0;
    uint32_t dim;
    uint32_t vocab;

    ps_layernorm(row_base, LN_F_BASE,
                 BITTRUE_LN_COEFF_BASE + BITTRUE_LN_FINAL_STAGE * BITTRUE_LN_STAGE_BYTES,
                 1u);

    for (vocab = 0; vocab < VOCAB_SIZE; ++vocab) {
        int32_t acc = 0;
        uint32_t scale_ratio = rd32(BITTRUE_LM_SCALE_BASE + (vocab << 2));
        int64_t score;
        for (dim = 0; dim < D_MODEL; ++dim) {
            int32_t x = (int32_t)read_s8(LN_F_BASE + dim);
            int32_t w = (int32_t)read_s8(WEIGHTS_BASE + OFF_LM_HEAD + (dim * VOCAB_SIZE) + vocab);
            acc += x * w;
        }
        score = (int64_t)acc * (int64_t)scale_ratio;
        if (vocab == 0u || score > best_score) {
            best_score = score;
            best_token = (uint16_t)vocab;
        }
    }
    return best_token;
}

static int pl_lm_head_argmax_row(uint32_t row_base, uint16_t *token)
{
    uint32_t saved_active_rows = g_active_rows;
    uint32_t saved_row_start = g_row_start;
    int rc;

    ps_layernorm(row_base, LN_F_BASE,
                 BITTRUE_LN_COEFF_BASE + BITTRUE_LN_FINAL_STAGE * BITTRUE_LN_STAGE_BYTES,
                 1u);
    g_active_rows = 1u;
    g_row_start = 0u;
    rc = run_mode(MODE_LM_HEAD_FAST, LN_F_BASE, ARGMAX_OUT_BASE,
                  WEIGHTS_BASE + OFF_LM_HEAD, BITTRUE_LM_SCALE_BASE,
                  0u, 0xffu, ARGMAX_OUT_BASE, 0u, 0u);
    if (rc == 0) {
        barrier();
        *token = (uint16_t)(rd32(ARGMAX_OUT_BASE) & 0x7fu);
        if (*token >= VOCAB_SIZE) rc = -5;
    }
    g_active_rows = saved_active_rows;
    g_row_start = saved_row_start;
    return rc;
}

/*
 * Greedy character generation with per-layer K/V caches in DDR. The prompt is
 * evaluated once; later invocations update only the newly appended token row.
 */
static int generate_greedy(uint16_t *tokens, uint32_t n, uint32_t max_new_tokens)
{
    uint32_t generated = 0u;
    uint32_t row_start = 0u;
    uint32_t embed_max;
    uint64_t started;

    if (max_new_tokens == 0u || max_new_tokens > MAX_NEW_TOKENS) {
        max_new_tokens = DEFAULT_MAX_NEW_TOKENS;
    }
    if (n == 0u || n > BLOCK_SIZE) return -4;

    embed_max = embedding_max_abs(tokens, n);
    build_hidden_range_scaled(tokens, n, 0u, n, embed_max);

    while (generated < max_new_tokens && n < BLOCK_SIZE) {
        uint16_t tok;
        int rc;

        mailbox_write(13u, row_start);
        mailbox_write(14u, (row_start == 0u) ? 0u : 1u);
        mailbox_write(15u, n);
        rc = run_full_model_range(n, row_start);
        if (rc != 0) {
            mailbox_write(11u, generated);
            mailbox_write(12u, n);
            return rc;
        }

        /* A causal LM predicts the next character from the last valid row. */
        started = global_timer_read();
        rc = pl_lm_head_argmax_row(LAYER_A_BASE + ((n - 1u) * D_MODEL), &tok);
        mailbox_write(PROFILE_LM_WORD, (uint32_t)(global_timer_read() - started));
        if (rc != 0) {
            mailbox_write(11u, generated);
            mailbox_write(12u, n);
            return rc;
        }
        mailbox_write(MAILBOX_TOKEN_WORD_BASE + generated, (uint32_t)tok);
        mailbox_write(MAILBOX_CHAR_WORD_BASE + generated,
                      (tok < VOCAB_SIZE) ? (uint32_t)g_itos[tok] : (uint32_t)'?');
        if (g_uart_console != 0u) uart_putc((tok < VOCAB_SIZE) ? g_itos[tok] : '?');
        tokens[n++] = tok;
        ++generated;

        if (generated < max_new_tokens && n < BLOCK_SIZE) {
            uint32_t next_max = embedding_max_abs(tokens, n);
            started = global_timer_read();
            if (next_max == embed_max) {
                row_start = n - 1u;
                build_hidden_range_scaled(tokens, n, row_start, 1u, next_max);
            } else {
                /* A scale change invalidates old K/V values, so refresh once. */
                row_start = 0u;
                build_hidden_range_scaled(tokens, n, 0u, n, next_max);
                embed_max = next_max;
            }
            mailbox_write(PROFILE_EMBED_WORD, (uint32_t)(global_timer_read() - started));
        }
    }

    mailbox_write(11u, generated);
    mailbox_write(12u, n);
    return 0;
}

static void uart_console(void)
{
    uint16_t tokens[BLOCK_SIZE];
    char line[BLOCK_SIZE];
    uint32_t n;
    uint32_t i;
    uint32_t prompt_start;
    uint32_t requested_tokens;

    uart_init();
    g_uart_console = 1u;
    uart_puts("nanoGPT Zynq UART ready\n> ");
    for (;;) {
        n = 0u;
        while (n < BLOCK_SIZE - 1u) {
            char c = uart_getc();
            if (c == '\r' || c == '\n') break;
            if (c == 0x08 || c == 0x7f) {
                if (n != 0u) { --n; uart_puts("\b \b"); }
                continue;
            }
            if (encode_char(c) >= 0 ||
                (n < 3u && c >= '0' && c <= '9') ||
                ((n >= 1u && n <= 3u) && c == ':')) {
                line[n++] = c;
                uart_putc(c);
            }
        }
        uart_puts("\n");
        if (n == 0u) { uart_puts("> "); continue; }

        if (n >= 5u &&
            line[0] == 'e' && line[1] == 'c' && line[2] == 'h' &&
            line[3] == 'o' && line[4] == ':') {
            uart_puts("output: ");
            for (i = 5u; i < n; ++i) uart_putc(line[i]);
            uart_puts("\n> ");
            continue;
        }

        prompt_start = 0u;
        requested_tokens = DEFAULT_MAX_NEW_TOKENS;
        if (line[0] >= '1' && line[0] <= '9') {
            uint32_t parsed = 0u;
            while (prompt_start < n && line[prompt_start] >= '0' && line[prompt_start] <= '9') {
                parsed = parsed * 10u + (uint32_t)(line[prompt_start] - '0');
                ++prompt_start;
            }
            if (prompt_start >= n || line[prompt_start] != ':') {
                prompt_start = 0u;
            } else {
                ++prompt_start;
                if (parsed > 0u && parsed <= MAX_NEW_TOKENS) requested_tokens = parsed;
            }
        }
        if (prompt_start >= n) { uart_puts("> "); continue; }
        for (i = prompt_start; i < n; ++i) {
            int encoded = encode_char(line[i]);
            if (encoded < 0) break;
            tokens[i - prompt_start] = (uint16_t)encoded;
        }
        if (i != n) { uart_puts("unsupported input\n> "); continue; }
        n -= prompt_start;
        uart_puts("output: ");
        (void)generate_greedy(tokens, n, requested_tokens);
        uart_puts("\n> ");
    }
}

int main(void)
{
    uint16_t tokens[BLOCK_SIZE];
    uint32_t n = mailbox_read(2);
    uint32_t cmd = mailbox_read(9);
    uint32_t max_new_tokens = mailbox_read(10);
    uint32_t i;
    uint64_t guard_started;
    int rc;

    wr32(GLOBAL_TIMER_BASE + 8u, rd32(GLOBAL_TIMER_BASE + 8u) | 1u);
    barrier();
    guard_started = global_timer_read();
    delay_cycles(START_GUARD_CYCLES);
    mailbox_write(PROFILE_GUARD_WORD,
                  (uint32_t)(global_timer_read() - guard_started));

    /* UART-console boot is selected by a cleared mailbox word 2. */
    if (n == 0u) uart_console();

    mailbox_write(0, MAGIC);
    mailbox_write(1, 0x100u);
    mailbox_write(3, 0u);
    mailbox_write(4, 0u);
    mailbox_write(5, 0u);
    mailbox_write(6, 0u);
    mailbox_write(7, 0u);
    mailbox_write(11u, 0u);
    mailbox_write(12u, n);
    if (n == 0u || n > BLOCK_SIZE) n = 11u;

    for (i = 0; i < n; ++i) {
        char c = (char)(rd32(MAILBOX_BASE + 0x100u + (i << 2)) & 0xffu);
        int token = encode_char(c);
        if (token < 0) token = SPACE_TOKEN;
        tokens[i] = (uint16_t)token;
        mailbox_write(0x80u + i, (uint32_t)tokens[i]);
    }

    if (cmd == CMD_EMBED_ONLY || cmd == CMD_FULL6_ONLY || cmd == CMD_LN1_ONLY ||
        cmd == CMD_LAYER0_ONLY) {
        build_hidden(tokens, n);
    }
    mailbox_write(1, 0x200u);
    if (cmd == CMD_EMBED_ONLY) {
        mailbox_write(3, 0u);
        mailbox_write(4, 0u);
        mailbox_write(5, 0u);
        mailbox_write(6, 0u);
        mailbox_write(7, 0u);
        mailbox_write(1, 0x9001u);
        barrier();
        __asm__ volatile ("bkpt #0");
        for (;;) {}
    }

    if (cmd == CMD_LN1_ONLY || cmd == CMD_LN1_JTAG_INPUT) {
        rc = run_layer0_ln1_only();
        mailbox_write(3, (uint32_t)rc);
        mailbox_write(4, rd32(PL_BASE + REG_STATUS));
        mailbox_write(5, rd32(PL_BASE + REG_FULL_STATUS));
        mailbox_write(6, rd32(PL_BASE + REG_FULL_STAGE));
        mailbox_write(7, rd32(PL_BASE + REG_HLS_SIGNATURE));
        mailbox_write(1, (rc == 0) ? 0x9003u : 0xdead0000u);
        barrier();
        __asm__ volatile ("bkpt #0");
        for (;;) {}
    }

    if (cmd == CMD_FULL6_ONLY) {
        rc = run_full_model(n);
        mailbox_write(3, (uint32_t)rc);
        mailbox_write(4, rd32(PL_BASE + REG_STATUS));
        mailbox_write(5, rd32(PL_BASE + REG_FULL_STATUS));
        mailbox_write(6, rd32(PL_BASE + REG_FULL_STAGE));
        mailbox_write(7, rd32(PL_BASE + REG_HLS_SIGNATURE));
        mailbox_write(1, (rc == 0) ? 0x9002u : 0xdead0000u);
        barrier();
        __asm__ volatile ("bkpt #0");
        for (;;) {}
    }

    if (cmd == CMD_LAYER0_ONLY) {
        uint32_t layers = max_new_tokens;
        if (layers == 0u || layers > 6u) layers = 1u;
        g_active_rows = n;
        g_row_start = 0u;
        rc = 0;
        for (i = 0u; i < layers && rc == 0; ++i) rc = run_layer(i);
        mailbox_write(3, (uint32_t)rc);
        mailbox_write(4, rd32(PL_BASE + REG_STATUS));
        mailbox_write(5, rd32(PL_BASE + REG_FULL_STATUS));
        mailbox_write(6, rd32(PL_BASE + REG_FULL_STAGE));
        mailbox_write(7, rd32(PL_BASE + REG_HLS_SIGNATURE));
        mailbox_write(1, (rc == 0) ? 0x9005u : 0xdead0000u);
        barrier();
        __asm__ volatile ("bkpt #0");
        for (;;) {}
    }

    mailbox_write(1, 0x300u);
    rc = generate_greedy(tokens, n, max_new_tokens);

    mailbox_write(3, (uint32_t)rc);
    mailbox_write(4, rd32(PL_BASE + REG_STATUS));
    mailbox_write(5, rd32(PL_BASE + REG_FULL_STATUS));
    mailbox_write(6, rd32(PL_BASE + REG_FULL_STAGE));
    mailbox_write(7, rd32(PL_BASE + REG_HLS_SIGNATURE));

    mailbox_write(1, (rc == 0) ? 0x900du : 0xdead0000u);
    barrier();
    __asm__ volatile ("bkpt #0");
    for (;;) {}
}
