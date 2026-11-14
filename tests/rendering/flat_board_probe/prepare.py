#!/usr/bin/env python3
"""Copy only first-party runtime scripts into this isolated synthetic GPU probe.

No Unity source, private data, media, imported cache, or generated artifacts.
The copied scripts are ignored and are not a frozen substitute for production.
"""
import hashlib
import json
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

def prepare():
    source = ROOT / 'scripts'
    destination = HERE / 'scripts'
    manifest = {}
    for path in sorted(source.rglob('*')):
        if path.is_symlink():
            raise ValueError(f'Symlink not accepted: {path}')
        if not path.is_file() or path.suffix not in ('.gd', '.gdshader'):
            continue
        relative = path.relative_to(source)
        output = destination / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, output)
        manifest[str(relative)] = hashlib.sha256(output.read_bytes()).hexdigest()
    if 'ui/source_lit_material.gd' not in manifest:
        raise ValueError('Production factory missing; probe not prepared')
    print(json.dumps({'copied_owned_scripts':len(manifest),'sha256':manifest},sort_keys=True))

if __name__ == '__main__':
    prepare()
