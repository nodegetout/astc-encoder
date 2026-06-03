# astcenc 配置参数与使用文档

本文档详细介绍 astcenc 命令行工具和库 API 中所有可调参数，帮助用户根据实际需求进行精确配置。

---

## 1. 基本操作模式

### 1.1 命令格式总览

```bash
# 压缩
astcenc {-cl|-cs|-ch|-cH} <输入文件> <输出文件> <块尺寸> <质量预设> [选项]

# 解压
astcenc {-dl|-ds|-dh|-dH} <输入文件> <输出文件>

# 压缩测试（压缩后立即解压并输出质量指标）
astcenc {-tl|-ts|-th|-tH} <输入文件> <输出文件> <块尺寸> <质量预设> [选项]
```

### 1.2 颜色配置文件（Profile）

| 参数 | 模式 | 说明 |
|------|------|------|
| `-*l` | LDR linear | 仅支持线性 LDR，不使用 HDR 编码特性 |
| `-*s` | LDR sRGB | 仅支持 sRGB LDR，输入纹理必须是 sRGB 色彩空间 |
| `-*h` | HDR RGB + LDR A | 支持 HDR，RGB 通道为 HDR，Alpha 通道为 LDR |
| `-*H` | HDR RGBA | 支持 HDR，所有 4 个通道均为 HDR |

> **注意：** 并非所有 GPU 都支持 ASTC HDR 配置文件。sRGB 模式下 alpha 通道始终以线性方式编码。

### 1.3 支持的输入/输出格式

**压缩输入：**
- LDR：BMP、PNG、TGA、JPEG
- HDR：OpenEXR (.exr)、Radiance HDR (.hdr)
- 容器：KTX、DDS（仅支持 2D/2D-array/3D/Cube-map，仅读取第一个 mipmap）

**压缩输出：** ASTC (.astc)、KTX (.ktx)

**解压输入：** ASTC (.astc)、KTX (.ktx)

**解压输出：** LDR（BMP/PNG/TGA）、HDR（EXR/HDR）、容器（KTX/DDS）

---

## 2. 块尺寸（Block Size）与比特率

每个 ASTC 块固定压缩为 128 bit，因此块尺寸直接决定压缩比特率。

### 2.1 2D 块尺寸

| 块尺寸 | bpp | 块尺寸 | bpp | 块尺寸 | bpp |
|--------|------|--------|------|--------|------|
| 4×4 | 8.00 | 10×5 | 2.56 | 12×10 | 1.07 |
| 5×4 | 6.40 | 10×6 | 2.13 | 10×10 | 1.28 |
| 5×5 | 5.12 | 8×8 | 2.00 | 12×12 | 0.89 |
| 6×5 | 4.27 | 10×8 | 1.60 | | |
| 6×6 | 3.56 | | | | |
| 8×5 | 3.20 | | | | |
| 8×6 | 2.67 | | | | |

### 2.2 3D 块尺寸

| 块尺寸 | bpp | 块尺寸 | bpp |
|--------|------|--------|------|
| 3×3×3 | 4.74 | 5×5×4 | 1.28 |
| 4×3×3 | 3.56 | 5×5×5 | 1.02 |
| 4×4×3 | 2.67 | 6×5×5 | 0.85 |
| 4×4×4 | 2.00 | 6×6×5 | 0.71 |
| 5×4×4 | 1.60 | 6×6×6 | 0.59 |

> **建议：** 块尺寸越大比特率越低、压缩质量越差，但内存占用和带宽更小。建议实验找到质量与尺寸的最佳平衡点。

---

## 3. 质量预设（Quality Preset）

质量级别控制压缩器的搜索深度，值越高搜索越完整、质量越好，但压缩时间越长。

| 预设名称 | 等效 quality 值 | 适用场景 |
|----------|----------------|----------|
| `-fastest` | 0 | 快速预览，质量最低 |
| `-fast` | 10 | 快速迭代 |
| `-medium` | 60 | **生产推荐起点**，质量与速度平衡 |
| `-thorough` | 98 | 高质量生产 |
| `-verythorough` | 99 | 极高质量，时间显著增加 |
| `-exhaustive` | 100 | 最高质量，时间极长，收益递减 |

> **建议：** 生产内容至少使用 `-medium`。超过 `-thorough` 的级别压缩时间大幅增加但质量提升有限。也可以传入 0-100 之间的浮点数自定义质量级别。

---

## 4. 常用压缩选项

### 4.1 解码模式

```bash
-decode_unorm8
```

指示压缩器针对 `decode_unorm8` 扩展行为优化舍入（而非默认的 `decode_float16`）。如果运行时使用 RGBA8 中间格式解压，启用此选项可获得小幅质量提升。当解压输出为 8-bit 格式时自动启用。

### 4.2 法线贴图

```bash
-normal
```

将输入纹理视为三通道线性 LDR 法线贴图 (R=X, G=Y, B=Z)，输出为双通道 X+Y 法线贴图 (RGB=X, A=Y)。压缩器优化角度误差而非线性 PSNR。

shader 中 Z 分量重建方式：
```glsl
nml.xy = texture(...).ga;                // 加载 [0,1]
nml.xy = nml.xy * 2.0 - 1.0;            // 解包到 [-1,1]
nml.z  = sqrt(1 - dot(nml.xy, nml.xy)); // 计算 Z
```

如需匹配 BC5n 分量顺序，使用 `-normal -esw gggr` 压缩，`-normal -dsw arz1` 解压。

### 4.3 RGBM 编码

```bash
-rgbm <max>
```

输入为 RGBM 编码的 HDR 纹理，以 LDR 容器存储，共享乘数。shader 重建方式：
```glsl
vec3 hdr = tex.rgb * tex.a * max;
```

> **重要：** M 值必须保持在下阈值以上（建议 16/255 或 32/255），否则量化为零会导致黑/白像素。

### 4.4 感知压缩

```bash
-perceptual
```

优化感知误差而非直接 RMS 误差。通常会降低 PSNR 分数但提升主观视觉质量。目前仅支持法线贴图和 RGB 颜色数据。

### 4.5 通道权重

```bash
-cw <红> <绿> <蓝> <Alpha>
```

为每个颜色通道分配额外权重缩放。值 >1 增加通道重要性，<1 降低重要性，=0 从误差计算中排除该通道。

**示例：** 绿色通道编码质量差时使用 `-cw 1 6 1 1`。

### 4.6 Alpha 加权

```bash
-a <radius>
```

按 alpha 值缩放逐纹素权重。radius 为 0 时仅使用该纹素自身的 alpha。全零权重的 ASTC 块会被替换为常色块（类似 RDO 技术，提升后续压缩率）。

> **建议：** 对使用线性纹理过滤的透明纹理，radius 设为 1 以减少透明纹素对相邻非透明纹素的颜色渗透。

### 4.7 通道重排（Swizzle）

| 参数 | 作用 | 字符集 |
|------|------|--------|
| `-esw <swizzle>` | 编码前重排通道 | `rgba01` |
| `-ssw <swizzle>` | 指定 shader 实际采样通道（影响误差计算） | `rgba` |
| `-dsw <swizzle>` | 解压后重排通道 | `rgba01z` |

**推荐编码 swizzle 表：**

| 输入分量数 | 编码 swizzle | 采样 swizzle | 说明 |
|-----------|-------------|-------------|------|
| 1 | `rrr1` | `.g` | 亮度 + 常量 1 |
| 2 | `rrrg` | `.ga` | 亮度 + Alpha |
| 3 | `rgb1` | `.rgb` | RGB + 常量 1 |
| 4 | `rgba` | `.rgba` | 标准 RGBA |

> **示例：** 交换 RG 通道并将 Alpha 替换为 1：`-esw grb1`

### 4.8 3D 图像

```bash
-zdim <切片数>
```

加载多个 2D 图像切片作为 3D 图像。输入文件名会被装饰为 `input_0.png`、`input_1.png` 等。

### 4.9 预处理

```bash
-pp-normalize      # 强制法线向量归一化为单位长度
-pp-premultiply    # RGB 分量乘以 alpha 值
```

### 4.10 其他

```bash
-yflip             # 压缩前垂直翻转，解压后翻转回来
-j <线程数>        # 指定线程数（默认 = CPU 核心数）
-silent            # 静默模式，仅输出必要信息和错误
```

---

## 5. 高级压缩调优参数

这些参数提供对压缩启发式算法的精细控制。默认值随块比特率变化分为三档：高比特率（<25 texels/block）、中比特率（25-63）、低比特率（≥64）。以下默认值为高比特率档位。

### 5.1 分区搜索控制

#### `-partitioncountlimit <N>`

每个块最多测试 N 个分区。范围 1-4。

| 预设 | 默认值 |
|------|--------|
| fastest | 2 |
| fast | 3 |
| medium/thorough/verythorough/exhaustive | 4 |

#### `-[2|3|4]partitionindexlimit <N>`

对应分区数下的块分区索引搜索数量。范围 1-1024。

| 预设 | 2分区 | 3分区 | 4分区 |
|------|-------|-------|-------|
| fastest | 10 | 6 | 4 |
| fast | 18 | 10 | 8 |
| medium | 34 | 28 | 16 |
| thorough | 82 | 60 | 30 |
| verythorough | 256 | 128 | 64 |
| exhaustive | 512 | 512 | 512 |

#### `-[2|3|4]partitioncandidatelimit <N>`

对应分区数下的候选分区方案数量。

| 预设 | 2分区 | 3分区 | 4分区 |
|------|-------|-------|-------|
| fastest/fast/medium | 2 | 2 | 2 |
| thorough | 3 | 2 | 2 |
| verythorough | 20 | 14 | 8 |
| exhaustive | 32 | 32 | 32 |

### 5.2 块模式搜索

#### `-blockmodelimit <N>`

测试使用频率低于第 N 百分位的块模式。范围 1-100。对 3D 纹理无效。

| 预设 | 默认值 |
|------|--------|
| fastest | 43 |
| fast | 55 |
| medium | 77 |
| thorough | 94 |
| verythorough | 98 |
| exhaustive | 100 |

### 5.3 迭代精化

#### `-refinementlimit <N>`

颜色和权重的迭代精化次数。最小值 1，通常超过 4 收益极小。

| 预设 | 默认值 |
|------|--------|
| fastest | 2 |
| fast/medium | 3 |
| thorough/verythorough/exhaustive | 4 |

#### `-candidatelimit <N>`

每个块模式试验的候选编码数。

| 预设 | 默认值 |
|------|--------|
| fastest | 2 |
| fast/medium | 3 |
| thorough | 4 |
| verythorough | 6 |
| exhaustive | 8 |

### 5.4 提前退出条件

#### `-dblimit <dB>`

当块 PSNR 超过此阈值时停止该块的压缩。对 HDR 纹理无效。

| 预设 | 默认值（N = 块内纹素数） |
|------|--------------------------|
| fastest/fast | MAX(63-19·log₁₀(N), 85-35·log₁₀(N)) |
| medium | MAX(70-19·log₁₀(N), 95-35·log₁₀(N)) |
| thorough | MAX(77-19·log₁₀(N), 105-35·log₁₀(N)) |
| verythorough/exhaustive | 999（即不提前退出） |

#### `-[2|3]partitionlimitfactor <factor>`

2/3 分区相比 1/2 分区误差降低因子低于此值时跳过更多分区测试。法线贴图中会进一步缩放以减少跳过。

| 预设 | 2分区因子 | 3分区因子 |
|------|-----------|-----------|
| fastest/fast | 1.00 | 1.00 |
| medium | 1.10 | 1.05 |
| thorough | 1.35 | 1.15 |
| verythorough | 1.60 | 1.40 |
| exhaustive | 2.00 | 2.00 |

#### `-2planelimitcorrelation <factor>`

颜色分量间最小相关因子低于此阈值时才尝试双权重平面。对法线贴图无效。

| 预设 | 默认值 |
|------|--------|
| fastest | 0.50 |
| fast | 0.65 |
| medium | 0.85 |
| thorough | 0.95 |
| verythorough | 0.98 |
| exhaustive | 0.99 |

---

## 6. 库 API 参数（`astcenc_config` 结构体）

通过 C/C++ API 使用时，`astcenc_config_init()` 初始化配置后，可在调用 `astcenc_context_alloc()` 前手动修改 `astcenc_config` 中的字段。

### 6.1 基础字段

| 字段 | 类型 | 说明 | CLI 对应 |
|------|------|------|----------|
| `profile` | `astcenc_profile` | 颜色配置 | `-cl/-cs/-ch/-cH` |
| `flags` | `unsigned int` | 标志位组合 | 见下方 |
| `block_x/y/z` | `unsigned int` | 块尺寸 | 块尺寸参数 |
| `cw_r/g/b/a_weight` | `float` | 通道误差权重 | `-cw` |
| `a_scale_radius` | `unsigned int` | Alpha 加权半径 | `-a` |
| `rgbm_m_scale` | `float` | RGBM 乘数因子（默认 5） | `-rgbm` |

### 6.2 标志位（flags）

| 标志 | 说明 |
|------|------|
| `ASTCENC_FLG_MAP_NORMAL` | 法线贴图模式，优化角度误差 |
| `ASTCENC_FLG_MAP_RGBM` | RGBM 编码模式 |
| `ASTCENC_FLG_USE_ALPHA_WEIGHT` | Alpha 加权 |
| `ASTCENC_FLG_USE_PERCEPTUAL` | 感知误差优化 |
| `ASTCENC_FLG_USE_DECODE_UNORM8` | 针对 decode_unorm8 优化 |
| `ASTCENC_FLG_DECOMPRESS_ONLY` | 仅解压上下文（节省内存） |
| `ASTCENC_FLG_SELF_DECOMPRESS_ONLY` | 仅保证解压自身压缩的数据（加速上下文创建） |

### 6.3 调优字段（对应 CLI 高级参数）

| 字段 | CLI 对应 | 范围 |
|------|----------|------|
| `tune_partition_count_limit` | `-partitioncountlimit` | 1-4 |
| `tune_2/3/4partition_index_limit` | `-[2\|3\|4]partitionindexlimit` | 1-1024 |
| `tune_2/3/4partitioning_candidate_limit` | `-[2\|3\|4]partitioncandidatelimit` | ≥1 |
| `tune_block_mode_limit` | `-blockmodelimit` | 1-100 |
| `tune_refinement_limit` | `-refinementlimit` | ≥1 |
| `tune_candidate_limit` | `-candidatelimit` | ≥1 |
| `tune_db_limit` | `-dblimit` | float |
| `tune_mse_overshoot` | — | float |
| `tune_2partition_early_out_limit_factor` | `-2partitionlimitfactor` | float |
| `tune_3partition_early_out_limit_factor` | `-3partitionlimitfactor` | float |
| `tune_2plane_early_out_limit_correlation` | `-2planelimitcorrelation` | float |
| `tune_search_mode0_enable` | — | float |

### 6.4 进度回调

```c
config.progress_callback = my_callback; // 类型为 void (*)(float)
```

压缩过程中周期性报告进度（0-100%）。回调在压缩线程中执行，避免在回调中做耗时操作。

### 6.5 API 使用示例

```cpp
#include "astcenc.h"

// 1. 初始化配置
astcenc_config config;
astcenc_config_init(
    ASTCENC_PRF_LDR,       // 颜色配置
    6, 6, 1,               // 块尺寸 6x6
    ASTCENC_PRE_MEDIUM,     // 质量预设
    ASTCENC_FLG_USE_PERCEPTUAL, // 感知压缩
    &config);

// 2. 可选：手动微调参数
config.cw_g_weight = 6.0f;       // 加大绿色通道权重
config.tune_refinement_limit = 4; // 增加精化迭代

// 3. 分配上下文
astcenc_context* ctx;
astcenc_context_alloc(&config, thread_count, &ctx, nullptr);

// 4. 压缩
astcenc_image image;
image.dim_x = width;
image.dim_y = height;
image.dim_z = 1;
image.data_type = ASTCENC_TYPE_U8;
uint8_t* slice = pixel_data;
image.data = (void**)&slice;

astcenc_swizzle swz = {ASTCENC_SWZ_R, ASTCENC_SWZ_G, ASTCENC_SWZ_B, ASTCENC_SWZ_A};
size_t out_len = block_count_x * block_count_y * 16;
uint8_t* out = new uint8_t[out_len];

astcenc_compress_image(ctx, &image, &swz, out, out_len, 0);

// 5. 多图像复用时重置上下文
astcenc_compress_reset(ctx);

// 6. 清理
astcenc_context_free(ctx);
delete[] out;
```

---

## 7. 多线程策略

astcenc 支持两种多线程方式：

### 7.1 单图多线程

```cpp
// 创建上下文时指定线程数
astcenc_context_alloc(&config, thread_count, &ctx, nullptr);

// 每个线程调用一次 compress_image，thread_index 不同
// 工作自动动态调度
for (int i = 0; i < thread_count; i++)
    astcenc_compress_image(ctx, &image, &swz, out, out_len, i);

// 所有线程完成后重置
astcenc_compress_reset(ctx);
```

### 7.2 多图并行

```cpp
// 每个线程分配独立上下文，共享只读数据表
astcenc_context_alloc(&config, 1, &ctx[i], parent_context);
```

子上下文从父上下文继承只读数据表，节省大量内存。

---

## 8. 等效其他压缩格式的配置

| 目标格式 | 编码 swizzle | 采样 swizzle | 说明 |
|----------|-------------|-------------|------|
| BC1 | `rgba` | `.rgba` | 无 1-bit 穿透 alpha |
| BC3 / BC7 | `rgba` | `.rgba` | 标准 RGBA |
| BC3nm | `gggr` | `.ag` | 法线贴图 |
| BC4 / EAC_R11 | `rrr1` | `.r` | 单通道亮度 |
| BC5 / EAC_RG11 | `rrrg` | `.ra` | 双通道 L+A |
| BC6H | `rgb1` | `.rgb` | 仅 HDR 配置文件，无符号模式 |
| ETC1 | `rgb1` | `.rgb` | 3 通道 RGB |
| ETC2 / ETC2+EAC | `rgba` | `.rgba` | 标准 RGBA |

---

## 9. 构建时参数

以下参数在 CMake 配置阶段设定，影响编译产物：

| CMake 选项 | 说明 |
|-----------|------|
| `ASTCENC_BLOCK_MAX_TEXELS` | 限制最大块纹素数（144 = 仅 2D，216 = 含 3D） |
| `ASTCENC_INVARIANCE=OFF` | 启用 FMA 指令，性能提升 10-15%，质量降低约 0.2dB |
| `ASTCENC_DECOMPRESSOR=ON` | 构建仅解压库（减小约 180KB） |
| `ASTCENC_SHAREDLIB=ON` | 构建共享库 |
| `ASTCENC_X86_GATHERS=OFF` | 禁用 x86 gather 指令（某些微架构上更快） |

---

## 10. Windows 一键构建脚本

项目提供两种 Windows 构建脚本，自动完成环境检测、CMake 配置、编译和安装，无需手动执行 `cmake` 命令。

### 10.1 批处理脚本 `build_windows.bat`

双击或在命令行中运行即可。默认会弹出交互式菜单选择 SIMD 指令集。

**命令行参数：**

| 参数 | 说明 |
|------|------|
| `/tests` | 构建单元测试（自动初始化 GoogleTest 子模块） |
| `/shared` | 同时构建共享库（DLL） |
| `/clang` | 使用 Clang-CL 工具链（生成更快的二进制文件） |
| `/debug` | 构建 Debug 版本（默认为 Release） |
| `/nowerror` | 不将警告视为错误（非英语区域设置时自动启用） |
| `/help` | 显示帮助信息 |

**交互式 SIMD 选择：**

运行后会出现以下菜单：

```text
Select SIMD instruction set:
  1. AVX2 + SSE4.1 + SSE2 (recommended, builds all three variants)
  2. SSE4.1 + SSE2 only
  3. SSE2 only (universal compatibility, slowest)
  4. Native (auto-detect best for this CPU)
  5. None (no SIMD, reference implementation)
```

**使用示例：**

```powershell
# 默认构建（交互式选择 SIMD）
build_windows.bat

# 构建含单元测试的 Release 版本，使用 Clang-CL
build_windows.bat /tests /clang

# Debug 构建，不启用 Werror
build_windows.bat /debug /nowerror
```

### 10.2 PowerShell 脚本 `build_windows.ps1`

功能更丰富的 PowerShell 构建脚本，支持参数验证、颜色输出和自动并行编译。

**参数：**

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `-SimdVariant` | `AVX2`/`SSE41`/`SSE2`/`Native`/`None`/`All` | `All` | SIMD 指令集变体 |
| `-BuildType` | `Release`/`Debug`/`RelWithDebInfo` | `Release` | 构建类型 |
| `-BuildTests` | switch | — | 构建并运行单元测试 |
| `-BuildShared` | switch | — | 同时构建共享库 |
| `-UseClang` | switch | — | 使用 Clang-CL 工具链 |
| `-NoWerror` | switch | — | 不将警告视为错误 |
| `-Clean` | switch | — | 构建前清理 build 目录 |
| `-Jobs` | int (1-64) | CPU 核心数 | 并行编译任务数 |

**使用示例：**

```powershell
# 构建所有 SIMD 变体（AVX2 + SSE4.1 + SSE2）
.\build_windows.ps1

# 仅构建 AVX2 版本
.\build_windows.ps1 -SimdVariant AVX2

# 构建含测试的 Debug 版本，使用 Clang-CL，构建前清理
.\build_windows.ps1 -SimdVariant All -BuildTests -UseClang -Clean -BuildType Debug

# 仅构建 SSE2，指定 4 个并行任务
.\build_windows.ps1 -SimdVariant SSE2 -Jobs 4
```

### 10.3 前提条件

两个脚本都会自动检查以下依赖：

- **CMake 3.15+**：必须在 PATH 中可用。可从 [cmake.org](https://cmake.org/download/) 下载。
- **Visual Studio 2019+**：需安装"使用 C++ 的桌面开发"工作负载。脚本会通过 `vswhere.exe` 自动检测安装路径。
- **Clang-CL**（可选）：仅在指定 `/clang` 或 `-UseClang` 时需要。

> **提示：** 脚本会自动检测非拉丁编码页（如中文 936、韩文 949），并禁用 `-Werror` 以避免 C4819 编译警告。

### 10.4 构建产物

构建成功后，可执行文件安装到项目根目录的 `bin/` 文件夹：

```text
bin/
├── astcenc-avx2.exe      # AVX2 版本（最快，需 CPU 支持）
├── astcenc-sse4.1.exe    # SSE4.1 版本
├── astcenc-sse2.exe      # SSE2 版本（兼容性最好）
└── ...
```

如果启用了共享库（`/shared` 或 `-BuildShared`），还会生成对应的 `.dll` 文件。

---

## 11. 实践建议

1. **从 `-medium` 和 6×6 块开始**，这是质量与速度的最佳平衡起点
2. **减少分量数以节省比特** — 单通道数据用 `rrr1`、双通道用 `rrrg`，避免浪费编码空间
3. **法线贴图始终用 `-normal`** — 角度误差优化比 PSNR 优化更适合法线数据
4. **使用 `-decode_unorm8`** — 如果运行时使用 RGBA8 解压（大多数 LDR 场景）
5. **遇到块效应时提高质量预设** — `-thorough` 或更高
6. **mask 纹理用 `-cw` 调整** — 某些通道质量差时提高对应权重
7. **Alpha 透明纹理配合 `-a 1`** — 减少颜色渗透
8. **sRGB 纹理用 `-cs`** — 感知质量优于线性 LDR
