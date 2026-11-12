import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from world_visual_metadata import world_metadata

class WorldMetadataTests(unittest.TestCase):
    def test_scene_renderer_and_environment_preserved(self):
        docs = [
            {'object_type': 'RenderSettings', 'fields': {'m_AmbientMode': 3, 'm_Fog': 0}},
            {'object_type': 'MeshRenderer', 'file_id': '7', 'fields': {'m_GameObject': {'fileID': '1'}, 'm_Enabled': 1, 'm_Materials': [{'guid': 'synthetic'}]}},
            {'object_type': 'MeshFilter', 'fields': {'m_GameObject': {'fileID': '1'}, 'm_Mesh': {'fileID': '10209'}}},
            {'object_type': 'Transform', 'file_id': '2', 'fields': {'m_GameObject': {'fileID': '1'}, 'm_Father': {'fileID': '0'}, 'm_LocalPosition': {'x': 0, 'y': -3, 'z': 0}, 'm_LocalRotation': {'x': 0, 'y': 0, 'z': 0, 'w': 1}, 'm_LocalScale': {'x': 2, 'y': 1, 'z': 2}}},
        ]
        actual = world_metadata(docs)
        self.assertEqual(actual['render_settings'], {'m_AmbientMode': 3, 'm_Fog': 0})
        mesh = actual['scene_meshes'][0]
        self.assertEqual(mesh['file_id'], '7')
        self.assertEqual(mesh['mesh']['fileID'], '10209')
        self.assertEqual(mesh['transform_chain'][0]['m_LocalPosition']['y'], -3)
        mesh['materials'][0]['guid'] = 'changed'
        self.assertEqual(docs[1]['fields']['m_Materials'][0]['guid'], 'synthetic')

    def test_empty_input_has_no_fabricated_world(self):
        self.assertEqual(world_metadata([]), {'render_settings': {}, 'scene_meshes': []})
