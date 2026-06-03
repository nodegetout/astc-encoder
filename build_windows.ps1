#Requires -Version 5.0
<#
.SYNOPSIS
    One-click build script for ASTC Encoder on Windows

.DESCRIPTION
    Automated build script that configures, builds, and installs astcenc.
    Supports multiple SIMD variants, unit tests, and various build options.

.PARAMETER SimdVariant
    SIMD instruction set to build: AVX2, SSE41, SSE2, Native, None, or All (default: All)

.PARAMETER BuildType
    Build configuration: Release, Debug, RelWithDebInfo (default: Release)

.PARAMETER BuildTests
    Build and run unit tests (requires GoogleTest submodule)

.PARAMETER BuildShared
    Build shared library in addition to static

.PARAMETER UseClang
    Use Clang-CL toolchain if available (produces faster binaries)

.PARAMETER NoWerror
    Do not treat warnings as errors (auto-enabled on non-Latin code pages)

.PARAMETER Clean
    Clean build directory before building

.PARAMETER Jobs
    Number of parallel build jobs (default: auto-detect CPU count)

.EXAMPLE
    .\build_windows.ps1
    Build all SIMD variants in Release mode

.EXAMPLE
    .\build_windows.ps1 -SimdVariant AVX2 -BuildType Release
    Build AVX2 variant in Release mode

.EXAMPLE
    .\build_windows.ps1 -SimdVariant All -BuildTests -UseClang
    Build all SIMD variants with tests using Clang-CL
#>

[CmdletBinding()]
param(
    [ValidateSet("AVX2", "SSE41", "SSE2", "Native", "None", "All")]
    [string]$SimdVariant = "All",

    [ValidateSet("Release", "Debug", "RelWithDebInfo")]
    [string]$BuildType = "Release",

    [switch]$BuildTests,
    [switch]$BuildShared,
    [switch]$UseClang,
    [switch]$NoWerror,
    [switch]$Clean,

    [ValidateRange(1, 64)]
    [int]$Jobs = [Environment]::ProcessorCount
)

$ErrorActionPreference = "Stop"

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    $oldColor = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $Color
    Write-Output $Message
    $host.UI.RawUI.ForegroundColor = $oldColor
}

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-ColorOutput "[$Step] $Message" "Cyan"
}

function Write-Success {
    param([string]$Message)
    Write-ColorOutput "[SUCCESS] $Message" "Green"
}

function Write-Error-Custom {
    param([string]$Message)
    Write-ColorOutput "[ERROR] $Message" "Red"
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-ColorOutput "[WARNING] $Message" "Yellow"
}

function Write-Info {
    param([string]$Message)
    Write-ColorOutput "[INFO] $Message" "Gray"
}

# Banner
Write-ColorOutput "========================================" "Magenta"
Write-ColorOutput " ASTC Encoder Build Script for Windows" "Magenta"
Write-ColorOutput "========================================" "Magenta"
Write-Output ""

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Determine Werror setting
$werror = -not $NoWerror
if ($werror) {
    # Auto-detect non-Latin code page (e.g. Chinese 936, Korean 949, Japanese 932)
    try {
        $acp = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage" -Name ACP -ErrorAction SilentlyContinue).ACP
        if ($acp -and $acp -notin @("1252", "437", "850", "1250")) {
            Write-Info "Non-Latin code page detected ($acp), disabling -Werror to avoid C4819 warnings"
            $werror = $false
        }
    } catch { }
}

# Check prerequisites
Write-Step "CHECK" "Verifying prerequisites..."

# Check CMake
$cmakePath = Get-Command cmake -ErrorAction SilentlyContinue
if (-not $cmakePath) {
    Write-Error-Custom "CMake not found in PATH. Please install CMake 3.15+ from https://cmake.org/download/"
    exit 1
}

$cmakeVersion = (cmake --version | Select-String "cmake version").ToString()
Write-Info "CMake: $cmakeVersion"

# Check for Visual Studio
$vswherePath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswherePath)) {
    $vswherePath = "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe"
}

$vsInstallPath = $null
if (Test-Path $vswherePath) {
    $vsInstallPath = & $vswherePath -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
}

if (-not $vsInstallPath -and -not $env:VCToolsVersion) {
    Write-Error-Custom "Visual Studio 2019+ with C++ tools not found."
    Write-Info "Please install Visual Studio with 'Desktop development with C++' workload"
    Write-Info "Or run this script from a Visual Studio Developer PowerShell"
    exit 1
}

if ($vsInstallPath) {
    Write-Info "Visual Studio found at: $vsInstallPath"
} elseif ($env:VCToolsVersion) {
    Write-Info "Visual Studio environment detected (version: $env:VisualStudioVersion)"
}

# Check for Clang-CL if requested
$clangClPath = $null
if ($UseClang) {
    $clangClPath = Get-Command clang-cl -ErrorAction SilentlyContinue
    if ($clangClPath) {
        Write-Info "Clang-CL found and will be used"
    } else {
        Write-Warning-Custom "Clang-CL not found, falling back to MSVC"
    }
}

# Setup build directory
$buildDir = Join-Path $scriptRoot "build"
Push-Location $scriptRoot

if ($Clean -and (Test-Path $buildDir)) {
    Write-Step "CLEAN" "Removing existing build directory..."
    Remove-Item -Recurse -Force $buildDir
}

if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir | Out-Null
}

# SIMD configuration
Write-Output ""
Write-Step "CONFIG" "Selecting SIMD variant..."

if ($SimdVariant -eq "All") {
    $simdFlags = "-DASTCENC_ISA_AVX2=ON", "-DASTCENC_ISA_SSE41=ON", "-DASTCENC_ISA_SSE2=ON"
    Write-Info "Building AVX2 + SSE4.1 + SSE2 variants"
} elseif ($SimdVariant -eq "AVX2") {
    $simdFlags = @("-DASTCENC_ISA_AVX2=ON")
    Write-Info "Building AVX2 variant"
} elseif ($SimdVariant -eq "SSE41") {
    $simdFlags = @("-DASTCENC_ISA_SSE41=ON")
    Write-Info "Building SSE4.1 variant"
} elseif ($SimdVariant -eq "SSE2") {
    $simdFlags = @("-DASTCENC_ISA_SSE2=ON")
    Write-Info "Building SSE2 variant"
} elseif ($SimdVariant -eq "Native") {
    $simdFlags = @("-DASTCENC_ISA_NATIVE=ON")
    Write-Info "Building native SIMD variant"
} else {
    $simdFlags = @("-DASTCENC_ISA_NONE=ON")
    Write-Info "Building without SIMD acceleration"
}

# Additional flags
$extraFlags = @()

if ($BuildTests) {
    if (-not (Test-Path "Source\GoogleTest\CMakeLists.txt")) {
        Write-Step "SUBMODULE" "Initializing GoogleTest..."
        git submodule update --init --recursive
    }
    $extraFlags += "-DASTCENC_UNITTEST=ON"
    Write-Info "Unit tests will be built"
}

if ($BuildShared) {
    $extraFlags += "-DASTCENC_SHAREDLIB=ON"
    Write-Info "Shared library will be built"
}

if ($UseClang -and $clangClPath) {
    $extraFlags += "-T ClangCL"
}

$werrorStr = if ($werror) { "ON" } else { "OFF" }

# Use absolute install prefix to avoid NMake relative path issues
$installPrefix = $scriptRoot

# Configure
Write-Output ""
Write-Step "CONFIGURE" "Running CMake configuration..."
Write-Info "Build type:  $BuildType"
Write-Info "Werror:      $werrorStr"
Write-Info "Install to:  $installPrefix"

Push-Location $buildDir

$cmakeArgs = @(
    "-G", "NMake Makefiles",
    "-DCMAKE_BUILD_TYPE=$BuildType",
    "-DCMAKE_INSTALL_PREFIX=`"$installPrefix`"",
    "-DASTCENC_CLI=ON",
    "-DASTCENC_WERROR=$werrorStr"
)

$cmakeArgs += $simdFlags
$cmakeArgs += $extraFlags
$cmakeArgs += "`"$scriptRoot`""

& cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "CMake configuration failed"
    Pop-Location
    Pop-Location
    exit 1
}

# Build
Write-Output ""
Write-Step "BUILD" "Compiling astcenc (this may take several minutes)..."

& nmake
if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "Build failed"
    Pop-Location
    Pop-Location
    exit 1
}

# Install
Write-Output ""
Write-Step "INSTALL" "Installing to bin/ directory..."

& nmake install
if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "Installation failed"
    Pop-Location
    Pop-Location
    exit 1
}

Pop-Location

# Run tests if built
if ($BuildTests) {
    Write-Output ""
    Write-Step "TEST" "Running unit tests..."

    Push-Location $buildDir
    & ctest --output-on-failure
    if ($LASTEXITCODE -ne 0) {
        Write-Warning-Custom "Some unit tests failed"
    } else {
        Write-Success "All unit tests passed"
    }
    Pop-Location
}

Pop-Location

# Summary
Write-Output ""
Write-ColorOutput "========================================" "Green"
Write-ColorOutput " Build completed successfully!" "Green"
Write-ColorOutput "========================================" "Green"
Write-Output ""

Write-Info "Installed binaries:"
$binDir = Join-Path $scriptRoot "bin"
if (Test-Path $binDir) {
    Get-ChildItem -Path $binDir -Filter "astcenc*.exe" | ForEach-Object {
        Write-Output "  $($_.Name)  ($([math]::Round($_.Length/1KB))KB)"
    }
} else {
    Write-Warning-Custom "bin/ directory not found - install may have failed"
}

Write-Output ""
Write-Info "Usage examples:"
Write-Output "  .\bin\astcenc-avx2.exe -cl input.png output.astc 6x6 -medium"
Write-Output "  .\bin\astcenc-avx2.exe -dl output.astc decoded.png"
Write-Output "  .\bin\astcenc-avx2.exe -help"
Write-Output ""
Write-Info "For detailed documentation, see Docs/Usage-Guide.md"
