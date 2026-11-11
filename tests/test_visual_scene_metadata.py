import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from visual_scene_metadata import apply_overrides, camera_records

class SceneMetadataTests(unittest.TestCase):
    def fixture(self):
        return [
            {'file_id': '1', 'object_type': 'Transform', 'fields': {'m_GameObject': {'fileID': 'root'}, 'm_LocalPosition': {'x': 0, 'y': 0, 'z': 0}, 'm_LocalRotation': {'x': 0, 'y': 0, 'z': 0, 'w': 1}, 'm_LocalScale': {'x': 1, 'y': 1, 'z': 1}, 'm_Father': {'fileID': '0'}}},
            {'file_id': '2', 'object_type': 'Transform', 'fields': {'m_GameObject': {'fileID': 'child'}, 'm_LocalPosition': {'x': 0, 'y': 0, 'z': 0}, 'm_LocalRotation': {'x': 0, 'y': 0, 'z': 0, 'w': 1}, 'm_LocalScale': {'x': 1, 'y': 1, 'z': 1}, 'm_Father': {'fileID': '1'}}},
            {'file_id': '3', 'object_type': 'Camera', 'fields': {'m_GameObject': {'fileID': 'child'}, 'orthographic': 0, 'field of view': 30, 'near clip plane': 2, 'far clip plane': 40}}]
    def test_parent_override_resolves_without_mutation(self):
        original = self.fixture()
        docs = apply_overrides(original, [{'target': {'fileID': '1'}, 'propertyPath': 'm_LocalPosition.y', 'value': 10}, {'target': {'fileID': '3'}, 'propertyPath': 'field of view', 'value': 35}])
        result = camera_records(docs)[0]
        self.assertTrue(result['resolved_pose'])
        self.assertEqual(result['transform_chain'][0]['m_LocalPosition']['y'], 10)
        self.assertEqual(result['field_of_view'], 35)
        self.assertEqual(original[0]['fields']['m_LocalPosition']['y'], 0)
    def test_unknown_parent_or_cycle_not_resolved(self):
        self.assertFalse(camera_records(self.fixture(), external_parent=True)[0]['resolved_pose'])
        docs = self.fixture(); docs[0]['fields']['m_Father']['fileID'] = '2'
        self.assertFalse(camera_records(docs)[0]['resolved_pose'])
if __name__ == '__main__': unittest.main()
