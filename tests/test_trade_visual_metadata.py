import json
import tempfile
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from trade_visual_metadata import trade_metadata

class TradeMetadataTests(unittest.TestCase):
    def test_reference_owned_components_and_outline(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            (source / 'Shaders').mkdir()
            properties = {'_OutlineSize': .2, '_OutlineColor': {'r':1,'g':0,'b':0,'a':1}, '_MinAlpha': .4, '_RotationSpeed': 3}
            (source / 'Shaders/CardOutline.shadergraph').write_text('\n'.join(json.dumps({'m_Type':'ShaderProperty','m_DefaultReferenceName':k,'m_Value':v}) for k,v in properties.items()))
            def doc(kind, file_id, owner, **fields):
                return {'object_type':kind,'file_id':file_id,'fields':{'m_GameObject':{'fileID':owner},**fields}}
            docs = [doc('MonoBehaviour',1,2,outlineMaterial={'guid':'outline','fileID':-8},titleText={'fileID':7}),
                    doc('MeshFilter',3,2,m_Mesh={'guid':'mesh'}),doc('MeshRenderer',4,2,m_Materials=[{'guid':'material'}]),
                    doc('MonoBehaviour',7,6,m_text='???',m_fontSize=1.3),
                    doc('RectTransform',8,6,m_LocalPosition={'x':2,'y':3,'z':4},m_LocalRotation={'w':1},m_LocalScale={'x':1,'y':1,'z':1},m_SizeDelta={'x':.9,'y':.5})]
            result = trade_metadata({'vendorPrefab':{'guid':'vendor'}},lambda guid:docs if guid=='vendor' else [], {'vendor':{'source_path':'Prefabs/vendor.prefab'},'outline':{'source_path':'Shaders/CardOutline.shadergraph'}},source)
            self.assertEqual(set(result), {'vendor'})
            self.assertEqual(result['vendor']['mesh'], {'guid':'mesh'})
            self.assertEqual(result['vendor']['labels']['title']['text']['m_text'], '???')
            self.assertEqual(result['vendor']['labels']['title']['pose']['m_LocalPosition']['z'],4)
            self.assertEqual(result['vendor']['outline']['properties'],properties)
            docs[2]['fields']['m_Materials'][0]['guid']='changed'
            self.assertEqual(result['vendor']['materials'][0]['guid'],'material')
    def test_missing_components_fail_closed(self):
        self.assertEqual(trade_metadata({'vendorPrefab':{'guid':'x'}},lambda _:[],{},Path('.')), {})
if __name__=='__main__': unittest.main()
