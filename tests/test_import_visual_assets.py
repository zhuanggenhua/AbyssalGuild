import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from import_visual_assets import build

class VisualImportTests(unittest.TestCase):
    def test_copy_hash_missing_and_determinism(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / 'source'; source.mkdir()
            (source / 'art.png').write_bytes(b'synthetic fixture, not licensed artwork')
            catalog = {'guid_index': {'art': {'source_path': 'art.png'}, 'gone': {'source_path': 'missing.wav'}}, 'scenes': []}
            output = Path(temp) / 'output'
            result = build(source, catalog, output)
            first = (output / 'manifest.json').read_bytes()
            self.assertEqual((output / 'art.png').read_bytes(), (source / 'art.png').read_bytes())
            self.assertEqual(result['missing'], [{'guid': 'gone', 'source_path': 'missing.wav'}])
            self.assertEqual(len(result['assets']['art']['sha256']), 64)
            build(source, catalog, output)
            self.assertEqual(first, (output / 'manifest.json').read_bytes())
    def test_scene_prefab_material_chain(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / 'source'; source.mkdir()
            (source / 'body.mat').write_text("--- !u!21 &21\nMaterial:\n  m_Name: Synthetic\n  m_SavedProperties:\n    m_Colors:\n    - _Color: {r: 0.2, g: 0.3, b: 0.4, a: 1}\n")
            (source / 'card.prefab').write_text("--- !u!65 &65\nBoxCollider:\n  m_GameObject: {fileID: 1}\n  m_Size: {x: 0.8, y: 0, z: 1}\n--- !u!23 &23\nMeshRenderer:\n  m_GameObject: {fileID: 1}\n  m_Materials:\n  - {guid: mat, fileID: 21}\n")
            catalog = {'guid_index': {'mat': {'source_path': 'body.mat'}, 'prefab': {'source_path': 'card.prefab'}}, 'scenes': [{'name': 'Main', 'documents': [{'object_type': 'MonoBehaviour', 'fields': {'cardPrefabs': [{'category': 1, 'prefab': {'guid': 'prefab'}}]}}]}]}
            result = build(source, catalog, Path(temp) / 'out')
            self.assertEqual(result['scenes']['Main']['categories']['1'], 'prefab')
            self.assertEqual(result['prefabs']['prefab']['size']['x'], 0.8)
            self.assertEqual(result['prefabs']['prefab']['materials'][0]['guid'], 'mat')
            self.assertEqual(result['materials']['mat']['colors']['_Color']['g'], 0.3)
    def test_escape_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / 'source'; source.mkdir()
            with self.assertRaises(ValueError):
                build(source, {'guid_index': {'bad': {'source_path': '../secret.png'}}}, Path(temp) / 'out')
    def test_source_output_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(ValueError):
                build(Path(temp), {'guid_index': {}}, Path(temp) / 'out')
if __name__ == '__main__': unittest.main()
