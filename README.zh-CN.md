# 简介

**[English](README.md)**

Arm® 自适应可扩展纹理压缩（ASTC）编码器 `astcenc` 是一个命令行工具，用于使用 ASTC 纹理压缩标准对图像进行压缩和解压。

## ASTC 格式

ASTC 压缩数据格式由 Arm® 和 AMD 联合开发，已被 OpenGL®、OpenGL ES 和 Vulkan® 图形 API 采纳为官方扩展。它在给定比特率下的图像质量以及内容创作者可用的格式和比特率灵活性方面都带来了重大进步。这使得更多资产可以使用压缩，通常比其他格式更低的比特率，从而减少内存存储和带宽需求。

阅读 [ASTC 格式概述][1] 可快速了解该格式，或阅读完整的 [Khronos 数据格式规范][2] 获取所有细节。

## 许可证

本项目基于 Apache 2.0 许可证授权。下载本仓库中的任何组件即表示您接受 [LICENSE.txt](LICENSE.txt) 文件中规定的条款。

# 编码器功能支持

编码器支持低动态范围（BMP、JPEG、PNG、TGA）和高动态范围（EXR、HDR）图像的压缩，以及 DDS 和 KTX 容器格式包装的图像数据子集，输出为 ASTC 或 KTX 格式图像。

解码器支持将 ASTC 或 KTX 格式输入图像解压为低动态范围（BMP、PNG、TGA）、高动态范围（EXR、HDR）或 DDS 和 KTX 包装的输出图像。

编码器允许通过 `exhaustive`、`verythorough`、`thorough`、`medium`、`fast` 和 `fastest` 编码质量预设来控制压缩时间与质量的权衡。

编码器允许通过报告压缩时间和输入图像与压缩输出之间的峰值信噪比（PSNR）来进行压缩时间和质量分析。

## ASTC 格式支持

`astcenc` 压缩器支持生成 ASTC 规范允许的三种配置文件的所有图像：

* 2D 低动态范围（LDR 配置文件）
* 2D LDR 和高动态范围（HDR 配置文件）
* 2D 和 3D，LDR 和 HDR（完整配置文件）

它还支持所有 ASTC 块尺寸和压缩模式，允许内容创作者使用从 0.89 比特/像素到 8 比特/像素的全范围质量-比特率选项。

# 预编译二进制文件

`astcenc` 稳定版本的预编译二进制文件可在 [GitHub Releases 页面][3] 获取。

* 更新日志：[5.x 系列](./Docs/ChangeLog-5x.md)

提供 Windows、macOS 和 Linux 的 64 位构建版本。

## Windows 和 Linux

Windows 和 Linux 提供多个二进制文件，每个文件针对特定 SIMD 指令集进行了优化。

x86-64 平台提供以下版本，按性能递增排列：

* `astcenc-sse2` - 使用 SSE2
* `astcenc-sse4.1` - 使用 SSE4.1 和 POPCNT
* `astcenc-avx2` - 使用 AVX2、SSE4.2、POPCNT 和 F16C

x86-64 SSE2 构建版本可在所有 x86-64 机器上运行，但性能最慢。其他两个版本需要扩展的 CPU 指令集支持，并非所有 CPU 都支持，但每个版本都能获得约 15% 的性能提升。

Arm 平台提供以下版本，按性能递增排列：

* `astcenc-sve_256` - 使用 256 位 SVE
* `astcenc-sve_128` - 使用 128 位 SVE
* `astcenc-neon` - 使用 NEON

注意：Arm 可扩展向量扩展（SVE）允许 CPU 具有可变的向量长度。astcenc 的实现不是以长度无关的方式编写的，需要二进制文件与主机 CPU 上的向量长度匹配。

## macOS

对于 macOS 设备，提供单一通用二进制文件 `astcenc`，允许操作系统自动为当前主机使用正确的二进制变体。支持三种架构切片：

* `x86_64` - 使用上述 `astcenc-sse4.1` 构建版本。
* `x86_64h` - 使用上述 `astcenc-avx2` 构建版本。
* `arm64` - 使用上述 `astcenc-neon` 构建版本。

## 仓库分支

`main` 分支是压缩器的活跃开发分支。它旨在成为最新主要发布系列的稳定分支，但由于用于持续开发，预计会有一定的波动。建议生产开发使用最新的稳定发布标签。

`4.x` 分支是较旧的 4.x 发布系列的稳定分支。它不再处于活跃开发状态，但是一个受支持的分支，会继续获得向后移植的错误修复。

`1.x`、`2.x` 和 `3.x` 分支是旧版本的遗留分支。它们不再处于活跃开发状态，也不会再获得安全或错误修复，并计划于 2026 年 8 月底删除。建议仍在使用旧分支的开发人员迁移到最新的 5.x 系列稳定发布标签。

您可能找到的任何其他分支都是用于新功能或优化的开发分支，可能值得一试，但应被视为临时的和不稳定的。

# 快速入门

打开终端，切换到系统的相应目录，运行 astcenc 编码器程序，在 Linux 或 macOS 上如下所示：

    ./astcenc

... 或在 Windows 上：

    astcenc

调用 `astcenc -help` 可获得详细的帮助信息，包括使用说明和所有可用命令行选项的详情。以下是主要编码器选项的摘要。

## 压缩图像

使用 `-cl` \ `-cs` \ `-ch` \ `-cH` 模式压缩图像。例如：

    astcenc -cl example.png example.astc 6x6 -medium

这使用 LDR 颜色配置文件和 6x6 块大小（3.56 比特/像素）压缩 `example.png`。`-medium` 质量预设在较快的压缩速度下提供合理的图像质量，因此是压缩的良好起点。输出存储为线性颜色空间压缩图像 `example.astc`。

可用模式包括：

* `-cl`：使用线性 LDR 颜色配置文件。
* `-cs`：使用 sRGB LDR 颜色配置文件。
* `-ch`：使用 HDR 颜色配置文件，针对 HDR RGB 和 LDR A 优化。
* `-cH`：使用 HDR 颜色配置文件，针对 HDR RGBA 优化。

如果您打算将生成的图像与解码模式扩展一起使用以将解压精度限制为 UNORM8，建议同时指定 `-decode_unorm8` 标志。这将确保压缩器在选择编码时使用正确的舍入规则。

## 解压图像

使用 `-dl` \ `-ds` \ `-dh` \ `-dH` 模式解压图像。例如：

    astcenc -dh example.astc example.tga

这使用完整 HDR 功能配置文件解压 `example.astc`，将解压后的输出存储到 `example.tga`。

可用模式与压缩选项对应，但使用 `d` 前缀。注意对于解压，两种 HDR 模式之间没有区别，它们仅为保持操作对称性而同时提供。

## 测量图像质量

使用 `-tl` \ `-ts` \ `-th` \ `-tH` 模式查看压缩质量。例如：

    astcenc -tl example.png example.tga 5x5 -thorough

这相当于使用 LDR 颜色配置文件和 5x5 块大小压缩图像，使用 `-thorough` 质量预设，然后立即解压图像并保存结果。这可以用于对压缩图像质量进行视觉检查。此外，此模式还会将一些图像质量指标打印到控制台。

可用模式与压缩选项对应，但使用 `t` 前缀。

## 实验调整

高效的实时图形渲染受益于最小化压缩纹理大小，因为这会减少内存占用、降低内存带宽、节省能源，并可以提高纹理缓存效率。然而，与任何有损压缩格式一样，当没有足够的比特来表示所需精度的输出时，压缩图像质量会变得不可接受。我们建议尝试不同的块大小以找到大小和质量之间的最佳平衡，因为精细可调的压缩比是 ASTC 格式的主要优势之一。

压缩速度可以从 `-fastest`，到 `-fast`、`-medium` 和 `-thorough`，直到 `-exhaustive`。一般来说，编码器花更多时间寻找好的编码会产生更好的结果，但确实会导致在所需时间上收益递减。

还有许多其他命令行选项可用于调整编码器参数，以精细调整压缩算法。请参阅命令行帮助消息了解更多详情。

# 文档

[ASTC 格式概述](./Docs/FormatOverview.md) 页面提供了 ASTC 纹理格式的高级介绍，包括它如何编码数据，以及为什么它既灵活又高效。

[高效 ASTC 编码](./Docs/Encoding.md) 页面介绍了使用 `astcenc` 压缩数据时应遵循的一些指南。它涵盖：

* 如何高效编码少于 4 个通道的数据。
* 如何高效编码法线贴图、sRGB 数据和 HDR 数据。
* 与其他压缩格式的编码等效方式。

[ASTC 开发者指南][5] 文档（外部链接）为使用 `astcenc` 压缩器的开发者提供了更详细的指南。

[.astc 文件格式](./Docs/FileFormat.md) 页面提供了 `.astc` 文件格式的轻量级规范以及如何读写它。

[构建 ASTC 编码器](./Docs/Building.md) 页面提供了如何从本仓库源代码构建 `astcenc` 的说明。

[测试 ASTC 编码器](./Docs/Testing.md) 页面提供了如何测试本仓库源代码修改的说明。

[使用指南](./Docs/Usage-Guide.md) 提供了所有命令行参数、质量预设、高级调优选项和库 API 的详细文档，以及 Windows 一键构建脚本说明。

# 支持

如果您在使用 `astcenc` 编码器时遇到问题，或对 ASTC 纹理格式本身有疑问，请在 GitHub issue 跟踪器中提出。

如果您有任何关于 Arm GPU、Arm GPU 应用开发或一般移动图形开发或技术的问题，请在 [Arm 社区图形论坛][4] 上提交。

- - -

_版权所有 © 2013-2026，Arm Limited 及其贡献者。_

[1]: ./Docs/FormatOverview.md
[2]: https://www.khronos.org/registry/DataFormat/specs/1.4/dataformat.1.4.html#ASTC
[3]: https://github.com/ARM-software/astc-encoder/releases
[4]: https://community.arm.com/support-forums/f/graphics-gaming-and-vr-forum/
[5]: https://developer.arm.com/documentation/102162/latest/?lang=en
