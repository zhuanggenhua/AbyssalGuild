"""Resolve only explicitly referenced card labels/panels into private metadata."""
from __future__ import annotations
import copy
from visual_scene_metadata import transform_chain
from equipment_interaction_metadata import interaction_metadata


def annotations(documents, owner):
    if not isinstance(owner, dict) or not owner.get("fileID"):
        return {"labels": {}, "equipment_panel": {}}
    by_id = {str(d['file_id']): d for d in documents}
    root_transform = next((d for d in documents if d['object_type'] == 'Transform' and d['fields'].get('m_GameObject') == owner), {})
    root_pose = transform_chain(documents, owner)
    labels, panel = {}, {}
    roles = {'titleText': 'title', 'priceText': 'price', 'nutritionText': 'nutrition', 'healthText': 'health'}
    for doc in documents:
        if doc['object_type'] != 'MonoBehaviour' or doc['fields'].get('m_GameObject') != owner:
            continue
        fields = doc['fields']
        for field, role in roles.items():
            target = by_id.get(str(fields.get(field, {}).get('fileID', '0')), {})
            if target.get('object_type') != 'MonoBehaviour':
                continue
            text = target['fields']
            rect = next((d['fields'] for d in documents if d['object_type'] == 'RectTransform' and d['fields'].get('m_GameObject') == text.get('m_GameObject')), {})
            keys = ('m_LocalPosition', 'm_LocalRotation', 'm_LocalScale')
            if not root_pose or 'm_fontColor' not in text or not all(k in rect for k in keys):
                continue
            # A plain Transform parent has no rectangle. Anchored X/Y resolve
            # relative to its origin; Z still comes from the local transform.
            # Nested RectTransform layouts need a separate layout resolver.
            if str(rect.get('m_Father', {}).get('fileID')) != str(root_transform.get('file_id')):
                continue
            pose = {key: copy.deepcopy(rect[key]) for key in keys}
            anchored = rect.get('m_AnchoredPosition', {})
            if 'x' in anchored and 'y' in anchored:
                pose['m_LocalPosition']['x'] = anchored['x']
                pose['m_LocalPosition']['y'] = anchored['y']
            labels[role] = {'transform_chain': copy.deepcopy(root_pose) + [pose],
                            'color': copy.deepcopy(text['m_fontColor']),
                            'rect_size': copy.deepcopy(rect.get('m_SizeDelta', {})),
                            'font_size': text.get('m_fontSize'),
                            'auto_size': text.get('m_enableAutoSizing'),
                            'font_size_min': text.get('m_fontSizeMin'),
                            'font_size_max': text.get('m_fontSizeMax'),
                            'word_wrap': text.get('m_enableWordWrapping'),
                            'overflow_mode': text.get('m_overflowMode'),
                            'margin': copy.deepcopy(text.get('m_margin', {})),
                            'horizontal_alignment': text.get('m_HorizontalAlignment'),
                            'vertical_alignment': text.get('m_VerticalAlignment'),
                            'anchor_resolution': 'plain_transform_parent'}
        target = by_id.get(str(fields.get('equipmentPanel', {}).get('fileID', '0')), {})
        if target.get('object_type') != 'MonoBehaviour':
            continue
        panel_owner = target['fields'].get('m_GameObject')
        if not isinstance(panel_owner, dict):
            continue
        renderer = next((d['fields'] for d in documents if d['object_type'] == 'MeshRenderer' and d['fields'].get('m_GameObject') == panel_owner), {})
        mesh = next((d['fields'].get('m_Mesh', {}) for d in documents if d['object_type'] == 'MeshFilter' and d['fields'].get('m_GameObject') == panel_owner), {})
        collider = next((d['fields'] for d in documents if d['object_type'] == 'BoxCollider' and d['fields'].get('m_GameObject') == panel_owner), {})
        pose = transform_chain(documents, panel_owner)
        if renderer and mesh and pose:
            panel = {'mesh': mesh, 'materials': renderer.get('m_Materials', []),
                     'transform_chain': pose, 'size': collider.get('m_Size', {}),
                     'center': collider.get('m_Center', {}),
                     'interaction': interaction_metadata(target['fields'])}
    return {'labels': labels, 'equipment_panel': panel}
