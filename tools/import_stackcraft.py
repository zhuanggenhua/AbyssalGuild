#!/usr/bin/env python3
"""Deterministic, read-only Unity text-serialization importer. Requires PyYAML 6.x."""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import yaml

SOURCE_COMMIT = 'a11a89b04cea8370476f2559b639bb9b4cbc08d8'
GROUPS = ('cards', 'packs', 'recipes', 'quests', 'encounters', 'settings')
HEADER = re.compile(r'^--- !u!(\d+) &(-?\d+)(?: stripped)?\s*$', re.M)

class UnityLoader(yaml.SafeLoader):
    pass

# YAML 1.1's octal/boolean/timestamp inference corrupts Unity packed hex arrays,
# identifiers and literal names such as "On". Keep only decimal integer inference.
UnityLoader.yaml_implicit_resolvers = copy.deepcopy(yaml.SafeLoader.yaml_implicit_resolvers)
for key, entries in UnityLoader.yaml_implicit_resolvers.items():
    UnityLoader.yaml_implicit_resolvers[key] = [(tag, rx) for tag, rx in entries
        if tag not in ('tag:yaml.org,2002:int', 'tag:yaml.org,2002:bool', 'tag:yaml.org,2002:timestamp')]
UnityLoader.add_implicit_resolver('tag:yaml.org,2002:int', re.compile(r'^(?:0|[-+]?[1-9][0-9]*)$'), list('-+0123456789'))

def unique_mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in result:
            raise ValueError(f'Duplicate YAML key: {key}')
        result[key] = loader.construct_object(value_node, deep=deep)
    return result
UnityLoader.add_constructor('tag:yaml.org,2002:map', unique_mapping)

def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + '\n').encode()

def normalize(value):
    if isinstance(value, dict):
        # Unity object IDs exceed the exact integer range of Godot's JSON parser.
        return {k: str(v) if k == 'fileID' else normalize(v) for k, v in value.items()}
    if isinstance(value, list):
        return [normalize(v) for v in value]
    return value

def parse_unity(path):
    raw = Path(path).read_text(encoding='utf-8-sig')
    matches = list(HEADER.finditer(raw))
    if not matches:
        raise ValueError(f'Not Unity text serialization: {path}')
    documents = []
    for i, match in enumerate(matches):
        part = raw[match.end():matches[i + 1].start() if i + 1 < len(matches) else len(raw)]
        value = yaml.load(part, Loader=UnityLoader)
        if not isinstance(value, dict) or len(value) != 1:
            raise ValueError(f'Unexpected Unity document in {path}')
        object_type, fields = next(iter(value.items()))
        documents.append({'class_id': int(match[1]), 'file_id': match[2],
                          'object_type': object_type, 'fields': normalize(fields)})
    return documents

def references(value, path=''):
    if isinstance(value, dict):
        if value.get('guid') and str(value.get('fileID', '0')) != '0':
            yield path, value['guid']
        for key, child in value.items():
            yield from references(child, path + '/' + str(key))
    elif isinstance(value, list):
        for i, child in enumerate(value):
            yield from references(child, path + '/' + str(i))

def read_enums(root):
    result = {}
    for path in sorted((root / 'Scripts').rglob('*.cs')):
        source = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(encoding='utf-8-sig'), flags=re.S)
        for name, body in re.findall(r'\benum\s+(\w+)\s*\{([^}]+)\}', source):
            members, number = {}, 0
            for member in body.split(','):
                member = member.strip()
                if not member:
                    continue
                match = re.fullmatch(r'(\w+)(?:\s*=\s*(-?\d+))?', member)
                if not match:
                    raise ValueError(f'Unsupported enum expression {name}: {member}')
                if match[2] is not None:
                    number = int(match[2])
                members[match[1]] = number
                number += 1
            if name in result and result[name] != members:
                raise ValueError(f'Conflicting enum {name}')
            result[name] = members
    return result

def build(root, source_commit=SOURCE_COMMIT, allow_missing_visual_assets=False):
    root = Path(root).resolve()
    if not (root / 'Resources/Cards').is_dir():
        raise ValueError('Source must be the original Assets/StackCraft directory')
    index, inputs, missing_visual_assets = {}, {}, []
    def track(path):
        relative = path.relative_to(root).as_posix()
        inputs[relative] = sha256(path)
        return relative
    for meta in sorted(root.rglob('*.meta')):
        found = re.search(r'^guid: ([0-9a-f]{32})\s*$', meta.read_text(), re.M)
        if not found:
            raise ValueError(f'Missing GUID in {meta}')
        guid = found[1]
        if guid in index:
            raise ValueError(f'Duplicate GUID {guid}')
        source = Path(str(meta)[:-5])
        if not source.exists():
            # Explicit logic-only import: retain GUIDs but never invent source bytes.
            # Scripts, serialized definitions, prefabs and scenes remain mandatory.
            if not allow_missing_visual_assets or source.suffix.lower() not in ('.png', '.jpg', '.jpeg', '.wav', '.ogg', '.mp3', '.fbx', '.pdf'):
                raise ValueError(f'Orphan metadata {meta}')
            missing_visual_assets.append(source.relative_to(root).as_posix())
        relative = source.relative_to(root).as_posix()
        index[guid] = {'source_path': relative, 'kind': source.suffix.lstrip('.') or 'directory'}
        track(meta)
    for script in sorted((root / 'Scripts').rglob('*.cs')):
        track(script)
    def guid_for(path):
        meta = path.with_name(path.name + '.meta')
        return re.search(r'^guid: ([0-9a-f]{32})\s*$', meta.read_text(), re.M)[1]
    def enriched_documents(path):
        docs = parse_unity(path)
        for doc in docs:
            script_guid = doc['fields'].get('m_Script', {}).get('guid')
            if script_guid in index:
                doc['script_class'] = Path(index[script_guid]['source_path']).stem
        return docs
    result = {'schema_version': 1, 'provenance': {
        'source_project': 'CardLoop / CryingSnow.StackCraft', 'source_commit': source_commit,
        'source_root': 'Assets/StackCraft', 'license_status': 'not_cleared_for_redistribution',
        'scope': 'Static serialized data, not a claim of gameplay or visual parity'},
        'enums': read_enums(root), 'guid_index': index}
    excluded = []
    for group in GROUPS:
        result[group] = []
        folder = root / ('Settings' if group == 'settings' else 'Resources/' + group.capitalize())
        for path in sorted(folder.rglob('*.asset')):
            relative = track(path)
            if 'URP' in path.parts:
                excluded.append({'source_path': relative, 'reason': 'Unity-specific rendering pipeline configuration'})
                continue
            docs = enriched_documents(path)
            if len(docs) != 1 or docs[0]['object_type'] != 'MonoBehaviour':
                raise ValueError(f'Unexpected gameplay asset document layout: {path}')
            doc = docs[0]
            fields = doc['fields']
            record = {'guid': guid_for(path), 'source_path': relative, 'source_sha256': inputs[relative],
                      'script_class': doc.get('script_class'), 'name': fields.get('m_Name'),
                      'file_id': doc['file_id'], 'fields': {k: v for k, v in fields.items() if not k.startswith('m_')},
                      'unity_fields': {k: v for k, v in fields.items() if k.startswith('m_')}}
            if record['script_class'] is None:
                raise ValueError(f'Unresolved gameplay definition script in {path}')
            if record['script_class'] == 'StackingRulesMatrix':
                packed = record['fields']['rules']
                data = bytes.fromhex(packed)
                size = len(result['enums']['CardCategory'])
                if len(data) != size * size * 4:
                    raise ValueError('Stacking rule matrix size differs from CardCategory squared')
                record['decoded'] = {'rules': list(struct.unpack('<' + 'i' * (len(data) // 4), data)), 'size': size,
                                     'index_order': 'bottom_category * size + top_category'}
            result[group].append(record)
            index[record['guid']]['group'] = group
    def object_file(path):
        relative = track(path)
        return {'guid': guid_for(path), 'name': path.stem, 'source_path': relative,
                'source_sha256': inputs[relative], 'documents': enriched_documents(path)}
    result['scenes'] = [object_file(path) for path in sorted((root / 'Scenes').glob('*.unity'))]
    result['referenced_prefabs'] = []
    pending = {guid for _, guid in references(result['scenes'])}
    seen = set()
    while pending:
        guid = min(pending)
        pending.remove(guid)
        if guid in seen:
            continue
        seen.add(guid)
        entry = index.get(guid)
        if entry and entry['kind'] == 'prefab':
            prefab = object_file(root / entry['source_path'])
            result['referenced_prefabs'].append(prefab)
            pending.update(g for _, g in references(prefab) if g not in seen)
    result['referenced_prefabs'].sort(key=lambda r: r['source_path'])
    result['counts'] = {group: len(result[group]) for group in (*GROUPS, 'scenes', 'referenced_prefabs')}
    all_refs = list(references({k: result[k] for k in (*GROUPS, 'scenes', 'referenced_prefabs')}))
    unresolved = sorted([{'field_path': path, 'guid': guid} for path, guid in all_refs if guid not in index], key=lambda r: (r['field_path'], r['guid']))
    # Gameplay references must resolve. Scene prefabs can use package-provided UI scripts.
    gameplay_missing = [r for r in unresolved if r['field_path'].split('/')[1] in GROUPS]
    if gameplay_missing:
        raise ValueError(f'Unresolved gameplay GUIDs: {gameplay_missing}')
    if allow_missing_visual_assets:
        result['provenance']['missing_visual_assets'] = sorted(missing_visual_assets)
        result['provenance']['import_mode'] = 'logic_only_sparse_assets'
    manifest = {'schema_version': 1, 'source_commit': source_commit, 'counts': result['counts'],
                'source_files_sha256': inputs, 'excluded_assets': excluded,
                'references': {'total': len(all_refs), 'resolved': len(all_refs) - len(unresolved),
                               'unresolved_external': unresolved},
                'stackcraft_json_sha256': hashlib.sha256(json_bytes(result)).hexdigest()}
    if allow_missing_visual_assets:
        manifest['missing_visual_assets'] = sorted(missing_visual_assets)
        manifest['import_mode'] = 'logic_only_sparse_assets'
    return result, manifest

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--output', default=Path('data'), type=Path)
    parser.add_argument('--source-commit', default=SOURCE_COMMIT, help='Provenance label, not independently proven by the importer')
    parser.add_argument('--allow-missing-visual-assets', action='store_true', help='Logic-only import: report absent binary media without fabricating files; never permits missing gameplay inputs')
    args = parser.parse_args()
    result, manifest = build(args.source, args.source_commit, args.allow_missing_visual_assets)
    args.output.mkdir(parents=True, exist_ok=True)
    for name, data in [('stackcraft.json', result), ('manifest.json', manifest)]:
        (args.output / name).write_bytes(json_bytes(data))
    print(json.dumps({'counts': result['counts'], 'references': manifest['references']['total'],
                      'unresolved_external': len(manifest['references']['unresolved_external'])}, sort_keys=True))

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, yaml.YAMLError) as exc:
        sys.exit(str(exc))
