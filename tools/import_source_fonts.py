#!/usr/bin/env python3
"""Private TMP supplement importer; never publish its output or source bundle.

The StackCraft catalog deliberately indexes its subtree only. External TMP font
assets must be a separately hash-locked input, not guessed from installed fonts.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
from import_stackcraft import parse_unity, json_bytes, sha256


def inside(root, relative):
    path = (root / relative).resolve()
    if not relative or not path.is_relative_to(root.resolve()) or Path(relative).is_absolute():
        raise ValueError('Unsafe source font path')
    return path


def blob_sha(path):
    data = path.read_bytes()
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()


def meta_guid(path):
    found = re.search(r'^guid: ([0-9a-f]{32})\s*$', path.read_text(), re.M)
    if not found:
        raise ValueError('Missing font metadata GUID')
    return found[1]


def build(source, lock, output, expected_source_commit=None):
    source, output = Path(source).resolve(), Path(output).resolve()
    if output == source or output.is_relative_to(source):
        raise ValueError('Output must not modify source bundle')
    if not re.fullmatch('[0-9a-f]{40}', lock.get('source_commit', '')):
        raise ValueError('Full source commit required')
    if expected_source_commit is not None and lock['source_commit'] != expected_source_commit:
        raise ValueError('Font supplement commit differs from StackCraft catalog')
    files = lock.get('files', {})
    inputs, missing = {}, []
    for relative, expected in sorted(files.items()):
        path = inside(source, relative)
        if not path.is_file():
            missing.append(relative)
            continue
        if blob_sha(path) != expected['git_blob_sha1']:
            raise ValueError('Source font blob mismatch: ' + relative)
        inputs[relative] = {'sha256': sha256(path), 'git_blob_sha1': expected['git_blob_sha1'],
                            'repository_path': expected['repository_path']}
    result = {'schema_version': 1, 'license_notice': 'PRIVATE source fonts and derived metrics. Do not publish.',
              'source_commit': lock['source_commit'], 'repository': lock.get('repository', ''),
              'inputs': inputs, 'fonts': {}, 'missing': missing}
    settings_path = lock.get('tmp_settings')
    if settings_path:
        if settings_path not in files:
            raise ValueError('TMP settings input must be hash-locked')
        if settings_path not in missing:
            settings = next((d['fields'] for d in parse_unity(inside(source, settings_path))
                             if d['object_type'] == 'MonoBehaviour' and 'm_defaultFontAsset' in d['fields']), {})
            result['tmp_default_font_guid'] = settings.get('m_defaultFontAsset', {}).get('guid', '')
    pending = []
    for record in lock.get('fonts', []):
        paths = [record[k] for k in ('asset', 'asset_meta', 'ttf', 'ttf_meta', 'license')]
        if any(path not in files for path in paths):
            raise ValueError('Every font input must be hash-locked')
        if any(path in missing for path in paths):
            continue # Registry exposes no binding; caller reports an explicit fallback.
        guid = meta_guid(inside(source, record['asset_meta']))
        ttf_guid = meta_guid(inside(source, record['ttf_meta']))
        if guid in result['fonts']:
            raise ValueError('Duplicate source font GUID')
        docs = parse_unity(inside(source, record['asset']))
        font = next((d['fields'] for d in docs if d['object_type'] == 'MonoBehaviour' and 'm_FaceInfo' in d['fields']), None)
        if font is None or font.get('m_SourceFontFileGUID') != ttf_guid:
            raise ValueError('TMP source-font GUID does not match locked TTF metadata')
        if not font.get('m_GlyphTable') or not font.get('m_CharacterTable'):
            raise ValueError('Static source glyph metrics required for this adapter')
        metrics = {key: font.get(key) for key in ('normalSpacingOffset', 'boldSpacing', 'm_FaceInfo', 'm_GlyphTable', 'm_CharacterTable',
                   'm_FontFeatureTable', 'm_FontWeightTable', 'm_FallbackFontAssetTable', 'm_AtlasPopulationMode',
                   'm_AtlasWidth', 'm_AtlasHeight', 'm_AtlasPadding', 'm_AtlasRenderMode')}
        metrics['source_font_guid'] = guid
        metrics['source_ttf_guid'] = ttf_guid
        metric_bytes = json_bytes(metrics)
        result['fonts'][guid] = {'font_path': guid + '/source.ttf', 'metrics_path': guid + '/metrics.json',
                                'license_path': guid + '/LICENSE.txt', 'ttf_guid': ttf_guid,
                                'ttf_sha256': inputs[record['ttf']]['sha256'],
                                'license_sha256': inputs[record['license']]['sha256'],
                                'metrics_sha256': hashlib.sha256(metric_bytes).hexdigest(),
                                'family': font['m_FaceInfo'].get('m_FamilyName', ''),
                                'style': font['m_FaceInfo'].get('m_StyleName', ''),
                                'rendering_status': 'exact_source_font_identity; native_Godot_layout_not_TMP_SDF_parity'}
        pending.append((guid, inside(source, record['ttf']).read_bytes(), inside(source, record['license']).read_bytes(), metric_bytes))
    # No output is changed until all hashes and GUID chains have validated.
    output.mkdir(parents=True, exist_ok=True)
    for guid, ttf, license_data, metrics in pending:
        target = output / guid; target.mkdir(parents=True, exist_ok=True)
        (target / 'source.ttf').write_bytes(ttf)
        (target / 'LICENSE.txt').write_bytes(license_data)
        (target / 'metrics.json').write_bytes(metrics)
    (output / 'manifest.json').write_bytes(json_bytes(result))
    return result

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--catalog', required=True, type=Path)
    parser.add_argument('--lock', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--acknowledge-license', action='store_true', required=True)
    args = parser.parse_args()
    if args.output.resolve() != Path('assets/imported/fonts').resolve():
        parser.error('Private font output must be assets/imported/fonts under the project')
    catalog_commit = json.loads(args.catalog.read_text())['provenance']['source_commit']
    result = build(args.source, json.loads(args.lock.read_text()), args.output, catalog_commit)
    print('Private source fonts:', len(result['fonts']), 'bindings;', len(result['missing']), 'missing files')
