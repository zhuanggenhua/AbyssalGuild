import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from progress_visual_metadata import progress_metadata, board_effective_pose, world_canvas_chain
from visual_scene_metadata import apply_overrides

def doc(kind, ident, **fields):
    return {'object_type':kind,'file_id':str(ident),'fields':fields}
def pose(owner, parent='0'):
    return {'m_GameObject':{'fileID':str(owner)},'m_Father':{'fileID':parent},'m_LocalPosition':{'x':1,'y':2,'z':3},'m_LocalRotation':{'x':0,'y':0,'z':0,'w':1},'m_LocalScale':{'x':1,'y':1,'z':1}}
class Metadata(unittest.TestCase):
    def test_effective_board_is_not_prefab_default(self):
        docs=[doc('Transform',1,**pose(10)),doc('SkinnedMeshRenderer',2,m_GameObject={'fileID':'10'})]
        effective=apply_overrides(docs,[{'target':{'fileID':'1'},'propertyPath':'m_LocalPosition.y','value':'-0.37'}])
        self.assertEqual(board_effective_pose(effective)[0]['m_LocalPosition']['y'],-.37)
        self.assertEqual(docs[0]['fields']['m_LocalPosition']['y'],2)
    def test_progress_references_are_followed_not_first_image(self):
        tint={'r':.1,'g':.2,'b':.3,'a':.4}
        docs=[doc('MonoBehaviour',9,m_GameObject={'fileID':'wrong'},m_Color=tint),
              doc('RectTransform',1,**pose(10),m_SizeDelta={'x':2,'y':.3}),
              doc('MonoBehaviour',2,m_GameObject={'fileID':'10'},m_Color=tint),
              doc('MonoBehaviour',3,m_GameObject={'fileID':'11'},m_Color=tint,m_Sprite={'guid':'synthetic'},m_Type=3,m_FillMethod=0,m_FillOrigin=0),
              doc('MonoBehaviour',4,displayOffset={'x':1,'y':2,'z':3},progressFill={'fileID':'3'})]
        out=progress_metadata({'progressUIPrefab':{'guid':'fixture'}},lambda guid:docs if guid=='fixture' else [])
        self.assertEqual(out['sprite']['guid'],'synthetic')
        self.assertEqual(out['size'],{'x':2,'y':.3})
        self.assertEqual(progress_metadata({},lambda _:[]),{})
    def test_canvas_ancestor_trs_retained(self):
        docs=[doc('Transform',1,**pose(10)),doc('RectTransform',2,**pose(20,'1')),
              doc('MonoBehaviour',3,m_GameObject={'fileID':'20'},m_Script={'guid':'d5480d6e0dbe4a343a6a4a6bfaff57fb'})]
        self.assertEqual(len(world_canvas_chain(docs)),2)
        self.assertEqual(docs[1]['object_type'],'RectTransform')
if __name__=='__main__': unittest.main()
