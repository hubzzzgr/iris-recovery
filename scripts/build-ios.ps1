param(
    [Parameter(Mandatory)][string]$ToolchainBin,
    [Parameter(Mandatory)][string]$Sdk,
    [Parameter(Mandatory)][string]$Zstd,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../build')
)

$ErrorActionPreference = 'Stop'
$ToolchainBin = (Resolve-Path -LiteralPath $ToolchainBin).Path
$Sdk = (Resolve-Path -LiteralPath $Sdk).Path
$Zstd = (Resolve-Path -LiteralPath $Zstd).Path
$project = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$zstdInclude = Join-Path $Zstd 'lib'
$zstdSources = foreach ($folder in 'common', 'compress', 'decompress') {
    Get-ChildItem -LiteralPath (Join-Path $zstdInclude $folder) -File -Filter '*.c' |
        Sort-Object Name | Select-Object -ExpandProperty FullName
}
$irisSources = foreach ($source in 'IrisPreferences.m', 'IrisSettingsViewController.m', 'IrisHeader.m', 'IrisRefresh.m', 'IrisMediaViewController.m') {
    Join-Path $project "Sources/$source"
}
$OutputDirectory = (New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
$output = Join-Path $OutputDirectory 'iris.dylib'
$linkedOutput = Join-Path $OutputDirectory 'iris.linked.dylib'

# Use forward slashes to keep Clang response-file quoting consistent across PowerShell versions.
$compileArguments = @(
    '-target', 'arm64-apple-ios15.0', '-isysroot', $Sdk, '-fuse-ld=lld',
    '-fobjc-arc', '-fblocks', '-fvisibility=hidden', '-O2', '-DZSTD_DISABLE_ASM=1', '-DZSTD_LEGACY_SUPPORT=0',
    '-DZSTDLIB_VISIBLE=', '-I', $zstdInclude, '-Wall', '-Wextra', '-dynamiclib',
    '-Wl,-install_name,@rpath/iris.dylib', '-framework', 'Foundation', '-framework', 'CoreFoundation',
    '-framework', 'CoreGraphics', '-framework', 'CoreImage', '-framework', 'UIKit',
    '-framework', 'UniformTypeIdentifiers', '-framework', 'PhotosUI', '-framework', 'Photos',
    '-framework', 'AVFoundation', '-framework', 'QuartzCore'
) + $irisSources + $zstdSources + @('-o', 'iris.linked.dylib')
$response = Join-Path $OutputDirectory 'clang.rsp'
$compileArguments | ForEach-Object { '"' + $_.Replace('\', '/') + '"' } |
    Set-Content -LiteralPath $response -Encoding ASCII
Push-Location -LiteralPath $OutputDirectory
try {
    & (Join-Path $ToolchainBin 'clang.exe') ('@' + $response)
    if ($LASTEXITCODE -ne 0) { throw 'Clang failed to build the iOS dylib.' }
} finally {
    Pop-Location
    Remove-Item -LiteralPath $response
}

$arch = & (Join-Path $ToolchainBin 'lipo.exe') -archs $linkedOutput
if ($LASTEXITCODE -ne 0 -or ($arch -join ' ').Trim() -ne 'arm64') { throw 'Expected a thin ARM64 library.' }
$header = & (Join-Path $ToolchainBin 'otool.exe') -hv $linkedOutput
if ($LASTEXITCODE -ne 0 -or ($header -join "`n") -notmatch '\bDYLIB\b') { throw 'Expected a Mach-O dylib.' }
$installName = & (Join-Path $ToolchainBin 'otool.exe') -D $linkedOutput | ForEach-Object { $_.Trim() }
if ($LASTEXITCODE -ne 0 -or '@rpath/iris.dylib' -notin $installName) { throw 'Unexpected dylib install name.' }

Move-Item -LiteralPath $linkedOutput -Destination $output -Force
Copy-Item -LiteralPath (Join-Path $Zstd 'LICENSE') -Destination (Join-Path $OutputDirectory 'Zstandard-LICENSE.txt')
$digest = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
"$digest  iris.dylib" | Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS') -Encoding ASCII
Write-Output "Built $output"
