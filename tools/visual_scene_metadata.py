"""Resolve source camera/light transforms without guessing Euler hints or defaults."""
from __future__ import annotations
import copy

def apply_overrides(documents, modifications):
    documents = copy.deepcopy(documents)
    by_id = {str(d['file_id']): d for d in documents}
    for mod in modifications:
        target = by_id.get(str(mod.get('target', {}).get('fileID', '')))
        if target is None:
            continue
        keys = mod.get('propertyPath', '').split('.')
        fields = target['fields']
        for key in keys[:-1]:
            fields = fields.get(key, {}) if isinstance(fields, dict) else {}
        if not isinstance(fields, dict) or keys[-1] not in fields:
            continue
        value = mod.get('value')
        previous = fields[keys[-1]]
        if isinstance(previous, (float, int)):
            value = float(value)
        elif isinstance(previous, dict):
            value = copy.deepcopy(mod.get('objectReference', {}))
        fields[keys[-1]] = value
    return documents

def transform_chain(documents, owner):
    transforms = {str(d['file_id']): d['fields'] for d in documents if d['object_type'] == 'Transform'}
    current = next((key for key, f in transforms.items() if f.get('m_GameObject') == owner), '')
    chain, seen = [], set()
    while current not in ('', '0'):
        if current in seen or current not in transforms:
            return []
        seen.add(current)
        fields = transforms[current]
        if not all(key in fields for key in ('m_LocalPosition', 'm_LocalRotation', 'm_LocalScale')):
            return []
        chain.append({key: copy.deepcopy(fields[key]) for key in ('m_LocalPosition', 'm_LocalRotation', 'm_LocalScale')})
        current = str(fields.get('m_Father', {}).get('fileID', '0'))
    return list(reversed(chain))

def camera_records(documents, external_parent=False):
    result = []
    for doc in documents:
        if doc['object_type'] != 'Camera':
            continue
        f = doc['fields']
        chain = [] if external_parent else transform_chain(documents, f.get('m_GameObject'))
        record = {'file_id': doc['file_id'], 'transform_chain': chain,
                  'resolved_pose': bool(chain), 'coordinate_system': 'Unity left-handed; +Z camera forward',
                  'orthographic': f.get('orthographic'), 'orthographic_size': f.get('orthographic size'),
                  'field_of_view': f.get('field of view'), 'near': f.get('near clip plane'), 'far': f.get('far clip plane'),
                  'fov_axis': f.get('m_FOVAxisMode'), 'background': f.get('m_BackGroundColor')}
        result.append(record)
    return result

def light_records(documents):
    return [{'fields': copy.deepcopy(d['fields']), 'transform_chain': transform_chain(documents, d['fields'].get('m_GameObject'))}
            for d in documents if d['object_type'] == 'Light']
