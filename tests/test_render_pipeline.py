import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
import yaml
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from import_render_pipeline import build

class RenderPipelineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.lock = {'source_commit': 'a'*40, 'files': {}, 'custom_feature_script': 'Assets/StackCraft/Scripts/PostProcess/CustomPostProcessFeature.cs'}
        self.catalog = {'provenance': {'source_commit': 'a'*40}, 'guid_index': {'c'*32: {'kind': 'cs', 'source_path': 'Scripts/PostProcess/CustomPostProcessFeature.cs'}}}
        self.put(self.lock['custom_feature_script'], 'class CustomPostProcessFeature : ScriptableRendererFeature {}')
        self.put(self.lock['custom_feature_script']+'.meta', 'guid: '+'c'*32+'\n')
        self.doc('ProjectSettings/GraphicsSettings.asset','GraphicsSettings',30,{'m_CustomRenderPipeline':{'fileID':11400000,'guid':'1'*32}})
        self.quality={'m_CurrentQuality':0,'m_PerPlatformDefaultQuality':{'Standalone':1,'Android':0},'m_QualitySettings':[{'name':'Mobile','customRenderPipeline':{'fileID':0}},{'name':'Desktop','customRenderPipeline':{'fileID':11400000,'guid':'2'*32}}]}
        self.doc('ProjectSettings/QualitySettings.asset','QualitySettings',47,self.quality)
        for idx in [1,2]:
            self.asset(str(idx)*32, {'m_RendererDataList':[{'fileID':11400000,'guid':str(idx+2)*32}], 'm_DefaultRendererIndex':0})
            self.asset(str(idx+2)*32, {'m_RendererFeatures':[]})
    def put(self,path,text):
        data=text.encode();p=self.root/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
        self.lock['files'][path]={'repository_path':path,'git_blob_sha1':hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()}
    def doc(self,path,kind,cls,fields):
        self.put(path,'%%YAML 1.1\n%%TAG !u! tag:unity3d.com,2011:\n--- !u!%d &11400000\n'%cls+yaml.safe_dump({kind:fields},sort_keys=False))
    def asset(self,guid,fields):
        path='Assets/Arbitrary/'+guid+'.asset';self.doc(path,'MonoBehaviour',114,fields);self.put(path+'.meta','guid: '+guid+'\n')
    def test_platform_override_chain_not_editor_quality(self):
        result=build(self.root,self.lock,self.catalog)
        self.assertEqual(result['selected_quality'],1)
        self.assertEqual(result['editor_quality'],0)
        self.assertEqual(result['qualities'][1]['pipeline_guid'],'2'*32)
        self.assertEqual(result['pipelines']['2'*32]['renderer_guids'],['4'*32])
        self.assertEqual(build(self.root,self.lock,self.catalog,'Android')['selected_quality'],0)
    def test_builtin_quality_and_graphics_null(self):
        self.doc('ProjectSettings/GraphicsSettings.asset','GraphicsSettings',30,{'m_CustomRenderPipeline':{'fileID':0}})
        self.quality['m_QualitySettings'][1]['customRenderPipeline']={'fileID':0};self.doc('ProjectSettings/QualitySettings.asset','QualitySettings',47,self.quality)
        result=build(self.root,self.lock,self.catalog);self.assertFalse(result['graphics_pipeline_guid']);self.assertFalse(result['pipelines'])
    def test_blob_tamper_rejected(self):
        (self.root/'ProjectSettings/GraphicsSettings.asset').write_text('changed')
        with self.assertRaises(ValueError):build(self.root,self.lock,self.catalog)
    def test_wrong_commit_rejected(self):
        self.catalog['provenance']['source_commit']='b'*40
        with self.assertRaises(ValueError):build(self.root,self.lock,self.catalog)
    def test_missing_renderer_rejected(self):
        del self.lock['files']['Assets/Arbitrary/'+'4'*32+'.asset']
        with self.assertRaises(ValueError):build(self.root,self.lock,self.catalog)
    def test_unknown_platform_rejected(self):
        with self.assertRaises(ValueError):build(self.root,self.lock,self.catalog,'Unknown')
    def test_arbitrary_feature_material_identity(self):
        p='Assets/Arbitrary/'+'4'*32+'.asset'
        self.doc(p,'MonoBehaviour',114,{'m_RendererFeatures':[{'fileID':23}]})
        self.put(p,(self.root/p).read_text()+'--- !u!114 &23\n'+yaml.safe_dump({'MonoBehaviour':{'m_Script':{'fileID':11500000,'guid':'c'*32},'m_Active':1,'settings':{'effectMaterial':{'fileID':21,'guid':'f'*32}}}},sort_keys=False))
        feature=build(self.root,self.lock,self.catalog)['renderers']['4'*32]['features'][0]
        self.assertEqual(feature,{'script_guid':'c'*32,'active':True,'material_guid':'f'*32,'material_file_id':'21'})
    def test_script_identity_and_guid_must_match_catalog(self):
        self.catalog['guid_index']={}
        with self.assertRaises(ValueError):build(self.root,self.lock,self.catalog)
