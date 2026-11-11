"""只读核对参考模板，不运行 Unity，也不修改模板。"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path

LOCK = Path(__file__).resolve().parents[1] / "docs" / "source-lock.json"

def verify(root: Path, lock: dict) -> list[str]:
    errors: list[str] = []
    expected = {item["path"]: item for item in lock["files"]}
    actual = {p.relative_to(root).as_posix(): p for p in root.rglob("*") if p.is_file()}
    for name, item in expected.items():
        path = actual.get(name)
        if path is None:
            errors.append(f"缺失: {name}")
        elif path.stat().st_size != item["bytes"] or hashlib.sha256(path.read_bytes()).hexdigest() != item["sha256"]:
            errors.append(f"内容不同: {name}")
    errors.extend(f"多余: {name}" for name in sorted(actual.keys() - expected.keys()))
    return errors

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--lock", type=Path, default=LOCK)
    args = parser.parse_args()
    if not args.source.is_dir():
        parser.error("source 必须是存在的 StackCraft 模板目录")
    lock = json.loads(args.lock.read_text(encoding="utf-8"))
    errors = verify(args.source, lock)
    if errors:
        print("\n".join(errors))
        return 1
    print(f"PASS: {len(lock['files'])} 个文件与 {lock['commit']} 完全匹配")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
