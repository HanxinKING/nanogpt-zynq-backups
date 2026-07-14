$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root "rtl\hls_kernel_chain_axis_full_only_core.v"
$outputPath = Join-Path $root "rtl\hls_kernel_chain_axis_full_only_core_ffn64.v"
$text = Get-Content -LiteralPath $sourcePath -Raw

function Require-Replace([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($count -ne 1) { throw "$Label expected one match, found $count" }
    return $Text.Replace($Old, $New)
}

function Add-Lanes([int]$First, [int]$Last, [scriptblock]$Line) {
    return (($First..$Last) | ForEach-Object { & $Line $_ }) -join "`r`n"
}

function Insert-After([string]$Text, [string]$Needle, [string]$Extra, [string]$Label) {
    $count = ([regex]::Matches($Text, [regex]::Escape($Needle))).Count
    if ($count -ne 1) { throw "$Label expected one match, found $count" }
    return $Text.Replace($Needle, "$Needle`r`n$Extra")
}

function Replace-AllExact([string]$Text, [string]$Needle, [scriptblock]$Replacement, [int]$Expected, [string]$Label) {
    $count = ([regex]::Matches($Text, [regex]::Escape($Needle))).Count
    if ($count -ne $Expected) { throw "$Label expected $Expected matches, found $count" }
    return $Text.Replace($Needle, (& $Replacement))
}

$text = Require-Replace $text "logic [4:0] ffn_parallel_lane;" "logic [5:0] ffn_parallel_lane;" "FFN lane width"
$text = Require-Replace $text "logic [1:0] ffn_weight_beat;" "logic [2:0] ffn_weight_beat;" "FFN AXI beat width"
$text = Require-Replace $text "8'd3 : 8'd0;" "8'd7 : 8'd0;" "FFN AXI burst length"
$text = Require-Replace $text "localparam logic [31:0] FULL_CONFIG_VERSION = 32'hF117_0001;" "localparam logic [31:0] FULL_CONFIG_VERSION = 32'hF117_0040;" "FFN64 signature"

$text = Insert-After $text "logic signed [31:0] ffn_acc31;" (Add-Lanes 32 63 { param($i) "    logic signed [31:0] ffn_acc$i;" }) "FFN accumulator declarations"
$text = Insert-After $text "logic signed [31:0] ffn_final31;" (Add-Lanes 32 63 { param($i) "    logic signed [31:0] ffn_final$i;" }) "FFN final declarations"
$text = Insert-After $text "logic signed [17:0] ffn_mul_b31;" (Add-Lanes 32 63 { param($i) "    logic signed [17:0] ffn_mul_b$i;" }) "FFN multiplier declarations"
$text = Insert-After $text '(* use_dsp = "yes" *) logic signed [42:0] ffn_prod31;' (Add-Lanes 32 63 { param($i) ('    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod{0};' -f $i) }) "FFN product declarations"
$text = Insert-After $text "logic [63:0] ffn_weight_quad;" @"
    logic [63:0] ffn_weight_penta;
    logic [63:0] ffn_weight_hexa;
    logic [63:0] ffn_weight_septa;
    logic [63:0] ffn_weight_oct;
"@ "FFN weight buffer declarations"
$text = Insert-After $text "logic [63:0] ffn_weight_next_quad;" @"
    logic [63:0] ffn_weight_next_penta;
    logic [63:0] ffn_weight_next_hexa;
    logic [63:0] ffn_weight_next_septa;
    logic [63:0] ffn_weight_next_oct;
"@ "FFN next-weight buffer declarations"

# Expand each 4-beat FFN response collector into an 8-beat collector.
$casePattern = [regex]'(?ms)case \(ffn_weight_beat\)\r?\n(?:(?!endcase).)*?endcase'
$cases = $casePattern.Matches($text)
if ($cases.Count -ne 6) { throw "FFN weight collectors expected 6 matches, found $($cases.Count)" }
$text = $casePattern.Replace($text, {
    param($match)
    $caseText = $match.Value
    $defaultPattern = [regex]'(?ms)^(?<indent>\s*)default: begin\r?\n(?<body>.*?)^\k<indent>end'
    $defaultMatch = $defaultPattern.Match($caseText)
    if (-not $defaultMatch.Success) { throw "Could not locate FFN collector default branch" }
    $body = $defaultMatch.Groups['body'].Value
    $nameMatch = [regex]::Match($body, 'ffn_weight_(?<next>next_)?quad <= m_axi_ddr_rdata;')
    if (-not $nameMatch.Success) { throw "Could not locate FFN quad buffer assignment" }
    $prefix = if ($nameMatch.Groups['next'].Success) { 'next_' } else { '' }
    $assignIndent = [regex]::Match($body, '(?m)^(\s*)ffn_weight_').Groups[1].Value
    $tail = $body.Remove($nameMatch.Index, $nameMatch.Length)
    $tail = [regex]::Replace($tail, '(?m)^\s*ffn_weight_beat <= ''0;\r?\n', '')
    $caseIndent = $defaultMatch.Groups['indent'].Value
    $branches = @()
    foreach ($entry in @(@('3','quad','4'), @('4','penta','5'), @('5','hexa','6'), @('6','septa','7'))) {
        $branches += "${caseIndent}3'd$($entry[0]): begin`r`n${assignIndent}ffn_weight_${prefix}$($entry[1]) <= m_axi_ddr_rdata;`r`n${assignIndent}ffn_weight_beat <= 3'd$($entry[2]);`r`n${caseIndent}end"
    }
    $newDefault = "${caseIndent}default: begin`r`n${assignIndent}ffn_weight_${prefix}oct <= m_axi_ddr_rdata;`r`n${assignIndent}ffn_weight_beat <= '0;`r`n$tail${caseIndent}end"
    return $caseText.Replace($defaultMatch.Value, (($branches -join "`r`n") + "`r`n" + $newDefault))
})

# The two FFN multiply paths receive four additional 64-bit words.
$weightNames = @('penta','hexa','septa','oct')
$mulExtra = Add-Lanes 32 63 {
    param($i)
    $word = $weightNames[[math]::Floor($i / 8) - 4]
    $byte = $i % 8
    "                    ffn_mul_b$i <= `$signed(select_dword_byte_signed(ffn_weight_$word, 3'd$byte));"
}
$text = Replace-AllExact $text "                    ffn_mul_b31 <= `$signed(select_dword_byte_signed(ffn_weight_quad, 3'd7));" { "                    ffn_mul_b31 <= `$signed(select_dword_byte_signed(ffn_weight_quad, 3'd7));`r`n$mulExtra" } 2 "FFN weight fanout"
$text = Replace-AllExact $text "                        ffn_weight_quad <= ffn_weight_next_quad;" {
    "                        ffn_weight_quad <= ffn_weight_next_quad;`r`n" +
    "                        ffn_weight_penta <= ffn_weight_next_penta;`r`n" +
    "                        ffn_weight_hexa <= ffn_weight_next_hexa;`r`n" +
    "                        ffn_weight_septa <= ffn_weight_next_septa;`r`n" +
    "                        ffn_weight_oct <= ffn_weight_next_oct;"
} 2 "FFN prefetched weight swap"
$prodExtra = Add-Lanes 32 63 { param($i) "                    ffn_prod$i <= ffn_mul_a * ffn_mul_b$i;" }
$text = Replace-AllExact $text "                    ffn_prod31 <= ffn_mul_a * ffn_mul_b31;" { "                    ffn_prod31 <= ffn_mul_a * ffn_mul_b31;`r`n$prodExtra" } 2 "FFN product fanout"

$nextDeclExtra = Add-Lanes 32 63 { param($i) "                    logic signed [31:0] next_acc$i;" }
$text = Replace-AllExact $text "                    logic signed [31:0] next_acc31;" { "                    logic signed [31:0] next_acc31;`r`n$nextDeclExtra" } 2 "FFN next accumulator declarations"
$nextAccExtra = Add-Lanes 32 63 { param($i) "                    next_acc$i = `$signed(ffn_acc$i) + `$signed(ffn_prod$i);" }
$text = Replace-AllExact $text "                    next_acc31 = `$signed(ffn_acc31) + `$signed(ffn_prod31);" { "                    next_acc31 = `$signed(ffn_acc31) + `$signed(ffn_prod31);`r`n$nextAccExtra" } 2 "FFN next accumulator equations"
$finalExtra = Add-Lanes 32 63 { param($i) "                        ffn_final$i <= next_acc$i;" }
$text = Replace-AllExact $text "                        ffn_final31 <= next_acc31;" { "                        ffn_final31 <= next_acc31;`r`n$finalExtra" } 2 "FFN final accumulator capture"
$accResetPattern = [regex]'(?m)^(?<indent>\s*)ffn_acc31 <= ''0;$'
$accResetCount = $accResetPattern.Matches($text).Count
if ($accResetCount -ne 8) { throw "FFN accumulator resets expected 8 matches, found $accResetCount" }
$text = $accResetPattern.Replace($text, {
    param($match)
    $indent = $match.Groups['indent'].Value
    $extra = Add-Lanes 32 63 { param($i) ('{0}ffn_acc{1} <= ''0;' -f $indent, $i) }
    return "$($match.Value)`r`n$extra"
})
$accUpdateExtra = Add-Lanes 32 63 { param($i) "                        ffn_acc$i <= next_acc$i;" }
$text = Replace-AllExact $text "                        ffn_acc31 <= next_acc31;" { "                        ffn_acc31 <= next_acc31;`r`n$accUpdateExtra" } 2 "FFN accumulator updates"

$selectExtra = ((31..62) | ForEach-Object { "                        6'd${_}: selected_final = ffn_final$_;" }) -join "`r`n"
$text = Replace-AllExact $text "                        default: selected_final = ffn_final31;" { "$selectExtra`r`n                        default: selected_final = ffn_final63;" } 2 "FFN output selectors"
$text = Require-Replace $text "if (ffn_parallel_lane == 5'd31) begin" "if (ffn_parallel_lane == 6'd63) begin" "FFN W1 group boundary"
$text = Require-Replace $text "end else if (ffn_parallel_lane != 5'd31) begin" "end else if (ffn_parallel_lane != 6'd63) begin" "FFN W2 group boundary"

Set-Content -LiteralPath $outputPath -Value $text -Encoding ascii
Write-Output "FFN64_VARIANT=$outputPath"
Write-Output "FFN64_LINES=$((Get-Content -LiteralPath $outputPath).Count)"
