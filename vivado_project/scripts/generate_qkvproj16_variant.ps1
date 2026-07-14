$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root "rtl\hls_kernel_chain_axis_full_only_core_ffn64.v"
$outputPath = Join-Path $root "rtl\hls_kernel_chain_axis_full_only_core_ffn64_qp16.v"
$text = Get-Content -LiteralPath $sourcePath -Raw

function Replace-Exact([string]$Text, [string]$Old, [string]$New, [int]$Expected, [string]$Label) {
    $count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($count -ne $Expected) { throw "$Label expected $Expected matches, found $count" }
    return $Text.Replace($Old, $New)
}

function Update-State([string]$Text, [string]$State, [scriptblock]$Edit) {
    $pattern = [regex]("(?ms)^\s{16}" + [regex]::Escape($State) + ": begin.*?(?=^\s{16}ST_[A-Z0-9_]+: begin)")
    $matches = $pattern.Matches($Text)
    if ($matches.Count -ne 1) { throw "$State expected one state block, found $($matches.Count)" }
    $updated = & $Edit $matches[0].Value
    return $Text.Remove($matches[0].Index, $matches[0].Length).Insert($matches[0].Index, $updated)
}

$text = Replace-Exact $text "localparam logic [31:0] FULL_CONFIG_VERSION = 32'hF117_0040;" "localparam logic [31:0] FULL_CONFIG_VERSION = 32'hF117_1040;" 1 "QP16 signature"
$text = Replace-Exact $text @"
    (* ram_style = "block" *) logic [63:0] wq_word_mem [0:FULL_Q_WEIGHT_WORDS64-1];
"@ @"
    // Consecutive 64-bit weight words are banked so Q/K/V/projection can read 16 INT8 lanes per cycle.
    (* ram_style = "block" *) logic [63:0] wq_word_mem_even [0:(FULL_Q_WEIGHT_WORDS64/2)-1];
    (* ram_style = "block" *) logic [63:0] wq_word_mem_odd [0:(FULL_Q_WEIGHT_WORDS64/2)-1];
"@ 1 "Q weight bank declarations"
$text = Replace-Exact $text @"
    logic [15:0] wq_rd_addr;
    logic [63:0] wq_rd_data;
"@ @"
    logic [14:0] wq_rd_pair_addr;
    logic [63:0] wq_rd_data_even;
    logic [63:0] wq_rd_data_odd;
"@ 1 "Q weight read ports"
$text = Replace-Exact $text @"
    always_ff @(posedge s_axi_aclk) begin
        if (wload_drain_pipe_valid)
            wq_word_mem[wload_drain_pipe_base + wload_drain_pipe_addr] <=
                wload_drain_pipe_bank ? wload_pp1_rd_data : wload_pp0_rd_data;
        wq_rd_data <= wq_word_mem[wq_rd_addr];
"@ @"
    always_ff @(posedge s_axi_aclk) begin
        if (wload_drain_pipe_valid && !((wload_drain_pipe_base + wload_drain_pipe_addr) & 16'd1))
            wq_word_mem_even[(wload_drain_pipe_base + wload_drain_pipe_addr) >> 1] <=
                wload_drain_pipe_bank ? wload_pp1_rd_data : wload_pp0_rd_data;
        wq_rd_data_even <= wq_word_mem_even[wq_rd_pair_addr];
    end

    always_ff @(posedge s_axi_aclk) begin
        if (wload_drain_pipe_valid && ((wload_drain_pipe_base + wload_drain_pipe_addr) & 16'd1))
            wq_word_mem_odd[(wload_drain_pipe_base + wload_drain_pipe_addr) >> 1] <=
                wload_drain_pipe_bank ? wload_pp1_rd_data : wload_pp0_rd_data;
        wq_rd_data_odd <= wq_word_mem_odd[wq_rd_pair_addr];
    end

    always_ff @(posedge s_axi_aclk) begin
"@ 1 "Q weight bank read/write logic"
$text = Replace-Exact $text "            wq_rd_addr <= '0;" "            wq_rd_pair_addr <= '0;" 1 "Q read address reset"
$text = Replace-Exact $text "                    wq_rd_addr <= (mac_dim * (FULL_Q_OUT/8)) + q_dim[8:3];" "                    wq_rd_pair_addr <= (mac_dim * (FULL_Q_OUT/16)) + q_dim[8:4];" 2 "Q/projection pair addresses"

foreach ($prefix in @('Q', 'PROJ')) {
    $text = Update-State $text "ST_${prefix}_MAC_PREP" {
        param($block)
        $block = $block.Replace('wq_rd_data, 3''d', 'wq_rd_data_even, 3''d')
        $extra = (8..15 | ForEach-Object {
            $byte = $_ - 8
            "                    ffn_mul_b$_ <= `$signed(select_dword_byte_signed(wq_rd_data_odd, 3'd$byte));"
        }) -join "`r`n"
        return $block.Replace("                    ffn_mul_b7 <= `$signed(select_dword_byte_signed(wq_rd_data_even, 3'd7));", "                    ffn_mul_b7 <= `$signed(select_dword_byte_signed(wq_rd_data_even, 3'd7));`r`n$extra")
    }
    $text = Update-State $text "ST_${prefix}_MUL" {
        param($block)
        $extra = (8..15 | ForEach-Object { "                    ffn_prod$_ <= ffn_mul_a * ffn_mul_b$_;" }) -join "`r`n"
        return $block.Replace("                    ffn_prod7 <= ffn_mul_a * ffn_mul_b7;", "                    ffn_prod7 <= ffn_mul_a * ffn_mul_b7;`r`n$extra")
    }
    $text = Update-State $text "ST_${prefix}_MAC" {
        param($block)
        $decl = (8..15 | ForEach-Object { "                    logic signed [31:0] next_acc$_;" }) -join "`r`n"
        $equations = (8..15 | ForEach-Object { "                    next_acc$_ = `$signed(ffn_acc$_) + `$signed(ffn_prod$_);" }) -join "`r`n"
        $finals = (8..15 | ForEach-Object { "                        ffn_final$_ <= next_acc$_;" }) -join "`r`n"
        $resets = (8..15 | ForEach-Object { "                        ffn_acc$_ <= '0;" }) -join "`r`n"
        $updates = (8..15 | ForEach-Object { "                        ffn_acc$_ <= next_acc$_;" }) -join "`r`n"
        $block = $block.Replace("                    logic signed [31:0] next_acc7;", "                    logic signed [31:0] next_acc7;`r`n$decl")
        $block = $block.Replace("                    next_acc7 = `$signed(ffn_acc7) + `$signed(ffn_prod7);", "                    next_acc7 = `$signed(ffn_acc7) + `$signed(ffn_prod7);`r`n$equations")
        $block = $block.Replace("                        ffn_final7 <= next_acc7;", "                        ffn_final7 <= next_acc7;`r`n$finals")
        $firstReset = $block.IndexOf("                        ffn_acc7 <= '0;")
        if ($firstReset -lt 0) { throw "ST_${prefix}_MAC reset anchor missing" }
        $insertAt = $firstReset + "                        ffn_acc7 <= '0;".Length
        $block = $block.Insert($insertAt, "`r`n$resets")
        $updateAnchor = "                        ffn_acc7 <= next_acc7;"
        $block = $block.Replace($updateAnchor, "$updateAnchor`r`n$updates")
        return $block
    }
    $text = Update-State $text "ST_${prefix}_QUANT" {
        param($block)
        $old = @"
                        3'd0: selected_final = ffn_final0;
                        3'd1: selected_final = ffn_final1;
                        3'd2: selected_final = ffn_final2;
                        3'd3: selected_final = ffn_final3;
                        3'd4: selected_final = ffn_final4;
                        3'd5: selected_final = ffn_final5;
                        3'd6: selected_final = ffn_final6;
                        default: selected_final = ffn_final7;
"@
        $new = ((0..14 | ForEach-Object { "                        4'd${_}: selected_final = ffn_final$_;" }) -join "`r`n") + "`r`n                        default: selected_final = ffn_final15;"
        if (-not $block.Contains($old)) { throw "ST_${prefix}_QUANT selector anchor missing" }
        return $block.Replace($old, $new)
    }
}

# Q writes two 64-bit words from each 16-lane result group before starting the next MAC group.
$text = Update-State $text 'ST_Q_WRITE_RESP' {
    param($block)
    $anchor = @"
                        end else begin
                            q_dim <= q_dim + 1'b1;
                            mac_dim <= '0;
"@
    $replacement = @"
                        end else if (ffn_parallel_lane != 6'd15) begin
                            q_dim <= q_dim + 1'b1;
                            ffn_parallel_lane <= ffn_parallel_lane + 1'b1;
                            q_word_pack <= '0;
                            state <= ST_Q_QUANT_WAIT;
                        end else begin
                            q_dim <= q_dim + 1'b1;
                            mac_dim <= '0;
"@
    if (-not $block.Contains($anchor)) { throw 'ST_Q_WRITE_RESP group anchor missing' }
    return $block.Replace($anchor, $replacement)
}
$text = Update-State $text 'ST_PROJ_WRITE_RESP' {
    param($block)
    return $block.Replace("ffn_parallel_lane != 3'd7", "ffn_parallel_lane != 6'd15")
}

# Reset the additional accumulators whenever a new 16-lane Q/projection group starts.
foreach ($stateName in @('ST_Q_WRITE_RESP', 'ST_PROJ_WRITE_RESP')) {
    $text = Update-State $text $stateName {
        param($block)
        $extraAcc = (8..15 | ForEach-Object { "                            ffn_acc$_ <= '0;" }) -join "`r`n"
        $extraFinal = (8..15 | ForEach-Object { "                            ffn_final$_ <= '0;" }) -join "`r`n"
        $block = $block.Replace("                            ffn_acc7 <= '0;", "                            ffn_acc7 <= '0;`r`n$extraAcc")
        $block = $block.Replace("                            ffn_final7 <= '0;", "                            ffn_final7 <= '0;`r`n$extraFinal")
        return $block
    }
}

Set-Content -LiteralPath $outputPath -Value $text -Encoding ascii
Write-Output "QKVPROJ16_VARIANT=$outputPath"
Write-Output "QKVPROJ16_LINES=$((Get-Content -LiteralPath $outputPath).Count)"
