#!/usr/bin/env python3
"""两棵目录树逐文件 md5 对比（移植产物校验用）。

用法: tree-md5-diff.py <参考目录> <新目录>
输出缺失/多余/内容不同的文件清单（含 md5）；完全一致时退出码 0，否则 1。
"""
import hashlib
import sys
from pathlib import Path


def scan(root: Path) -> dict:
    out = {}
    for p in sorted(root.rglob("*")):
        if p.is_file() and not p.is_symlink():
            out[str(p.relative_to(root))] = hashlib.md5(p.read_bytes()).hexdigest()
    return out


def main(ref: str, new: str) -> int:
    a, b = scan(Path(ref)), scan(Path(new))
    missing = sorted(set(a) - set(b))
    extra = sorted(set(b) - set(a))
    changed = sorted(k for k in set(a) & set(b) if a[k] != b[k])
    for k in missing:
        print("MISSING", k, " ref-md5", a[k])
    for k in extra:
        print("EXTRA  ", k, " new-md5", b[k])
    for k in changed:
        print("CHANGED", k, " ref=" + a[k], " new=" + b[k])
    print("--- ref=%d new=%d | missing=%d extra=%d changed=%d"
          % (len(a), len(b), len(missing), len(extra), len(changed)))
    return 1 if (missing or extra or changed) else 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
