$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root "rtl\hls_kernel_chain_axis_full_only_core_ffn64_qp16.v"
$outputPath = Join-Path $root "rtl\hls_kernel_chain_axis_full_only_core_ffn64_qp16_pipe100.v"
$text = Get-Content -LiteralPath $sourcePath -Raw

function Replace-Exact([string]$Text, [string]$Old, [string]$New, [int]$Expected, [string]$Label) {
    $count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($count -ne $Expected) { throw "$Label expected $Expected matches, found $count" }
    return $Text.Replace($Old, $New)
}

function Split-State([string]$Text, [string]$State, [string]$Marker, [string]$Setup, [string]$PipeState, [scriptblock]$EditSuffix) {
    $pattern = [regex]("(?ms)^\s{16}" + [regex]::Escape($State) + ": begin.*?(?=^\s{16}ST_[A-Z0-9_]+: begin)")
    $matches = $pattern.Matches($Text)
    if ($matches.Count -ne 1) { throw "$State expected one block, found $($matches.Count)" }
    $block = $matches[0].Value
    $index = $block.IndexOf($Marker)
    if ($index -lt 0) { throw "$State marker not found" }
    $prefix = $block.Substring(0, $index)
    $suffix = & $EditSuffix $block.Substring($index)
    $replacement = $prefix + $Setup + "                    state <= $PipeState;`r`n                end`r`n`r`n                ${PipeState}: begin`r`n" + $suffix
    return $Text.Remove($matches[0].Index, $matches[0].Length).Insert($matches[0].Index, $replacement)
}

$text = Replace-Exact $text "localparam logic [31:0] FULL_CONFIG_VERSION = 32'hF117_1040;" "localparam logic [31:0] FULL_CONFIG_VERSION = 32'hF117_1140;" 1 "pipeline signature"
$text = Replace-Exact $text "        ST_Q_QUANT,`n        ST_Q_QUANT_WAIT," "        ST_Q_QUANT,`n        ST_Q_QUANT_PIPE,`n        ST_Q_QUANT_WAIT," 1 "Q pipeline state"
$text = Replace-Exact $text "        ST_PROJ_QUANT,`n        ST_PROJ_QUANT_WAIT," "        ST_PROJ_QUANT,`n        ST_PROJ_QUANT_PIPE,`n        ST_PROJ_QUANT_WAIT," 1 "projection pipeline state"
$text = Replace-Exact $text "        ST_FFN_W1_QUANT,`n        ST_FFN_W1_QUANT_WAIT," "        ST_FFN_W1_QUANT,`n        ST_FFN_W1_QUANT_PIPE,`n        ST_FFN_W1_QUANT_WAIT," 1 "FFN W1 pipeline state"
$text = Replace-Exact $text "        ST_FFN_W2_QUANT,`n        ST_FFN_W2_QUANT_WAIT," "        ST_FFN_W2_QUANT,`n        ST_FFN_W2_QUANT_PIPE,`n        ST_FFN_W2_QUANT_WAIT," 1 "FFN W2 pipeline state"
$text = Replace-Exact $text "    logic signed [7:0] q_value;" @"
    logic signed [7:0] q_value;
    // Register the wide lane selector before the DSP requantization path.
    logic signed [31:0] requant_value_reg;
    logic [31:0] requant_mult_reg;
    logic requant_use_shift_reg;
"@ 1 "requant pipeline registers"

$qSetup = @"
                    requant_value_reg <= selected_final;
                    requant_use_shift_reg <= !(full_debug_base_reg == 32'h12E0_0001 ||
                                               full_debug_base_reg == 32'h12E0_0002 ||
                                               full_debug_base_reg == 32'h12E0_0003);
                    if (full_debug_base_reg == 32'h12E0_0001) requant_mult_reg <= q_mult_q30_data;
                    else if (full_debug_base_reg == 32'h12E0_0002) requant_mult_reg <= k_mult_q30_data;
                    else requant_mult_reg <= v_mult_q30_data;
"@
$text = Split-State $text 'ST_Q_QUANT' "                    if (full_debug_base_reg == 32'h12E0_0001)" $qSetup 'ST_Q_QUANT_PIPE' {
    param($suffix)
    $pattern = [regex]"(?ms)^\s{20}if \(full_debug_base_reg == 32'h12E0_0001\).*?^\s{20}else q_value <= requant_full_q\(selected_final, full_q_shift_reg\);"
    if ($pattern.Matches($suffix).Count -ne 1) { throw 'Q requant suffix mismatch' }
    return $pattern.Replace($suffix, "                    if (requant_use_shift_reg) q_value <= requant_full_q(requant_value_reg, full_q_shift_reg);`r`n                    else q_value <= requant_q30(requant_value_reg, requant_mult_reg);")
}

$simpleSetup = "                    requant_value_reg <= selected_final;`r`n                    requant_use_shift_reg <= 1'b0;`r`n"
$text = Split-State $text 'ST_PROJ_QUANT' "                    q_value <= requant_q30(selected_final, attn_proj_mult_q30_data);" ($simpleSetup + "                    requant_mult_reg <= attn_proj_mult_q30_data;`r`n") 'ST_PROJ_QUANT_PIPE' {
    param($suffix)
    return $suffix.Replace('q_value <= requant_q30(selected_final, attn_proj_mult_q30_data);', 'q_value <= requant_q30(requant_value_reg, requant_mult_reg);')
}
$text = Split-State $text 'ST_FFN_W2_QUANT' "                    q_value <= requant_q30(selected_final, ffn_mult_q30_data);" ($simpleSetup + "                    requant_mult_reg <= ffn_mult_q30_data;`r`n") 'ST_FFN_W2_QUANT_PIPE' {
    param($suffix)
    return $suffix.Replace('q_value <= requant_q30(selected_final, ffn_mult_q30_data);', 'q_value <= requant_q30(requant_value_reg, requant_mult_reg);').Replace('requant_full_ffn(selected_final, full_ffn_shift_reg)', 'requant_full_ffn(requant_value_reg, full_ffn_shift_reg)')
}
$text = Split-State $text 'ST_FFN_W1_QUANT' "                    ffn_mid_we <= 1'b1;" ($simpleSetup + "                    requant_mult_reg <= ffn_mid_mult_q30_data;`r`n") 'ST_FFN_W1_QUANT_PIPE' {
    param($suffix)
    return $suffix.Replace('requant_q30(selected_final, ffn_mid_mult_q30_data)', 'requant_q30(requant_value_reg, requant_mult_reg)').Replace('requant_full_ffn_mid(selected_final, full_ffn_mid_shift_reg)', 'requant_full_ffn_mid(requant_value_reg, full_ffn_mid_shift_reg)')
}

Set-Content -LiteralPath $outputPath -Value $text -Encoding ascii
Write-Output "REQUANT_PIPELINE_VARIANT=$outputPath"
Write-Output "REQUANT_PIPELINE_LINES=$((Get-Content -LiteralPath $outputPath).Count)"
