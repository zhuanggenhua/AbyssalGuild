"""Source-referenced trading renderers/text. Output is private import data only."""
from copy import deepcopy
from outline_visual_metadata import outline_metadata


def trade_metadata(manager, read, index, source):
    result = {}
    for role, key in [('buyer', 'buyerPrefab'), ('vendor', 'vendorPrefab')]:
        guid = manager.get(key, {}).get('guid', '')
        docs = read(guid)
        component = next((d for d in docs if d['object_type'] == 'MonoBehaviour' and 'outlineMaterial' in d['fields']), None)
        if not component:
            continue
        fields = component['fields']
        owner = fields.get('m_GameObject')
        def of(kind, target):
            return next((d['fields'] for d in docs if d['object_type'] == kind and d['fields'].get('m_GameObject') == target), {})
        def pose(target):
            value = of('Transform', target) or of('RectTransform', target)
            return {key: deepcopy(value[key]) for key in ('m_LocalPosition', 'm_LocalRotation', 'm_LocalScale') if key in value}
        renderer = of('MeshRenderer', owner)
        record = {'prefab_guid': guid, 'source_path': index.get(guid, {}).get('source_path', ''),
                  'mesh': of('MeshFilter', owner).get('m_Mesh', {}),
                  'materials': renderer.get('m_Materials', []),
                  'cast_shadows': renderer.get('m_CastShadows', 0),
                  'receive_shadows': renderer.get('m_ReceiveShadows', 0), 'labels': {}}
        # Resolve the ACTUAL trade component's material, not CardSettings.
        record['outline'] = outline_metadata({'cardSettings': {'guid': guid, 'fileID': component['file_id']}}, read, index, source)
        for name, reference in [('title', fields.get('titleText')), ('price', fields.get('priceText')), ('tracker', fields.get('trackerText'))]:
            text = next((d['fields'] for d in docs if reference and str(d['file_id']) == str(reference.get('fileID'))), {})
            if role == 'buyer' and name == 'title':
                text = next((d['fields'] for d in docs if d['object_type'] == 'MonoBehaviour' and 'm_text' in d['fields']), {})
            if not text:
                continue
            target = text['m_GameObject']
            record['labels'][name] = {'pose': pose(target), 'rect': deepcopy(of('RectTransform', target)), 'text': deepcopy(text)}
        icon = next((d['fields'] for d in docs if str(d['file_id']) == str(fields.get('iconRenderer', {}).get('fileID'))), {})
        if icon:
            target = icon['m_GameObject']
            record['icon'] = {'pose': pose(target), 'mesh': of('MeshFilter', target).get('m_Mesh', {}),
                              'materials': icon.get('m_Materials', []), 'cast_shadows': icon.get('m_CastShadows', 0)}
        result[role] = record
    return deepcopy(result)
