#!/usr/bin/env python3
import argparse, subprocess, pathlib, shlex

def run(cmd, cwd=None):
    print("+", " ".join(shlex.quote(c) for c in cmd))
    subprocess.check_call(cmd, cwd=cwd)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--llvm-src", required=True)
    p.add_argument("--out-root", required=True)
    p.add_argument("--host-os", required=True, choices=["windows","linux"])
    p.add_argument("--arch", required=True, choices=["x64","arm64"])
    p.add_argument("--config", required=True, choices=["Debug","Release"])
    p.add_argument("--abi-namespace", required=True)
    p.add_argument("--enable-iterator-debugging", default="false")
    p.add_argument("--instrumented-with-asan", default="0")
    p.add_argument("--enable-tzdb", default="true")
    args = p.parse_args()

    out = pathlib.Path(args.out_root).resolve()
    build = out / "build" / f"{args.host_os}-{args.arch}-{args.config}"
    install = out / "install" / f"{args.host_os}-{args.arch}-{args.config}"
    build.mkdir(parents=True, exist_ok=True)
    install.mkdir(parents=True, exist_ok=True)

    cxx_flags = [f"-D_LIBCPP_INSTRUMENTED_WITH_ASAN={args.instrumented_with_asan}"]
    if args.enable_iterator_debugging.lower() == "true":
        cxx_flags.append("-D_LIBCPP_ENABLE_DEBUG_MODE")

    tzdb_requested = args.enable_tzdb.lower() == "true"
    tzdb_effective = tzdb_requested and args.host_os != "windows"
    if tzdb_requested and args.host_os == "windows":
        print("[warn] Windows tzdb support is disabled per upstream maintainer guidance.")

    tzdb_enabled = "ON" if tzdb_effective else "OFF"

    runtimes = ["libcxx"]
    if args.host_os != "windows":
        runtimes.append("libcxxabi")
        runtimes.append("libunwind")

    cmake_args = [
        "cmake", "-S", f"{args.llvm_src}/runtimes", "-B", str(build), "-G", "Ninja",
        f"-DCMAKE_BUILD_TYPE={args.config}",
        f"-DCMAKE_INSTALL_PREFIX={install}",
        f"-DLLVM_ENABLE_RUNTIMES={';'.join(runtimes)}",
        "-DLIBCXX_ENABLE_SHARED=OFF", "-DLIBCXX_ENABLE_STATIC=ON",
        f"-DLIBCXX_ENABLE_TIME_ZONE_DATABASE={tzdb_enabled}",
        "-DLIBCXX_INCLUDE_TESTS=OFF",
        f"-DLIBCXX_ABI_NAMESPACE={args.abi_namespace}",
        f"-DCMAKE_CXX_FLAGS={' '.join(cxx_flags)}",
    ]

    if "libcxxabi" in runtimes:
        cmake_args += [
            "-DLIBCXXABI_ENABLE_SHARED=OFF",
            "-DLIBCXXABI_ENABLE_STATIC=ON",
            "-DLIBCXXABI_INCLUDE_TESTS=OFF",
        ]

    if "libunwind" in runtimes:
        cmake_args += [
            "-DLIBUNWIND_ENABLE_SHARED=OFF",
            "-DLIBUNWIND_ENABLE_STATIC=ON",
            "-DLIBUNWIND_INCLUDE_TESTS=OFF",
        ]

    if args.host_os == "windows":
        cmake_args += [
            "-DCMAKE_C_COMPILER=clang-cl",
            "-DCMAKE_CXX_COMPILER=clang-cl",
            "-DCMAKE_EXE_LINKER_FLAGS=/INCREMENTAL:NO",
            "-DCMAKE_SHARED_LINKER_FLAGS=/INCREMENTAL:NO",
            "-DCMAKE_MODULE_LINKER_FLAGS=/INCREMENTAL:NO",
        ]
        if args.arch == "arm64":
            cmake_args += ["-DCMAKE_C_COMPILER_TARGET=aarch64-pc-windows-msvc",
                           "-DCMAKE_CXX_COMPILER_TARGET=aarch64-pc-windows-msvc"]
        else:
            cmake_args += ["-DCMAKE_C_COMPILER_TARGET=x86_64-pc-windows-msvc",
                           "-DCMAKE_CXX_COMPILER_TARGET=x86_64-pc-windows-msvc"]
    else:
        cmake_args += ["-DCMAKE_C_COMPILER=clang-21", "-DCMAKE_CXX_COMPILER=clang++-21"]
        if args.arch == "arm64":
            cmake_args += [
                "-DCMAKE_SYSTEM_NAME=Linux",
                "-DCMAKE_SYSTEM_PROCESSOR=aarch64",
                "-DCMAKE_C_COMPILER_TARGET=aarch64-linux-gnu",
                "-DCMAKE_CXX_COMPILER_TARGET=aarch64-linux-gnu",
                "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY",
            ]

    run(cmake_args)
    run(["cmake", "--build", str(build), "--target", "install", "-j", "4"])

if __name__ == "__main__":
    main()