"""Synthetic owner matching tests. No licensed source or exported records included."""
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from import_visual_assets import build


class CardMeshImportTests(unittest.TestCase):
    def import_prefab(self, text):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'source'
            source.mkdir()
            (source / 'synthetic.prefab').write_text(text)
            catalog = {'guid_index': {'prefab': {'source_path': 'synthetic.prefab'}},
                       'scenes': [{'name': 'Synthetic', 'documents': [
                           {'object_type': 'MonoBehaviour', 'fields': {
                               'packPrefab': {'guid': 'prefab'}, 'cardPrefabs': []}}]}]}
            return build(source, catalog, Path(directory) / 'out')['prefabs']['prefab']

    def test_mesh_filter_matches_collider_renderer_not_text_child(self):
        result = self.import_prefab('''--- !u!33 &10
MeshFilter:
  m_GameObject: {fileID: 2}
  m_Mesh: {fileID: 11, guid: wrong}
--- !u!23 &20
MeshRenderer:
  m_GameObject: {fileID: 2}
  m_Materials: [{guid: text}]
--- !u!33 &30
MeshFilter:
  m_GameObject: {fileID: 1}
  m_Mesh: {fileID: 31, guid: correct}
--- !u!23 &40
MeshRenderer:
  m_GameObject: {fileID: 1}
  m_Materials: [{guid: body}]
--- !u!65 &50
BoxCollider:
  m_GameObject: {fileID: 1}
  m_Size: {x: 2, y: 0, z: 3}
--- !u!4 &60
Transform:
  m_GameObject: {fileID: 1}
  m_LocalPosition: {x: 0, y: 1, z: 2}
  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}
  m_LocalScale: {x: 1, y: 2, z: 1}
  m_Father: {fileID: 70}
--- !u!4 &70
Transform:
  m_GameObject: {fileID: 3}
  m_LocalPosition: {x: 4, y: 5, z: 6}
  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}
  m_LocalScale: {x: 1, y: 1, z: 1}
  m_Father: {fileID: 0}
''')
        self.assertEqual(result['mesh'], {'fileID': '31', 'guid': 'correct'})
        self.assertEqual(result['materials'], [{'guid': 'body'}])
        self.assertEqual(result['size'], {'x': 2, 'y': 0, 'z': 3})
        self.assertEqual(len(result['renderers']), 2)
        self.assertEqual([pose['m_LocalPosition']['x'] for pose in result['transform_chain']], [4, 0])

    def test_skinned_mesh_reference_takes_precedence(self):
        result = self.import_prefab('''--- !u!137 &1
SkinnedMeshRenderer:
  m_GameObject: {fileID: 2}
  m_Mesh: {fileID: 5, guid: skinned}
  m_Materials: [{guid: surface}]
--- !u!33 &3
MeshFilter:
  m_GameObject: {fileID: 2}
  m_Mesh: {fileID: 4, guid: unused}
''')
        self.assertEqual(result['mesh']['guid'], 'skinned')
        self.assertEqual(result['transform_chain'], [])

    def test_missing_filter_does_not_borrow_child_geometry(self):
        result = self.import_prefab('''--- !u!23 &1
MeshRenderer:
  m_GameObject: {fileID: 2}
--- !u!33 &3
MeshFilter:
  m_GameObject: {fileID: 4}
  m_Mesh: {fileID: 5, guid: wrong}
''')
        self.assertEqual(result['mesh'], {})

    def test_material_shader_identity_and_title_pose_are_private_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'source'
            source.mkdir()
            (source / 'synthetic.mat').write_text("""--- !u!21 &1
Material:
  m_Name: Synthetic
  m_Shader: {guid: shader}
  m_SavedProperties: {}
""")
            catalog = {'guid_index': {'material': {'source_path': 'synthetic.mat'},
                                     'shader': {'source_path': 'Shaders/Synthetic.shadergraph'}}, 'scenes': []}
            result = build(source, catalog, Path(directory) / 'out')
            self.assertEqual(result['materials']['material']['shader_source_path'], 'Shaders/Synthetic.shadergraph')
        result = self.import_prefab("""--- !u!23 &1
MeshRenderer:
  m_GameObject: {fileID: 2}
--- !u!4 &3
Transform:
  m_GameObject: {fileID: 2}
  m_LocalPosition: {x: 1, y: 2, z: 3}
  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}
  m_LocalScale: {x: 1, y: 1, z: 1}
  m_Father: {fileID: 0}
--- !u!1 &4
GameObject:
  m_Name: Title
--- !u!224 &5
RectTransform:
  m_GameObject: {fileID: 4}
  m_LocalPosition: {x: 4, y: 5, z: 6}
  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}
  m_LocalScale: {x: 1, y: 1, z: 1}
  m_SizeDelta: {x: 7, y: 8}
  m_Father: {fileID: 3}
--- !u!114 &6
MonoBehaviour:
  m_GameObject: {fileID: 4}
  m_fontColor: {r: 0.2, g: 0.4, b: 0.6, a: 0.8}
""")
        self.assertEqual(len(result['title']['transform_chain']), 2)
        self.assertEqual(result['title']['transform_chain'][1]['m_LocalPosition']['z'], 6)
        self.assertEqual(result['title']['color']['a'], 0.8)
        self.assertEqual(result['title']['rect_size']['x'], 7)


if __name__ == '__main__':
    unittest.main()
