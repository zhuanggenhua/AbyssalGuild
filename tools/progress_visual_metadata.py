"""Source ProgressUI / effective world-canvas data; output remains private."""
from copy import deepcopy
from visual_scene_metadata import transform_chain

def progress_metadata(manager, read):
    docs=read(manager.get('progressUIPrefab',{}).get('guid',''))
    behaviour=next((d['fields'] for d in docs if 'displayOffset' in d['fields']),{})
    fill=next((d['fields'] for d in docs if str(d['file_id'])==str(behaviour.get('progressFill',{}).get('fileID',''))),{})
    root=next((d['fields'] for d in docs if d['object_type']=='RectTransform' and str(d['fields'].get('m_Father',{}).get('fileID'))=='0'),{})
    background=next((d['fields'] for d in docs if d['fields'].get('m_GameObject')==root.get('m_GameObject') and 'm_Color' in d['fields']),{})
    if not all([behaviour,fill,root,background]):return {}
    return deepcopy({'size':root.get('m_SizeDelta',{}),'offset':behaviour['displayOffset'],'background':background['m_Color'],'fill':fill['m_Color'],'sprite':fill.get('m_Sprite',{}),'image_type':fill.get('m_Type'),'fill_method':fill.get('m_FillMethod'),'fill_origin':fill.get('m_FillOrigin')})

def world_canvas_chain(documents):
    docs=deepcopy(documents)
    owner=next((d['fields'].get('m_GameObject') for d in docs if d['fields'].get('m_Script',{}).get('guid')=='d5480d6e0dbe4a343a6a4a6bfaff57fb'),None)
    if owner is None:return []
    for d in docs:
        if d['object_type']=='RectTransform':d['object_type']='Transform'
    return transform_chain(docs,owner)

def board_effective_pose(documents):
    renderer=next((d['fields'] for d in documents if d['object_type']=='SkinnedMeshRenderer'),{})
    return transform_chain(documents,renderer.get('m_GameObject')) if renderer else []
