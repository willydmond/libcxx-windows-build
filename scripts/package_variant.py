#!/usr/bin/env python3
import argparse, pathlib, zipfile, hashlib, json, shutil

def sha256(path: pathlib.Path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda: f.read(1024*1024), b""):
            h.update(b)
    return h.hexdigest()

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out-root", required=True)
    p.add_argument("--host-os", required=True)
    p.add_argument("--arch", required=True)
    p.add_argument("--config", required=True)
    p.add_argument("--llvm-tag", required=True)
    p.add_argument("--abi-namespace", required=True)
    args = p.parse_args()

    out = pathlib.Path(args.out_root)
    inst = out / "install" / f"{args.host_os}-{args.arch}-{args.config}"
    pkg_dir = out / "packages"
    pkg_dir.mkdir(parents=True, exist_ok=True)

    name = f"libcxx-prebuilt-{args.host_os}-{args.arch}-{args.config}-{args.llvm_tag}-{args.abi_namespace}.zip"
    zpath = pkg_dir / name

    with zipfile.ZipFile(zpath, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for pth in inst.rglob("*"):
            if pth.is_file():
                z.write(pth, pth.relative_to(inst).as_posix())

    (pkg_dir / f"{name}.sha256").write_text(f"{sha256(zpath)}  {name}\n", encoding="utf-8")
    manifest = {
        "llvm_tag": args.llvm_tag,
        "host_os": args.host_os,
        "arch": args.arch,
        "config": args.config,
        "abi_namespace": args.abi_namespace
    }
    (pkg_dir / f"{name}.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

if __name__ == "__main__":
    main()