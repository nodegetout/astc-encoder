@echo off
setlocal enabledelayedexpansion

echo ========================================
echo  ASTC Encoder Build Script for Windows
echo ========================================
echo.

REM Parse command line arguments
set "BUILD_TESTS=OFF"
set "BUILD_SHARED=OFF"
set "USE_CLANG=OFF"
set "BUILD_TYPE=Release"
set "WERROR=ON"

:parse_args
if "%~1"=="" goto :args_done
if /i "%~1"=="/tests" (
    set "BUILD_TESTS=ON"
    shift
    goto :parse_args
)
if /i "%~1"=="/shared" (
    set "BUILD_SHARED=ON"
    shift
    goto :parse_args
)
if /i "%~1"=="/clang" (
    set "USE_CLANG=ON"
    shift
    goto :parse_args
)
if /i "%~1"=="/debug" (
    set "BUILD_TYPE=Debug"
    shift
    goto :parse_args
)
if /i "%~1"=="/nowerror" (
    set "WERROR=OFF"
    shift
    goto :parse_args
)
if /i "%~1"=="/help" (
    echo Usage: build_windows.bat [options]
    echo.
    echo Options:
    echo   /tests     Build unit tests (requires GoogleTest submodule)
    echo   /shared    Build shared library in addition to static
    echo   /clang     Use Clang-CL toolchain if available (faster binaries)
    echo   /debug     Build debug version instead of release
    echo   /nowerror  Do not treat warnings as errors (useful for non-English locales)
    echo   /help      Show this help message
    echo.
    echo Interactive mode will prompt for SIMD selection.
    exit /b 0
)
shift
goto :parse_args

:args_done

REM Auto-detect non-English code page and disable WERROR if needed
for /f "tokens=3" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Nls\CodePage" /v ACP 2^>nul ^| findstr "ACP"') do set "SYSTEM_ACP=%%a"
if not "%SYSTEM_ACP%"=="1252" if not "%SYSTEM_ACP%"=="437" (
    if "%WERROR%"=="ON" (
        echo [INFO] Non-Latin code page detected (%SYSTEM_ACP%), disabling -Werror to avoid C4819 warnings.
        set "WERROR=OFF"
    )
)

REM Check if CMake is available
where cmake >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] CMake not found in PATH. Please install CMake 3.15+ and add it to PATH.
    echo Download from: https://cmake.org/download/
    pause
    exit /b 1
)

for /f "tokens=3" %%v in ('cmake --version ^| findstr "cmake version"') do set CMAKE_VERSION=%%v
echo [INFO] CMake version: %CMAKE_VERSION%

REM Check if we're in a Visual Studio environment
if not defined VCToolsVersion (
    echo [INFO] Visual Studio environment not detected, attempting auto-detection...

    set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
    if not exist "!VSWHERE!" set "VSWHERE=%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe"

    if exist "!VSWHERE!" (
        for /f "usebackq tokens=*" %%i in (`"!VSWHERE!" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
            set "VSINSTALLDIR=%%i"
        )
    )

    if defined VSINSTALLDIR (
        echo [INFO] Found Visual Studio at: !VSINSTALLDIR!
        call "!VSINSTALLDIR!\VC\Auxiliary\Build\vcvars64.bat" < nul
    ) else (
        echo [ERROR] Visual Studio 2019+ with C++ tools not found.
        echo Please run this script from a Visual Studio Developer Command Prompt.
        echo Or install Visual Studio with C++ desktop development workload.
        pause
        exit /b 1
    )
)

echo [INFO] Visual Studio version: %VisualStudioVersion%

if "%USE_CLANG%"=="ON" (
    where clang-cl >nul 2>&1
    if !errorlevel! equ 0 (
        echo [INFO] Clang-CL found and will be used
        set "CMAKE_TOOLCHAIN=-T ClangCL"
    ) else (
        echo [WARNING] Clang-CL not found, falling back to default MSVC compiler
    )
)

echo.

REM Resolve project root to absolute path
set "PROJECT_ROOT=%~dp0"
set "PROJECT_ROOT=%PROJECT_ROOT:~0,-1%"

REM Create build directory
set "BUILD_DIR=%PROJECT_ROOT%\build"
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

REM SIMD selection
if defined SIMD_FLAGS goto :simd_done

echo Select SIMD instruction set:
echo   1. AVX2 + SSE4.1 + SSE2 (recommended, builds all three variants)
echo   2. SSE4.1 + SSE2 only
echo   3. SSE2 only (universal compatibility, slowest)
echo   4. Native (auto-detect best for this CPU)
echo   5. None (no SIMD, reference implementation)
echo.
set /p CHOICE="Enter choice [1-5, default=1]: "

if "%CHOICE%"=="" set CHOICE=1

if "%CHOICE%"=="1" (
    set SIMD_FLAGS=-DASTCENC_ISA_AVX2=ON -DASTCENC_ISA_SSE41=ON -DASTCENC_ISA_SSE2=ON
    echo [INFO] Building AVX2 + SSE4.1 + SSE2 variants
) else if "%CHOICE%"=="2" (
    set SIMD_FLAGS=-DASTCENC_ISA_SSE41=ON -DASTCENC_ISA_SSE2=ON
    echo [INFO] Building SSE4.1 + SSE2 variants
) else if "%CHOICE%"=="3" (
    set SIMD_FLAGS=-DASTCENC_ISA_SSE2=ON
    echo [INFO] Building SSE2 variant only
) else if "%CHOICE%"=="4" (
    set SIMD_FLAGS=-DASTCENC_ISA_NATIVE=ON
    echo [INFO] Building native SIMD variant
) else if "%CHOICE%"=="5" (
    set SIMD_FLAGS=-DASTCENC_ISA_NONE=ON
    echo [INFO] Building without SIMD acceleration
) else (
    echo [ERROR] Invalid choice. Please enter 1-5.
    pause
    exit /b 1
)

:simd_done
echo.

REM Check for unit tests
if "%BUILD_TESTS%"=="ON" (
    if not exist "%PROJECT_ROOT%\Source\GoogleTest\CMakeLists.txt" (
        echo [INFO] GoogleTest submodule not found, initializing...
        pushd "%PROJECT_ROOT%"
        git submodule update --init --recursive
        popd
    )
    set "EXTRA_FLAGS=!EXTRA_FLAGS! -DASTCENC_UNITTEST=ON"
    echo [INFO] Unit tests will be built
)

if "%BUILD_SHARED%"=="ON" (
    set "EXTRA_FLAGS=!EXTRA_FLAGS! -DASTCENC_SHAREDLIB=ON"
    echo [INFO] Shared library will be built
)

REM Use absolute install prefix to avoid NMake relative path issues
set "INSTALL_PREFIX=%PROJECT_ROOT%"

echo.
echo [STEP 1/3] Configuring build with CMake...
echo            Build type:   %BUILD_TYPE%
echo            Werror:       %WERROR%
echo            Install to:   %INSTALL_PREFIX%
echo.

pushd "%BUILD_DIR%"

cmake -G "NMake Makefiles" ^
    -DCMAKE_BUILD_TYPE=%BUILD_TYPE% ^
    -DCMAKE_INSTALL_PREFIX="%INSTALL_PREFIX%" ^
    %SIMD_FLAGS% ^
    %EXTRA_FLAGS% ^
    -DASTCENC_CLI=ON ^
    -DASTCENC_WERROR=%WERROR% ^
    "%PROJECT_ROOT%"

if %errorlevel% neq 0 (
    echo [ERROR] CMake configuration failed.
    popd
    pause
    exit /b 1
)

echo.
echo [STEP 2/3] Building astcenc...
echo            This may take several minutes...
echo.

nmake

if %errorlevel% neq 0 (
    echo [ERROR] Build failed.
    popd
    pause
    exit /b 1
)

echo.
echo [STEP 3/3] Installing to bin/ directory...

nmake install

if %errorlevel% neq 0 (
    echo [ERROR] Installation failed.
    popd
    pause
    exit /b 1
)

popd

REM Run unit tests if built
if "%BUILD_TESTS%"=="ON" (
    echo.
    echo [TEST] Running unit tests...
    pushd "%BUILD_DIR%"
    ctest --output-on-failure
    if %errorlevel% neq 0 (
        echo [WARNING] Some unit tests failed.
    ) else (
        echo [INFO] All unit tests passed.
    )
    popd
)

echo.
echo ========================================
echo  Build completed successfully!
echo ========================================
echo.
echo Installed binaries in bin/:
dir /b "%PROJECT_ROOT%\bin\astcenc*.exe" 2>nul

if "%BUILD_SHARED%"=="ON" (
    echo.
    echo Shared libraries in bin/:
    dir /b "%PROJECT_ROOT%\bin\*.dll" 2>nul
)

echo.
echo Usage examples:
echo   bin\astcenc-avx2.exe -cl input.png output.astc 6x6 -medium
echo   bin\astcenc-avx2.exe -dl output.astc decoded.png
echo   bin\astcenc-avx2.exe -help
echo.
echo For detailed documentation, see Docs\Usage-Guide.md
echo.

pause
