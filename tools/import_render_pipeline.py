#!/usr/bin/env python3
"""Import a PRIVATE, same-commit locked project rendering dependency graph.

No source GUID is hardcoded. This bounded adapter recognizes Unity's serialized
URP renderer-list schema and the locked CustomPostProcessFeature script identity.
It does not translate URP lighting, SSAO, or arbitrary renderer features.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
from import_stackcraft import parse_unity, json_bytes
from import_source_fonts import inside, blob_sha, meta_guid


def build(source, lock, catalog, target_platform="Standalone"):
    source = Path(source).resolve()
    commit = lock.get('source_commit', '')
    if not re.fullmatch('[0-9a-f]{40}', commit) or commit != catalog.get('provenance', {}).get('source_commit'):
        raise ValueError('Pipeline supplement commit differs from catalog')
    inputs, documents, by_guid = {}, {}, {}
    files = lock.get('files', {})
    for relative, expected in sorted(files.items()):
        path = inside(source, relative)
        if not path.is_file() or blob_sha(path) != expected.get('git_blob_sha1'):
            raise ValueError('Pipeline source missing/blob mismatch: ' + relative)
        if expected.get('repository_path') != relative:
            raise ValueError('Pipeline bundle paths must preserve repository paths')
        inputs[relative] = dict(expected, sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        if path.suffix in ('.asset', '.prefab'):
            documents[relative] = parse_unity(path)
    for relative in files:
        if relative.endswith('.meta') and relative[:-5] in documents:
            guid = meta_guid(inside(source, relative))
            if guid in by_guid:
                raise ValueError('Duplicate pipeline asset GUID')
            by_guid[guid] = documents[relative[:-5]]
    def fields(path, kind):
        if path not in documents:
            raise ValueError('Hash-locked project setting required: ' + path)
        return next(d['fields'] for d in documents[path] if d['object_type'] == kind)
    graphics = fields('ProjectSettings/GraphicsSettings.asset', 'GraphicsSettings')
    quality = fields('ProjectSettings/QualitySettings.asset', 'QualitySettings')
    script_path = lock.get('custom_feature_script', '')
    if script_path not in files or script_path + '.meta' not in files:
        raise ValueError('Hash-locked custom feature script and metadata required')
    if not re.search(r'\bclass\s+CustomPostProcessFeature\s*:\s*ScriptableRendererFeature\b', inside(source, script_path).read_text()):
        raise ValueError('Unsupported custom feature script identity')
    custom_guid = meta_guid(inside(source, script_path + '.meta'))
    indexed = catalog.get('guid_index', {}).get(custom_guid, {})
    if indexed.get('kind') != 'cs' or not script_path.endswith('/' + indexed.get('source_path', '!')):
        raise ValueError('Custom feature GUID differs from locked catalog')
    def guid(ref):
        return str(ref.get('guid', '')) if str(ref.get('fileID', '0')) != '0' else ''
    root_guid = guid(graphics.get('m_CustomRenderPipeline', {}))
    qualities = [{'name': q.get('name', ''), 'pipeline_guid': guid(q.get('customRenderPipeline', {}))} for q in quality.get('m_QualitySettings', [])]
    platform_defaults = quality.get('m_PerPlatformDefaultQuality', {})
    current = platform_defaults.get(target_platform)
    if not isinstance(current, int) or not 0 <= current < len(qualities):
        raise ValueError('Invalid source quality selection')
    pipelines, renderers = {}, {}
    for pg in sorted({root_guid} | {q['pipeline_guid'] for q in qualities} - {''}):
        if not pg:
            continue
        docs = by_guid.get(pg, [])
        f = next((d['fields'] for d in docs if 'm_RendererDataList' in d['fields'] and 'm_DefaultRendererIndex' in d['fields']), None)
        if f is None:
            raise ValueError('Missing/unrecognized selected pipeline asset: ' + pg)
        refs = [guid(r) for r in f['m_RendererDataList']]
        pipelines[pg] = {'schema': 'urp_renderer_list', 'default_renderer_index': f['m_DefaultRendererIndex'], 'renderer_guids': refs}
        for rg in refs:
            if rg in renderers:
                continue
            rd = by_guid.get(rg, [])
            rf = next((d['fields'] for d in rd if 'm_RendererFeatures' in d['fields']), None)
            if rf is None:
                raise ValueError('Missing/unrecognized renderer dependency: ' + rg)
            features = []
            for ref in rf['m_RendererFeatures']:
                # Renderer features are ordinarily local subassets; external refs are resolved too.
                fd = by_guid.get(guid(ref), []) if guid(ref) else rd
                component = next((d for d in fd if str(d['file_id']) == str(ref.get('fileID'))), None)
                if component is None:
                    raise ValueError('Unresolved renderer feature')
                ff = component['fields']
                material = ff.get('settings', {}).get('effectMaterial', {})
                features.append({'script_guid': guid(ff.get('m_Script', {})), 'active': bool(ff.get('m_Active', 0)),
                                 'material_guid': guid(material), 'material_file_id': str(material.get('fileID', '0'))})
            renderers[rg] = {'features': features}
    return {'schema_version': 1, 'source_commit': commit, 'license_notice': 'PRIVATE derived source rendering graph; do not publish.',
            'inputs': inputs, 'graphics_pipeline_guid': root_guid, 'selected_quality': current, 'qualities': qualities,
            'target_platform': target_platform, 'platform_defaults': platform_defaults, 'editor_quality': quality.get('m_CurrentQuality'),
            'pipelines': pipelines, 'renderers': renderers, 'custom_feature_script_guid': custom_guid,
            'scope': 'Renderer-list/pass admission only; not URP lighting, SSAO or complete shader equivalence.'}

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for key in ('source', 'lock', 'catalog', 'output'):
        p.add_argument('--' + key, required=True, type=Path)
    p.add_argument('--target-platform', default='Standalone')
    p.add_argument('--acknowledge-license', required=True, action='store_true')
    a = p.parse_args()
    if a.output.resolve() != Path('assets/imported/render_pipeline.json').resolve():
        p.error('Private pipeline output must be assets/imported/render_pipeline.json')
    result = build(a.source, json.loads(a.lock.read_text()), json.loads(a.catalog.read_text()), a.target_platform)
    a.output.parent.mkdir(parents=True, exist_ok=True)
    data = json_bytes(result)
    a.output.write_bytes(data)
    a.output.with_suffix('.json.sha256').write_text(hashlib.sha256(data).hexdigest() + '\n')
    print('Private render pipeline graph: %d pipelines, %d renderers' % (len(result['pipelines']), len(result['renderers'])))
