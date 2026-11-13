#!/usr/bin/env python3
"""Private licensed visual adapter. Never commit its output or the original source."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import shutil
import yaml
from import_stackcraft import parse_unity, json_bytes, sha256, UnityLoader
from visual_scene_metadata import apply_overrides, camera_records, light_records, transform_chain
from card_visual_metadata import annotations, single_line_text_fields
from combat_visual_metadata import combat_metadata, sprite_metadata
from puff_visual_metadata import scene_puff_metadata
from world_visual_metadata import world_metadata
from progress_visual_metadata import progress_metadata, world_canvas_chain, board_effective_pose
from trade_visual_metadata import trade_metadata
from outline_visual_metadata import outline_metadata

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
            meta = path.with_name(path.name + '.meta')
            if path.suffix.lower() == '.png' and meta.is_file():
                document = yaml.load(meta.read_text(encoding='utf-8-sig'), Loader=UnityLoader)
                importer = document.get('TextureImporter', {})
                result['assets'][guid]['texture_importer'] = {'filter_mode': importer.get('textureSettings', {}).get('filterMode'),
                    'wrap_u': importer.get('textureSettings', {}).get('wrapU'), 'wrap_v': importer.get('textureSettings', {}).get('wrapV'),
                    'mipmaps': importer.get('mipmaps', {}).get('enableMipMap'), 'srgb': importer.get('mipmaps', {}).get('sRGBTexture'),
                    'alpha_is_transparency': importer.get('alphaIsTransparency'),
                    'alpha_usage': importer.get('alphaUsage')}
                result['inputs'][relative + '.meta'] = sha256(meta)
                sprite = sprite_metadata(importer, path.read_bytes())
                if sprite:
                    result['assets'][guid]['sprite'] = sprite
                    result['inputs'][relative + '.meta'] = sha256(meta)
        elif path.suffix.lower() == '.mat':
            for doc in read(guid):
                if doc['object_type'] != 'Material':
                    continue
                fields = doc['fields']; saved = fields.get('m_SavedProperties', {})
                result['materials'][guid] = {'source_path': relative, 'name': fields.get('m_Name'),
                    'shader_source_path': index.get(fields.get('m_Shader', {}).get('guid', ''), {}).get('source_path', ''),
                    'shader_reference': fields.get('m_Shader', {}),
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
        owner = renderer.get('m_GameObject')
        mesh_filter = next((d['fields'] for d in docs if d['object_type'] == 'MeshFilter' and d['fields'].get('m_GameObject') == owner), {})
        mesh = renderer.get('m_Mesh') or mesh_filter.get('m_Mesh', {})
        pose = transform_chain(docs, owner)
        # Only a directly parented Title with explicit text color is supported.
        title = {}
        root_transform = next((d for d in docs if d['object_type'] == 'Transform' and d['fields'].get('m_GameObject') == owner), {})
        for doc in docs:
            if doc['object_type'] != 'GameObject' or doc['fields'].get('m_Name') != 'Title':
                continue
            title_owner = {'fileID': doc['file_id']}
            rect = next((d['fields'] for d in docs if d['object_type'] == 'RectTransform' and d['fields'].get('m_GameObject') == title_owner), {})
            text = next((d['fields'] for d in docs if d['object_type'] == 'MonoBehaviour' and d['fields'].get('m_GameObject') == title_owner and 'm_fontColor' in d['fields']), {})
            keys = ('m_LocalPosition', 'm_LocalRotation', 'm_LocalScale')
            if pose and text and all(k in rect for k in keys) and str(rect.get('m_Father', {}).get('fileID')) == str(root_transform.get('file_id')):
                title = {**single_line_text_fields(text), 'transform_chain': pose + [{k: rect[k] for k in keys}], 'color': text['m_fontColor'], 'rect_size': rect.get('m_SizeDelta', {}), 'rect_pivot': rect.get('m_Pivot', {})}
        overlays = annotations(docs, owner)
        title = overlays['labels'].get('title', title)
        result['prefabs'][guid] = {'source_path': index.get(guid, {}).get('source_path', ''),
            'size': collider.get('m_Size', {}), 'materials': renderer.get('m_Materials', []),
            'mesh': mesh, 'transform_chain': pose, 'title': title,
            'labels': overlays['labels'], 'equipment_panel': overlays['equipment_panel'],
            'renderers': [{'owner': f.get('m_GameObject'), 'materials': f.get('m_Materials', [])} for f in renderers]}
        return guid
    for scene in catalog.get('scenes', []):
        docs = scene['documents']
        config = {'categories': {}, 'boards': [], 'cameras': camera_records(docs), 'lights': light_records(docs)}
        config.update(world_metadata(docs))
        for doc in docs:
            f = doc['fields']
            if 'progressUIPrefab' in f:
                config['progress'] = progress_metadata(f, read)
            if any(key in f for key in ('arrowProjectile', 'magicProjectile', 'hitUIPrefab')):
                config['combat'] = combat_metadata(f, read)
            if 'buyerPrefab' in f and 'vendorPrefab' in f:
                config['trading'] = trade_metadata(f, read, index, source)
                for zone in config['trading'].values():
                    graph_path = zone.get('outline', {}).get('shader_source_path', '')
                    if graph_path:
                        result['inputs'][graph_path] = sha256(inside(source, graph_path))
            if 'cardPrefabs' in f:
                config['puff'] = scene_puff_metadata(f, read)
                config['card_outline'] = outline_metadata(f, read, index, source)
                if config['card_outline']:
                    graph_path = config['card_outline']['shader_source_path']
                    result['inputs'][graph_path] = sha256(inside(source, graph_path))
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
                    canvas = world_canvas_chain(effective)
                    if canvas: config['world_canvas_chain'] = canvas
                    if guid in config['boards']:
                        config.setdefault('board_poses', {})[guid] = board_effective_pose(effective)
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
