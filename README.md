# libcxx-windows-build

预构建并发布跨平台 `libc++` 包（Windows/Linux，x64/arm64），用于在你自己的 CMake 项目中一键导入。

## 你现在能获得什么

- 自动构建矩阵：
  - Windows: `x64`, `arm64`
  - Linux: `x64`, `arm64`
  - Config: `Debug`, `Release`
- 自动打包产物（zip + sha256 + json）
- 自动生成 GitHub Release（tag: `libcxx-<llvm_tag>`）
- 已支持 `tzdb`（`std::chrono::zoned_time`, `locate_zone`, `get_tzdb` 等）

## 工作流入口

触发 `.github/workflows/build.yml`（`workflow_dispatch`）时可选参数：

- `llvm_tag`：LLVM 版本标签（例如 `llvmorg-22.1.0`）
- `enable_iterator_debugging`：是否启用 iterator debug mode
- `instrumented_with_asan`：是否开启 ASAN 宏
- `enable_tzdb`：是否启用 `LIBCXX_ENABLE_TIME_ZONE_DATABASE`（默认 `true`）

## 产物命名

单变体包：

- `libcxx-prebuilt-<host_os>-<arch>-<config>-<llvm_tag>-<abi_namespace>.zip`

聚合包（Release 附件中可见）：

- 所有 zip
- `SHA256SUMS.txt`
- `manifest.json`

## 在你的项目中一键导入（FetchContent）

在你的 `CMakeLists.txt` 里：

```cmake
cmake_minimum_required(VERSION 3.24)
project(demo LANGUAGES CXX)

include(FetchContent)

FetchContent_Declare(
  libcxx_prebuilt_repo
  GIT_REPOSITORY https://github.com/willydmond/libcxx-windows-build.git
  GIT_TAG main
)
FetchContent_MakeAvailable(libcxx_prebuilt_repo)

include(${libcxx_prebuilt_repo_SOURCE_DIR}/cmake/LibcxxPrebuilt.cmake)

libcxx_prebuilt_import(
  TARGET libcxx_prebuilt::runtime
  LLVM_TAG llvmorg-22.1.0
  CONFIG Release
  ABI_NAMESPACE __Cr
)

add_executable(app main.cpp)
libcxx_prebuilt_enable_for_target(app libcxx_prebuilt::runtime)
```

> `libcxx_prebuilt_import` 会按当前主机自动判断 `HOST_OS`/`ARCH`，并从对应 release 下载 zip、解压、配置 include/lib。

## 关键函数

`cmake/LibcxxPrebuilt.cmake` 提供：

- `libcxx_prebuilt_import(...)`
  - 关键参数：`LLVM_TAG`（必填）
  - 常用可选：`TARGET`, `OWNER`, `REPO`, `HOST_OS`, `ARCH`, `CONFIG`, `ABI_NAMESPACE`, `RELEASE_TAG`
- `libcxx_prebuilt_enable_for_target(<your_target> <imported_target>)`
  - 自动链接导入目标
  - Clang/GNU 下自动加 `-nostdinc++`、`-nostdlib++`

## 关于 tzdb（chrono 时区数据库）

构建脚本会传入：

- `-DLIBCXX_ENABLE_TIME_ZONE_DATABASE=ON/OFF`

默认开启（`enable_tzdb=true`）。开启后可用 C++20 `<chrono>` 时区能力（例如 `std::chrono::zoned_time`）。

## 平台备注（和 libc++ vendor 文档一致）

- Windows `clang-cl` + `*-windows-msvc` 目标仅构建 `libcxx`（不构建 `libcxxabi/libunwind`）
- Linux 构建使用 `clang-21`
- Linux arm64 采用交叉目标配置（`aarch64-linux-gnu`）

## 最小使用示例（main.cpp）

```cpp
#include <chrono>
#include <iostream>

int main() {
  using namespace std::chrono;
  auto z = locate_zone("UTC");
  zoned_time zt{z, system_clock::now()};
  std::cout << zt << '\n';
}
```
