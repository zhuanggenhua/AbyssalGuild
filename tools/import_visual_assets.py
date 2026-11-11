#!/usr/bin/env python3
"""Private licensed visual adapter. Never commit its output or the original source."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import shutil
from import_stackcraft import parse_unity, json_bytes, sha256
from visual_scene_metadata import apply_overrides, camera_records, light_records

SUPPORTED = {'.png', '.wav', '.fbx'}

def inside(root, relative):
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError(f'Path escapes root: {relative}')
    return path

def build(source, catalog, output):
    source, output = Path(source).resolve(), Path(output).resolve()
    if output == source or output.is_relative_to(source):
        raise ValueError('Output must not be inside licensed source')
    output.mkdir(parents=True, exist_ok=True)
    result = {'schema_version': 1, 'license_notice': 'PRIVATE LICENSED INPUT. Do not redistribute originals or this generated manifest without permission.',
              'assets': {}, 'materials': {}, 'prefabs': {}, 'scenes': {}, 'missing': [], 'inputs': {}}
    index = catalog['guid_index']
    def read(guid):
        entry = index.get(guid, {})
        relative = entry.get('source_path', '')
        if not relative:
            return []
        path = inside(source, relative)
        if not path.is_file():
            return []
        result['inputs'][relative] = sha256(path)
        return parse_unity(path)
    for guid, entry in sorted(index.items()):
        relative = entry['source_path']
        path = inside(source, relative)
        if not path.exists():
            result['missing'].append({'guid': guid, 'source_path': relative})
            continue
        if path.suffix.lower() in SUPPORTED:
            target = inside(output, relative)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
            digest = sha256(path)
            result['assets'][guid] = {'source_path': relative, 'path': relative, 'sha256': digest, 'kind': path.suffix.lower()[1:], 'conversion': 'byte-identical copy'}
            result['inputs'][relative] = digest
        elif path.suffix.lower() == '.mat':
            for doc in read(guid):
                if doc['object_type'] != 'Material':
                    continue
                fields = doc['fields']; saved = fields.get('m_SavedProperties', {})
                result['materials'][guid] = {'source_path': relative, 'name': fields.get('m_Name'),
                    'colors': {k: v for item in saved.get('m_Colors', []) for k, v in item.items()},
                    'textures': {k: v for item in saved.get('m_TexEnvs', []) for k, v in item.items()},
                    'floats': {k: v for item in saved.get('m_Floats', []) for k, v in item.items()}}
    def prefab(guid):
        if guid in result['prefabs']:
            return guid
        docs = read(guid)
        renderers = [d['fields'] for d in docs if d['object_type'] in ('MeshRenderer', 'SkinnedMeshRenderer')]
        colliders = [d['fields'] for d in docs if d['object_type'] == 'BoxCollider']
        # Root card renderer is selected by collider owner, never a text child.
        collider = colliders[0] if colliders else {}
        renderer = next((f for f in renderers if f.get('m_GameObject') == collider.get('m_GameObject')), renderers[0] if renderers else {})
        result['prefabs'][guid] = {'source_path': index.get(guid, {}).get('source_path', ''),
            'size': collider.get('m_Size', {}), 'materials': renderer.get('m_Materials', []),
            'mesh': renderer.get('m_Mesh', {}),
            'renderers': [{'owner': f.get('m_GameObject'), 'materials': f.get('m_Materials', [])} for f in renderers]}
        return guid
    for scene in catalog.get('scenes', []):
        docs = scene['documents']
        config = {'categories': {}, 'boards': [], 'cameras': camera_records(docs), 'lights': light_records(docs)}
        for doc in docs:
            f = doc['fields']
            if 'cardPrefabs' in f:
                config['categories'] = {str(e['category']): prefab(e['prefab']['guid']) for e in f['cardPrefabs']}
                for field in ('packPrefab', 'aggressiveMobPrefab'):
                    if f.get(field, {}).get('guid'):
                        config[field] = prefab(f[field]['guid'])
            guid = f.get('m_SourcePrefab', {}).get('guid', '')
            if index.get(guid, {}).get('source_path', '').startswith('Prefabs/Boards/'):
                config['boards'].append(prefab(guid))
            if guid and index.get(guid, {}).get('source_path', '').endswith('.prefab'):
                modification = f.get('m_Modification', {})
                modifications = modification.get('m_Modifications', [])
                effective = apply_overrides(read(guid), modifications)
                external_parent = str(modification.get('m_TransformParent', {}).get('fileID', '0')) != '0'
                for camera in camera_records(effective, external_parent):
                    camera['prefab_guid'] = guid
                    camera['instance_modifications'] = modifications
                    config['cameras'].append(camera)
                if not external_parent:
                    config['lights'].extend(light_records(effective))
        result['scenes'][scene['name']] = config
    (output / 'manifest.json').write_bytes(json_bytes(result))
    return result

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', required=True, type=Path)
    p.add_argument('--catalog', type=Path, default=Path('data/stackcraft.json'))
    p.add_argument('--output', type=Path, default=Path('assets/imported'))
    p.add_argument('--acknowledge-license', action='store_true', required=True)
    a = p.parse_args()
    # Public-project runs must use the explicitly ignored destination.
    if a.output.resolve() != Path('assets/imported').resolve():
        p.error('Use assets/imported in the project root; output must remain ignored')
    result = build(a.source, json.loads(a.catalog.read_text()), a.output)
    print(f"Private import: {len(result['assets'])} assets; {len(result['missing'])} missing. No redistribution rights granted.")
if __name__ == '__main__':
    main()
