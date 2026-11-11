#!/usr/bin/env python3
"""Verify imported hashes, counts, GUID integrity; optionally reimport the source."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
from import_stackcraft import GROUPS, build, json_bytes, references


def verify(data_dir, source=None):
    data_dir = Path(data_dir)
    payload = (data_dir / 'stackcraft.json').read_bytes()
    data = json.loads(payload)
    manifest = json.loads((data_dir / 'manifest.json').read_bytes())
    errors = []
    def check(condition, message):
        if not condition:
            errors.append(message)
    check(data.get('schema_version') == 1 and manifest.get('schema_version') == 1, 'Unsupported schema version')
    check(hashlib.sha256(payload).hexdigest() == manifest['stackcraft_json_sha256'], 'Data SHA-256 mismatch')
    check(payload == json_bytes(data), 'Data is not in canonical JSON format')
    check(data['provenance']['source_commit'] == manifest['source_commit'], 'Provenance mismatch')
    seen, ids = set(), {}
    for group in (*GROUPS, 'scenes', 'referenced_prefabs'):
        records = data[group]
        check(len(records) == data['counts'].get(group) == manifest['counts'].get(group), f'Count mismatch: {group}')
        for record in records:
            guid, path = record['guid'], record['source_path']
            check(guid not in seen, f'Duplicate record GUID: {guid}')
            seen.add(guid)
            check(guid in data['guid_index'], f'Missing GUID index entry: {guid}')
            if guid in data['guid_index']:
                check(data['guid_index'][guid]['source_path'] == path, f'GUID path mismatch: {path}')
            check(record['source_sha256'] == manifest['source_files_sha256'].get(path), f'Source hash mismatch: {path}')
            game_id = record.get('fields', {}).get('id')
            if game_id:
                check(game_id not in ids, f'Duplicate gameplay ID: {game_id} in {path} and {ids.get(game_id)}')
                ids[game_id] = path
    refs = list(references({key: data[key] for key in (*GROUPS, 'scenes', 'referenced_prefabs')}))
    missing = sorted([{'field_path': path, 'guid': guid} for path, guid in refs if guid not in data['guid_index']], key=lambda r: (r['field_path'], r['guid']))
    expected = manifest['references']
    check(expected['total'] == len(refs), 'Reference total mismatch')
    check(expected['resolved'] == len(refs) - len(missing), 'Resolved reference count mismatch')
    check(expected['unresolved_external'] == missing, 'Unresolved reference report mismatch')
    check(not any(r['field_path'].split('/')[1] in GROUPS for r in missing), 'Unresolved gameplay GUID')
    for record in data['settings']:
        if record['script_class'] == 'StackingRulesMatrix':
            decoded = record['decoded']
            check(len(decoded['rules']) == decoded['size'] ** 2, 'Matrix size mismatch')
            check(set(decoded['rules']) <= set(data['enums']['StackingRule'].values()), 'Unknown stacking rule')
    if source is not None:
        source = Path(source)
        for path, digest in manifest['source_files_sha256'].items():
            candidate = source / path
            check(candidate.is_file(), f'Missing source: {path}')
            if candidate.is_file():
                check(hashlib.sha256(candidate.read_bytes()).hexdigest() == digest, f'Changed source: {path}')
        regenerated, regenerated_manifest = build(source, manifest['source_commit'])
        check(json_bytes(regenerated) == payload, 'Reimport differs from data')
        check(json_bytes(regenerated_manifest) == json_bytes(manifest), 'Reimport differs from manifest')
    if errors:
        raise ValueError('\n'.join(errors))
    return {'status': 'verified', 'counts': data['counts'], 'unresolved_external': len(missing),
            'source_reimported': source is not None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', type=Path, default=Path('data'))
    parser.add_argument('--source', type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.data, args.source), sort_keys=True))

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError) as exc:
        sys.exit(str(exc))
