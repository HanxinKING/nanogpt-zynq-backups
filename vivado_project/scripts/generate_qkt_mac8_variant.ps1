$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root "rtl\hls_kernel_chain_axis_full_only_core_ffn64_qp16_pipe100.v"
$outputPath = Join-Path $root "rtl\hls_kernel_chain_axis_full_only_core_ffn64_qp16_pipe100_qkt8.v"
$text = Get-Content -LiteralPath $sourcePath -Raw

function Replace-Exact([string]$Text, [string]$Old, [string]$New, [int]$Expected, [string]$Label) {
    $count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($count -ne $Expected) { throw "$Label expected $Expected matches, found $count" }
    return $Text.Replace($Old, $New)
}
function Update-State([string]$Text, [string]$State, [scriptblock]$Edit) {
    $pattern = [regex]("(?ms)^\s{16}" + [regex]::Escape($State) + ": begin.*?(?=^\s{16}ST_[A-Z0-9_]+: begin)")
    $matches = $pattern.Matches($Text)
    if ($matches.Count -ne 1) { throw "$State expected one block, found $($matches.Count)" }
    $updated = & $Edit $matches[0].Value
    return $Text.Remove($matches[0].Index, $matches[0].Length).Insert($matches[0].Index, $updated)
}

$text = Replace-Exact $text "localparam logic [31:0] FULL_CONFIG_VERSION = 32'hF117_1140;" "localparam logic [31:0] FULL_CONFIG_VERSION = 32'hF117_1180;" 1 "QKT8 signature"
$text = Replace-Exact $text @"
    assign m_axi_ddr_arsize = ((state == ST_Q_W_REQ) || (state == ST_PROJ_W_REQ) ||
"@ @"
    assign m_axi_ddr_arsize = ((state == ST_Q_W_REQ) || (state == ST_PROJ_W_REQ) ||
                               (state == ST_ATTN_Q_REQ) || (state == ST_ATTN_K_REQ) ||
"@ 1 "QKT8 AXI beat size"
$text = Replace-Exact $text "    logic signed [15:0] attn_prod3;" @"
    logic signed [15:0] attn_prod3;
    logic signed [15:0] attn_prod4;
    logic signed [15:0] attn_prod5;
    logic signed [15:0] attn_prod6;
    logic signed [15:0] attn_prod7;
"@ 1 "QKT8 products"

# Q head is naturally 64-byte aligned, so load eight bytes per DDR beat.
$text = Replace-Exact $text "m_axi_ddr_araddr <= full_weights_base_reg + (attn_row * FULL_Q_OUT) + (attn_head * 64) + (attn_word_index << 2);" "m_axi_ddr_araddr <= full_weights_base_reg + (attn_row * FULL_Q_OUT) + (attn_head * 64) + (attn_word_index << 3);" 1 "Q byte offset"
$text = Replace-Exact $text "m_axi_ddr_araddr <= full_scales_base_reg + (attn_cand * FULL_Q_OUT) + (attn_head * 64) + (attn_word_index << 2);" "m_axi_ddr_araddr <= full_scales_base_reg + (attn_cand * FULL_Q_OUT) + (attn_head * 64) + (attn_word_index << 3);" 1 "K byte offset"
$text = Update-State $text 'ST_ATTN_Q_WAIT' { param($b) $b.Replace('attn_read_word <= select_axi_word32(m_axi_ddr_rdata, m_axi_ddr_araddr[2]);', 'ddr_read_word <= m_axi_ddr_rdata;') }
$text = Replace-Exact $text @"
                    attn_q_head[(attn_word_index << 2) + 0] <= select_word_byte_signed(attn_read_word, 2'd0);
                    attn_q_head[(attn_word_index << 2) + 1] <= select_word_byte_signed(attn_read_word, 2'd1);
                    attn_q_head[(attn_word_index << 2) + 2] <= select_word_byte_signed(attn_read_word, 2'd2);
                    attn_q_head[(attn_word_index << 2) + 3] <= select_word_byte_signed(attn_read_word, 2'd3);
"@ @"
                    attn_q_head[(attn_word_index << 3) + 0] <= select_dword_byte_signed(ddr_read_word, 3'd0);
                    attn_q_head[(attn_word_index << 3) + 1] <= select_dword_byte_signed(ddr_read_word, 3'd1);
                    attn_q_head[(attn_word_index << 3) + 2] <= select_dword_byte_signed(ddr_read_word, 3'd2);
                    attn_q_head[(attn_word_index << 3) + 3] <= select_dword_byte_signed(ddr_read_word, 3'd3);
                    attn_q_head[(attn_word_index << 3) + 4] <= select_dword_byte_signed(ddr_read_word, 3'd4);
                    attn_q_head[(attn_word_index << 3) + 5] <= select_dword_byte_signed(ddr_read_word, 3'd5);
                    attn_q_head[(attn_word_index << 3) + 6] <= select_dword_byte_signed(ddr_read_word, 3'd6);
                    attn_q_head[(attn_word_index << 3) + 7] <= select_dword_byte_signed(ddr_read_word, 3'd7);
"@ 1 "Q head 8-byte capture"
$text = Update-State $text 'ST_ATTN_Q_CAP' { param($b) $b.Replace('if (attn_word_index == 15) begin', 'if (attn_word_index == 7) begin') }

# Preserve the entire 64-bit K beat for eight parallel dot-product lanes.
$text = Update-State $text 'ST_ATTN_K_WAIT' { param($b) $b.Replace('attn_read_word <= select_axi_word32(m_axi_ddr_rdata, m_axi_ddr_araddr[2]);', 'ddr_read_word <= m_axi_ddr_rdata;') }
$text = Replace-Exact $text @"
                    attn_prod0 <= `$signed(attn_q_head[(attn_word_index << 2) + 0]) * select_word_byte_signed(attn_read_word, 2'd0);
                    attn_prod1 <= `$signed(attn_q_head[(attn_word_index << 2) + 1]) * select_word_byte_signed(attn_read_word, 2'd1);
                    attn_prod2 <= `$signed(attn_q_head[(attn_word_index << 2) + 2]) * select_word_byte_signed(attn_read_word, 2'd2);
                    attn_prod3 <= `$signed(attn_q_head[(attn_word_index << 2) + 3]) * select_word_byte_signed(attn_read_word, 2'd3);
"@ @"
                    attn_prod0 <= `$signed(attn_q_head[(attn_word_index << 3) + 0]) * select_dword_byte_signed(ddr_read_word, 3'd0);
                    attn_prod1 <= `$signed(attn_q_head[(attn_word_index << 3) + 1]) * select_dword_byte_signed(ddr_read_word, 3'd1);
                    attn_prod2 <= `$signed(attn_q_head[(attn_word_index << 3) + 2]) * select_dword_byte_signed(ddr_read_word, 3'd2);
                    attn_prod3 <= `$signed(attn_q_head[(attn_word_index << 3) + 3]) * select_dword_byte_signed(ddr_read_word, 3'd3);
                    attn_prod4 <= `$signed(attn_q_head[(attn_word_index << 3) + 4]) * select_dword_byte_signed(ddr_read_word, 3'd4);
                    attn_prod5 <= `$signed(attn_q_head[(attn_word_index << 3) + 5]) * select_dword_byte_signed(ddr_read_word, 3'd5);
                    attn_prod6 <= `$signed(attn_q_head[(attn_word_index << 3) + 6]) * select_dword_byte_signed(ddr_read_word, 3'd6);
                    attn_prod7 <= `$signed(attn_q_head[(attn_word_index << 3) + 7]) * select_dword_byte_signed(ddr_read_word, 3'd7);
"@ 1 "QKT8 multiply"
$sum4 = "`$signed(attn_prod0) + `$signed(attn_prod1) + `$signed(attn_prod2) + `$signed(attn_prod3)"
$sum8 = "$sum4 + `$signed(attn_prod4) + `$signed(attn_prod5) + `$signed(attn_prod6) + `$signed(attn_prod7)"
$text = Replace-Exact $text $sum4 $sum8 2 "QKT8 accumulation"
$text = Update-State $text 'ST_ATTN_K_ACC' { param($b) $b.Replace('if (attn_word_index == 15) begin', 'if (attn_word_index == 7) begin') }

Set-Content -LiteralPath $outputPath -Value $text -Encoding ascii
Write-Output "QKT8_VARIANT=$outputPath"
