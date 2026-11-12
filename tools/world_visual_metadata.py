"""Read scene-authored world visuals; generated metadata stays private."""
from copy import deepcopy
from visual_scene_metadata import transform_chain


def world_metadata(documents):
    settings = next((deepcopy(d['fields']) for d in documents
                     if d['object_type'] == 'RenderSettings'), {})
    meshes = []
    for doc in documents:
        if doc['object_type'] != 'MeshRenderer':
            continue
        fields = doc['fields']
        owner = fields.get('m_GameObject')
        mesh = next((d['fields'].get('m_Mesh', {}) for d in documents
                     if d['object_type'] == 'MeshFilter' and d['fields'].get('m_GameObject') == owner), {})
        meshes.append({'file_id': doc['file_id'], 'mesh': deepcopy(mesh),
                       'transform_chain': transform_chain(documents, owner),
                       'materials': deepcopy(fields.get('m_Materials', [])),
                       'enabled': fields.get('m_Enabled', 0),
                       'cast_shadows': fields.get('m_CastShadows', 0),
                       'receive_shadows': fields.get('m_ReceiveShadows', 0)})
    return {'render_settings': settings, 'scene_meshes': meshes}
