# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Arm ASTC Encoder (`astcenc`) — a C++14 command-line tool and library for compressing/decompressing images using the Adaptive Scalable Texture Compression (ASTC) standard. Version 5.4.0. Licensed under Apache 2.0.

The library API (`astcenc.h`) follows semantic versioning since 5.4.0. Breaking changes require a major version bump and are designed to cause compilation failures.

## Build Commands

### Configure (Windows, from project root)

```powershell
mkdir build; cd build

# x86-64 with Visual Studio (ClangCL recommended)
cmake -G "Visual Studio 16 2019" -T ClangCL -DCMAKE_INSTALL_PREFIX=..\ -DASTCENC_ISA_AVX2=ON -DASTCENC_ISA_SSE41=ON -DASTCENC_ISA_SSE2=ON ..

# x86-64 with NMake
cmake -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=..\ -DASTCENC_ISA_AVX2=ON -DASTCENC_ISA_SSE41=ON -DASTCENC_ISA_SSE2=ON ..
```

### Build and Install

```powershell
cd build
nmake install    # or: cmake --build . --config Release
```

Binaries are named by SIMD variant: `astcenc-sse2`, `astcenc-sse4.1`, `astcenc-avx2`, `astcenc-neon`, `astcenc-sve_128`, `astcenc-sve_256`, `astcenc-none`, `astcenc-native`.

### Useful CMake Options

| Option | Purpose |
|---|---|
| `-DASTCENC_ISA_AVX2=ON` | Enable AVX2 backend |
| `-DASTCENC_ISA_SSE41=ON` | Enable SSE4.1 backend |
| `-DASTCENC_ISA_SSE2=ON` | Enable SSE2 backend |
| `-DASTCENC_ISA_NEON=ON` | Enable NEON backend (Arm) |
| `-DASTCENC_ISA_NONE=ON` | No SIMD (reference fallback) |
| `-DASTCENC_ISA_NATIVE=ON` | Compiler's default SIMD |
| `-DASTCENC_UNITTEST=ON` | Build unit tests (requires GoogleTest submodule) |
| `-DASTCENC_DECOMPRESSOR=ON` | Build decompress-only variant |
| `-DASTCENC_SHAREDLIB=ON` | Build shared library |
| `-DASTCENC_INVARIANCE=OFF` | Enable FMA/non-invariant FP (faster, ~0.2dB quality loss) |
| `-DASTCENC_BLOCK_MAX_TEXELS=144` | Limit block sizes (144 = all 2D blocks) |
| `-DASTCENC_ASAN=ON` / `-DASTCENC_UBSAN=ON` | Sanitizer builds (Linux/macOS Clang) |

## Testing

### Unit Tests (C++, GoogleTest)

```powershell
# First time only:
git submodule init && git submodule update

# Configure with tests:
cmake -DASTCENC_UNITTEST=ON -DASTCENC_ISA_AVX2=ON ..

# Build then run:
cd build && ctest --verbose
```

Unit test sources are in [Source/UnitTest/](Source/UnitTest/) — covers decode, SIMD, and softfloat.

### Functional Tests (Python CLI tests)

Requires Python 3.12, numpy, Pillow. Binaries must be installed to `./bin` first.

```sh
python ./Test/astc_test_functional.py -v --encoder <variant>
# e.g.: python ./Test/astc_test_functional.py -v --encoder avx2
```

### Image Quality / Performance Tests (Python)

```sh
python ./Test/astc_test_image.py --encoder <variant> --test-set Small
```

Compares PSNR against reference CSVs. Use `--repeats` for stable perf data.

## Architecture

### Two-Layer Structure

**Core library** (`astcenc-*-static` / `astcenc-*-shared`) — the codec itself:
- Public API: [astcenc.h](Source/astcenc.h) — context-based compress/decompress. Thread-safe via per-thread context invocation.
- Internal types: [astcenc_internal.h](Source/astcenc_internal.h) — block/partition/weight data structures
- Threading model: [astcenc_internal_entry.h](Source/astcenc_internal_entry.h) — atomic counter-based task dispatch, no main thread in pool

**CLI tool** (`astcenc-*`) — command-line frontend:
- Entry: [astcenccli_entry.cpp](Source/astcenccli_entry.cpp) (compiled without SIMD for ISA compat checks) → [astcenccli_entry2.cpp](Source/astcenccli_entry2.cpp) (compiled with SIMD but no vector-length overrides for SVE checks) → main logic in [astcenccli_toplevel.cpp](Source/astcenccli_toplevel.cpp)
- Image I/O uses stb_image, stb_image_write, tinyexr (vendored in [Source/ThirdParty/](Source/ThirdParty/))
- Supports BMP, JPEG, PNG, TGA (LDR) and EXR, HDR (HDR), plus DDS/KTX containers

### Compression Pipeline

The compression flow for each block:
1. **Variance/averages** — compute per-partition statistics ([astcenc_averages_and_directions.cpp](Source/astcenc_averages_and_directions.cpp), [astcenc_compute_variance.cpp](Source/astcenc_compute_variance.cpp))
2. **Partition selection** — find best partitioning via k-means clustering ([astcenc_find_best_partitioning.cpp](Source/astcenc_find_best_partitioning.cpp))
3. **Ideal endpoints/weights** — compute ideal color endpoints and interpolation weights ([astcenc_ideal_endpoints_and_weights.cpp](Source/astcenc_ideal_endpoints_and_weights.cpp))
4. **Endpoint format selection** — pick best quantized endpoint encoding ([astcenc_pick_best_endpoint_format.cpp](Source/astcenc_pick_best_endpoint_format.cpp))
5. **Color quantize/unquantize** — quantize endpoints to bit budget ([astcenc_color_quantize.cpp](Source/astcenc_color_quantize.cpp))
6. **Weight alignment/quantization** — quantize weights and align to grid ([astcenc_weight_align.cpp](Source/astcenc_weight_align.cpp))
7. **Symbolic→physical** — pack symbolic representation into ASTC bitstream ([astcenc_symbolic_physical.cpp](Source/astcenc_symbolic_physical.cpp))

Decompression reverses this: physical→symbolic→color unquantize→interpolate ([astcenc_decompress_symbolic.cpp](Source/astcenc_decompress_symbolic.cpp)).

### SIMD Abstraction (vecmathlib)

[astcenc_vecmathlib.h](Source/astcenc_vecmathlib.h) provides a vector-length-agnostic API with types `vfloat`, `vint`, `vmask` that take on the widest available SIMD width. Backend headers:

| Header | Width | ISA |
|---|---|---|
| `astcenc_vecmathlib_sse_4.h` | 4-wide | SSE2/SSE4.1 |
| `astcenc_vecmathlib_avx2_8.h` | 8-wide | AVX2 |
| `astcenc_vecmathlib_neon_4.h` | 4-wide | NEON |
| `astcenc_vecmathlib_sve_8.h` | 8-wide | SVE (128/256-bit) |
| `astcenc_vecmathlib_rvv_n.h` | N-wide | RISC-V Vector |
| `astcenc_vecmathlib_none_4.h` | 4-wide | Scalar fallback |
| `astcenc_vecmathlib_common_4.h` | 4-wide | Shared helpers |

SIMD is selected at compile time via preprocessor defines (`ASTCENC_SSE`, `ASTCENC_AVX`, `ASTCENC_NEON`, `ASTCENC_SVE`). There is no runtime dispatch — each binary is built for a specific ISA.

### Build System

CMake generates one target per enabled SIMD variant. Each variant produces:
- `astcenc-<isa>-static` — static library (core codec)
- `astcenc-<isa>-shared` — shared library (if `ASTCENC_SHAREDLIB=ON`)
- `astcenc-<isa>` — CLI executable (if `ASTCENC_CLI=ON`, linked against `-static`)
- Two veneer libraries (`-veneer1`, `-veneer2`) compiled at lower ISA levels for safe runtime ISA detection

macOS supports universal binary builds (SSE4.1 + AVX2 + NEON slices via `lipo`).

Build configuration per-variant is in [Source/cmake_core.cmake](Source/cmake_core.cmake). Compiler flag setup is in `Source/cmake_compiler.cmake`.

### Key Conventions

- All source files use `astcenc_` prefix for library, `astcenccli_` prefix for CLI
- Compression code is guarded by `#if !defined(ASTCENC_DECOMPRESS_ONLY)`
- Floating-point invariance is enforced by default (`ASTCENC_INVARIANCE=ON`) — no FMA, no FP contraction
- The `promise()` macro provides compiler hints for loop optimization (see [astcenc_internal.h:47](Source/astcenc_internal.h#L47))
- Quality presets defined in [astcenc_entry.cpp](Source/astcenc_entry.cpp) (`astcenc_preset_config`) control the compression time/quality tradeoff
