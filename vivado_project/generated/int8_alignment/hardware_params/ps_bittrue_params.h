#ifndef NANO_GPT_PS_BITTRUE_PARAMS_H
#define NANO_GPT_PS_BITTRUE_PARAMS_H

#define BITTRUE_LN_COEFF_BASE 0x13200000u
#define BITTRUE_LM_SCALE_BASE 0x13205000u
#define BITTRUE_LN_STAGE_BYTES (384u * 4u)
#define BITTRUE_LN_FINAL_STAGE 12u

static const uint32_t g_res1_input_mult_q30[6] = {0x0fd26d29u, 0x3c5179f5u, 0x3d9c52b0u, 0x3e3e80b2u, 0x3e9b0e82u, 0x3be3e4f6u};
static const uint32_t g_res1_proj_mult_q30[6] = {0x39c5580cu, 0x080fcd3bu, 0x04ab1f6cu, 0x04d1fefcu, 0x05e70f61u, 0x05ee6135u};
static const uint32_t g_final_res1_mult_q30[6] = {0x081fe4a0u, 0x32d048d5u, 0x3895f172u, 0x3c84bb4au, 0x3d22e5e5u, 0x3921f71eu};
static const uint32_t g_final_ffn_mult_q30[6] = {0x3de38e2bu, 0x1171ca51u, 0x0a166e9fu, 0x06996b51u, 0x19fa4841u, 0x1376a82fu};

#endif
