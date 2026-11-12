"""Resolve the scene's explicitly referenced ShaderGraph default outline material."""
import json

def outline_metadata(manager, read, index, source):
    reference = manager.get('cardSettings', {})
    settings = next((d['fields'] for d in read(reference.get('guid', '')) if d['object_type'] == 'MonoBehaviour' and str(d['file_id']) == str(reference.get('fileID'))), {})
    material = settings.get('outlineMaterial', {})
    path = index.get(material.get('guid', ''), {}).get('source_path', '')
    if path != 'Shaders/CardOutline.shadergraph' or not str(material.get('fileID', '')).startswith('-'):
        return {}
    text = (source / path).read_text(encoding='utf-8-sig')
    decoder = json.JSONDecoder()
    objects = []
    while text.strip():
        item, end = decoder.raw_decode(text.lstrip())
        objects.append(item)
        text = text.lstrip()[end:]
    properties = {o.get('m_OverrideReferenceName') or o.get('m_DefaultReferenceName'): o.get('m_Value') for o in objects if 'ShaderProperty' in o.get('m_Type', '')}
    required = ('_OutlineSize', '_OutlineColor', '_MinAlpha', '_RotationSpeed')
    if not all(k in properties for k in required):
        return {}
    return {'reference': material, 'shader_source_path': path, 'properties': {k: properties[k] for k in required}}
