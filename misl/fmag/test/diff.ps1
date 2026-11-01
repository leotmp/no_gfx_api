# Differential: cl_c vs cl_odin on fsl fixtures. Exit 0 only if every gate matches.
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$Out = Join-Path $Root "out\fmag_c"
$ClC = Join-Path $Out "cl_c.exe"
$ClO = Join-Path $Out "cl_odin.exe"
$Test = $PSScriptRoot
$Std = Join-Path $Root "oge\misl\research\fmag\tools\std\std.fsl"
$Work = Join-Path $Out "diff_work"
New-Item -ItemType Directory -Force -Path $Work | Out-Null

function Invoke-Cli {
    param($Exe, $ArgList)
    $p = Start-Process -FilePath $Exe -ArgumentList $ArgList -WorkingDirectory $Work -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput (Join-Path $Work "stdout.txt") `
        -RedirectStandardError (Join-Path $Work "stderr.txt")
    return @{
        Code = $p.ExitCode
        Out  = Get-Content (Join-Path $Work "stdout.txt") -Raw -ErrorAction SilentlyContinue
        Err  = Get-Content (Join-Path $Work "stderr.txt") -Raw -ErrorAction SilentlyContinue
    }
}

function Compare-Run {
    param($Name, $Src, $Inputs)
    $cF = Join-Path $Work "$Name-c.fmag"
    $oF = Join-Path $Work "$Name-o.fmag"
    $rc = Invoke-Cli $ClC @("-c", $Src, "-o", $cF)
    $ro = Invoke-Cli $ClO @("-c", $Src, "-o", $oF)
    if ($rc.Code -ne 0 -or $ro.Code -ne 0) {
        Write-Host "FAIL $Name compile  cl_c=$($rc.Code) cl_odin=$($ro.Code)"
        Write-Host $rc.Err
        Write-Host $ro.Err
        exit 1
    }
    $runC = Invoke-Cli $ClC (@("-r", $cF) + $Inputs)
    $runO = Invoke-Cli $ClO (@("-r", $oF) + $Inputs)
    if ($runC.Code -ne 0 -or $runO.Code -ne 0) {
        Write-Host "FAIL $Name run  cl_c=$($runC.Code) cl_odin=$($runO.Code)"
        exit 1
    }
    $a = ($runC.Out -replace "`r", "").Trim()
    $b = ($runO.Out -replace "`r", "").Trim()
    if ($a -ne $b) {
        Write-Host "FAIL $Name -r mismatch"
        Write-Host "cl_c:`n$a"
        Write-Host "cl_odin:`n$b"
        exit 1
    }
    Write-Host "ok $Name => $a"
}

function Compare-Fail {
    param($Name, $Src)
    $cF = Join-Path $Work "$Name-c.fmag"
    $oF = Join-Path $Work "$Name-o.fmag"
    $rc = Invoke-Cli $ClC @("-c", $Src, "-o", $cF)
    $ro = Invoke-Cli $ClO @("-c", $Src, "-o", $oF)
    if ($rc.Code -eq 0 -or $ro.Code -eq 0) {
        Write-Host "FAIL $Name expected both -c to fail  cl_c=$($rc.Code) cl_odin=$($ro.Code)"
        exit 1
    }
    Write-Host "ok $Name both failed to lower/compile"
}

if (-not (Test-Path $ClC) -or -not (Test-Path $ClO)) {
    Write-Host "missing cl_c.exe or cl_odin.exe in $Out"
    exit 1
}

Compare-Run "lambert" (Join-Path $Test "lambert.fsl") @("0", "1", "0", "0", "1", "0", "1", "0.2", "0.1", "0.1")
Compare-Run "lambert_flipped" (Join-Path $Test "lambert.fsl") @("0", "1", "0", "0", "-1", "0", "1", "0.2", "0.1", "0.1")
Compare-Run "if_merge" (Join-Path $Test "if_merge.fsl") @("3")
Compare-Run "if_merge_neg" (Join-Path $Test "if_merge.fsl") @("-2")

$combined = Join-Path $Work "std_ops_combined.fsl"
$stdText = Get-Content -Raw -Path $Std
$opsText = Get-Content -Raw -Path (Join-Path $Test "std_ops.fsl")
Set-Content -Path $combined -Value ($stdText + "`n" + $opsText) -NoNewline
Compare-Run "std_ops" $combined @("0.5", "4")

Compare-Fail "recursion" (Join-Path $Test "recursion.fsl")

function Files-Equal($a, $b) {
    $ba = [IO.File]::ReadAllBytes($a)
    $bb = [IO.File]::ReadAllBytes($b)
    if ($ba.Length -ne $bb.Length) { return $false }
    for ($i = 0; $i -lt $ba.Length; $i++) {
        if ($ba[$i] -ne $bb[$i]) { return $false }
    }
    return $true
}

$re = Join-Path $Test "reassoc.fsl"
$cDef = Join-Path $Work "reassoc-c.fmag"
$oDef = Join-Path $Work "reassoc-o.fmag"
$cFast = Join-Path $Work "reassoc-c-fast.fmag"
$oFast = Join-Path $Work "reassoc-o-fast.fmag"
$rcd = Invoke-Cli $ClC @("-c", $re, "-o", $cDef)
$rod = Invoke-Cli $ClO @("-c", $re, "-o", $oDef)
$rcf = Invoke-Cli $ClC @("-c", $re, "-o", $cFast, "-ffast-math")
$rof = Invoke-Cli $ClO @("-c", $re, "-o", $oFast, "-ffast-math")
if ($rcd.Code -ne 0 -or $rod.Code -ne 0 -or $rcf.Code -ne 0 -or $rof.Code -ne 0) {
    Write-Host "FAIL reassoc compile"
    exit 1
}
if (-not (Files-Equal $cDef $oDef)) {
    Write-Host "FAIL reassoc default stream C vs Odin"
    exit 1
}
if (-not (Files-Equal $cFast $oFast)) {
    Write-Host "FAIL reassoc fast stream C vs Odin"
    exit 1
}
if (Files-Equal $cDef $cFast) {
    Write-Host "FAIL reassoc default and fast streams should differ"
    exit 1
}
$defC = (Invoke-Cli $ClC @("-r", $cDef, "1.1")).Out
$defO = (Invoke-Cli $ClO @("-r", $oDef, "1.1")).Out
$fastC = (Invoke-Cli $ClC @("-r", $cFast, "1.1")).Out
$fastO = (Invoke-Cli $ClO @("-r", $oFast, "1.1")).Out
if (($defC -replace "`r", "") -ne ($defO -replace "`r", "")) {
    Write-Host "FAIL reassoc default -r mismatch"
    exit 1
}
if (($fastC -replace "`r", "") -ne ($fastO -replace "`r", "")) {
    Write-Host "FAIL reassoc fast -r mismatch"
    exit 1
}
Write-Host "ok reassoc default vs fast streams differ; C matches Odin"

$asm = Join-Path $Test "one.s"
$cA = Join-Path $Work "one-c.fmag"
$oA = Join-Path $Work "one-o.fmag"
$ac = Invoke-Cli $ClC @("-a", $asm, "-o", $cA)
$ao = Invoke-Cli $ClO @("-a", $asm, "-o", $oA)
if ($ac.Code -ne 0 -or $ao.Code -ne 0) {
    Write-Host "FAIL assemble one.s"
    exit 1
}
$bytesC = [IO.File]::ReadAllBytes($cA)
$bytesO = [IO.File]::ReadAllBytes($oA)
if ($bytesC.Length -ne $bytesO.Length) {
    Write-Host "FAIL assemble size $($bytesC.Length) vs $($bytesO.Length)"
    exit 1
}
for ($i = 0; $i -lt $bytesC.Length; $i++) {
    if ($bytesC[$i] -ne $bytesO[$i]) {
        Write-Host "FAIL assemble byte $i"
        exit 1
    }
}
$rC = (Invoke-Cli $ClC @("-r", $cA, "4")).Out
$rO = (Invoke-Cli $ClO @("-r", $oA, "4")).Out
if (($rC -replace "`r", "").Trim() -ne ($rO -replace "`r", "").Trim()) {
    Write-Host "FAIL assemble -r mismatch"
    exit 1
}
Write-Host "ok assemble one.s bytes and -r match"

Write-Host "all differential tests passed"
