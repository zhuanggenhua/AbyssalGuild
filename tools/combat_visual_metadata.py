"""Private combat sprite/rectangle bindings, resolved by serialized references."""
from __future__ import annotations
from source_font_metadata import font_reference
import copy
import math
import struct
from visual_scene_metadata import transform_chain


def _finite_vector(value, keys):
    return isinstance(value, dict) and all(isinstance(value.get(k), (int, float)) and math.isfinite(value[k]) for k in keys)


def sprite_metadata(importer, png_bytes):
    """Only a single full-image sprite is supported; no guessed atlas regions."""
    if importer.get('textureType') != 8 or importer.get('spriteMode') != 1:
        return {}
    ppu, pivot = importer.get('spritePixelsToUnits'), importer.get('spritePivot')
    alignment = importer.get('alignment')
    if alignment == 0:
        pivot = {'x': 0.5, 'y': 0.5}
    elif alignment != 9:
        return {} # Other automatic pivot modes are outside this adapter.
    if not isinstance(ppu, (int, float)) or not math.isfinite(ppu) or ppu <= 0 or not _finite_vector(pivot, 'xy'):
        return {}
    if len(png_bytes) < 24 or png_bytes[:8] != b'\x89PNG\r\n\x1a\n' or png_bytes[12:16] != b'IHDR':
        return {}
    width, height = struct.unpack('>II', png_bytes[16:24])
    if not width or not height:
        return {}
    return {'pixels_per_unit': ppu, 'pivot': copy.deepcopy(pivot), 'pixel_size': {'x': width, 'y': height},
            'filter_mode': importer.get('textureSettings', {}).get('filterMode'),
            'mesh_type': importer.get('spriteMeshType'), 'mode': 'single_full_image'}


def projectile_metadata(documents, component_ref):
    component = next((d for d in documents if str(d['file_id']) == str(component_ref.get('fileID')) and d['object_type'] == 'MonoBehaviour'), {})
    fields = component.get('fields', {})
    owner = fields.get('m_GameObject')
    renderer = next((d['fields'] for d in documents if d['object_type'] == 'SpriteRenderer' and d['fields'].get('m_GameObject') == owner), {})
    pose = transform_chain(documents, owner)
    duration = fields.get('duration')
    if not renderer or not pose or not isinstance(duration, (int, float)) or not math.isfinite(duration) or duration <= 0:
        return {}
    return {'transform_chain': pose, 'duration': duration,
            'sprite': copy.deepcopy(renderer.get('m_Sprite', {})), 'color': copy.deepcopy(renderer.get('m_Color', {})),
            'flip_x': renderer.get('m_FlipX'), 'flip_y': renderer.get('m_FlipY'),
            'draw_mode': renderer.get('m_DrawMode'), 'materials': copy.deepcopy(renderer.get('m_Materials', [])),
            'sorting_order': renderer.get('m_SortingOrder'), 'cast_shadows': renderer.get('m_CastShadows')}


def _rect(documents, owner):
    return next((d for d in documents if d['object_type'] == 'RectTransform' and d['fields'].get('m_GameObject') == owner), {})


def _rect_geometry(rect, parent=None):
    keys = ('m_LocalPosition', 'm_LocalRotation', 'm_LocalScale')
    if not all(_finite_vector(rect.get(k), 'xyzw' if k == 'm_LocalRotation' else 'xyz') for k in keys):
        return {}
    if not all(_finite_vector(rect.get(k), 'xy') for k in ('m_SizeDelta', 'm_Pivot', 'm_AnchorMin', 'm_AnchorMax', 'm_AnchoredPosition')):
        return {}
    size = copy.deepcopy(rect['m_SizeDelta'])
    pose = {key: copy.deepcopy(rect[key]) for key in keys}
    if parent is None:
        # Instantiate supplies world position/rotation. Keep only source scale.
        pose['m_LocalPosition'] = {'x': 0, 'y': 0, 'z': 0}
        pose['m_LocalRotation'] = {'x': 0, 'y': 0, 'z': 0, 'w': 1}
    else:
        for axis in 'xy':
            amin, amax = rect['m_AnchorMin'][axis], rect['m_AnchorMax'][axis]
            size[axis] += parent['size'][axis] * (amax - amin)
            pose['m_LocalPosition'][axis] = parent['size'][axis] * (amin + (amax - amin) * rect['m_Pivot'][axis] - parent['pivot'][axis]) + rect['m_AnchoredPosition'][axis]
    if size['x'] <= 0 or size['y'] <= 0:
        return {}
    return {'pose': pose, 'size': size, 'pivot': copy.deepcopy(rect['m_Pivot'])}


def hit_ui_metadata(documents, component_ref):
    by_id = {str(d['file_id']): d for d in documents}
    component = by_id.get(str(component_ref.get('fileID')), {})
    if component.get('object_type') != 'MonoBehaviour':
        return {}
    fields = component['fields']
    root_rect = _rect(documents, fields.get('m_GameObject'))
    root = _rect_geometry(root_rect.get('fields', {}))
    if not root or str(root_rect['fields'].get('m_Father', {}).get('fileID', '0')) != '0':
        return {}
    roles = {}
    for field, role in [('hitImage', 'hit'), ('effectivenessImage', 'effectiveness'), ('damageLabel', 'damage')]:
        target = by_id.get(str(fields.get(field, {}).get('fileID')), {})
        if target.get('object_type') != 'MonoBehaviour':
            return {}
        tf = target['fields']
        rect = _rect(documents, tf.get('m_GameObject'))
        if rect.get('file_id') == root_rect['file_id']:
            geometry = copy.deepcopy(root)
            # Root scale belongs to the popup container, not the image twice.
            geometry['pose']['m_LocalScale'] = {'x': 1, 'y': 1, 'z': 1}
        elif str(rect.get('fields', {}).get('m_Father', {}).get('fileID')) == root_rect['file_id']:
            geometry = _rect_geometry(rect['fields'], root)
        else:
            return {} # Unsupported nesting must not guess a layout.
        if not geometry:
            return {}
        geometry.update({'color': copy.deepcopy(tf.get('m_fontColor' if role == 'damage' else 'm_Color', {})),
                         'material': copy.deepcopy(tf.get('m_Material', {}))})
        if role == 'damage':
            geometry.update({**font_reference(tf), 'font_size': tf.get('m_fontSize'), 'font_asset': copy.deepcopy(tf.get('m_fontAsset', {})),
                             'horizontal_alignment': tf.get('m_HorizontalAlignment'), 'vertical_alignment': tf.get('m_VerticalAlignment')})
        else:
            geometry.update({'image_type': tf.get('m_Type'), 'preserve_aspect': tf.get('m_PreserveAspect')})
        roles[role] = geometry
    return {'root_scale': root['pose']['m_LocalScale'], 'roles': roles,
            'sprites': {name: copy.deepcopy(fields.get(name + 'Sprite', {})) for name in ('miss', 'normal', 'critical', 'advantage', 'disadvantage')}}


def combat_metadata(fields, read):
    result = {'projectiles': {}}
    for field, kind in [('arrowProjectile', '2'), ('magicProjectile', '3')]:
        reference = fields.get(field, {})
        if reference.get('guid'):
            record = projectile_metadata(read(reference['guid']), reference)
            if record:
                record['prefab_guid'] = reference['guid']
                result['projectiles'][kind] = record
    reference = fields.get('hitUIPrefab', {})
    if reference.get('guid'):
        record = hit_ui_metadata(read(reference['guid']), reference)
        if record:
            record['prefab_guid'] = reference['guid']
            result['hit_ui'] = record
    return result
