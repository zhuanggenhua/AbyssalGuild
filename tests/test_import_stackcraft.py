"""Synthetic fixtures only: no proprietary source needed for the public test suite."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from import_stackcraft import build, json_bytes, parse_unity, references
from verify_source import verify

SCRIPT_GUID = 'a' * 32
CARD_GUID = 'b' * 32
HEADER = '%YAML 1.1\n%TAG !u! tag:unity3d.com,2011:\n--- !u!114 &11400000\nMonoBehaviour:\n'

class ImportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / 'source'
        self.out = Path(self.temp.name) / 'output'
        self.root.mkdir()
        for group in ('Cards', 'Packs', 'Recipes', 'Quests', 'Encounters'):
            (self.root / 'Resources' / group).mkdir(parents=True)
        (self.root / 'Settings').mkdir()
        (self.root / 'Scripts').mkdir()
        (self.root / 'Scenes').mkdir()
        self.write('Scripts/CardDefinition.cs', 'public enum CardCategory { None, Resource = 4, Character }\n', SCRIPT_GUID)
        self.card = self.write('Resources/Cards/Card_Test.asset', HEADER +
            '  m_Name: Card_Test\n'
            f'  m_Script: {{fileID: 11500000, guid: {SCRIPT_GUID}, type: 3}}\n'
            '  id: test-card\n  displayName: On\n  sellPrice: 5\n'
            '  loot: []\n  packed: 0000000001000000\n'
            '  artTexture: {fileID: 0}\n  nested: {x: -0.18, y: 3}\n', CARD_GUID)

    def tearDown(self):
        self.temp.cleanup()

    def write(self, path, content, guid):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        target.with_name(target.name + '.meta').write_text('fileFormatVersion: 2\nguid: ' + guid + '\n')
        return target

    def generate(self):
        data, manifest = build(self.root)
        self.out.mkdir(exist_ok=True)
        (self.out / 'stackcraft.json').write_bytes(json_bytes(data))
        (self.out / 'manifest.json').write_bytes(json_bytes(manifest))
        return data, manifest

    def test_preserves_serialized_types_and_fields(self):
        data, _ = self.generate()
        fields = data['cards'][0]['fields']
        self.assertEqual(fields['displayName'], 'On')
        self.assertEqual(fields['packed'], '0000000001000000')
        self.assertEqual(fields['sellPrice'], 5)
        self.assertEqual(fields['nested']['x'], -0.18)
        self.assertEqual(fields['artTexture']['fileID'], '0')
        self.assertEqual(data['cards'][0]['script_class'], 'CardDefinition')

    def test_sparse_visual_import_is_explicit_and_reported(self):
        image = self.write('Sprites/Unavailable.png', 'fake fixture image', 'd' * 32)
        image.unlink()
        with self.assertRaisesRegex(ValueError, 'Orphan metadata'):
            build(self.root)
        data, manifest = build(self.root, allow_missing_visual_assets=True)
        self.assertEqual(manifest['missing_visual_assets'], ['Sprites/Unavailable.png'])
        self.assertEqual(data['provenance']['import_mode'], 'logic_only_sparse_assets')
        self.assertIn('d' * 32, data['guid_index'])
        self.out.mkdir()
        (self.out / 'stackcraft.json').write_bytes(json_bytes(data))
        (self.out / 'manifest.json').write_bytes(json_bytes(manifest))
        self.assertEqual(verify(self.out, self.root)['missing_visual_assets'], ['Sprites/Unavailable.png'])
        self.assertFalse(image.exists())

    def test_sparse_import_still_rejects_missing_gameplay_and_scripts(self):
        self.card.unlink()
        with self.assertRaisesRegex(ValueError, 'Orphan metadata'):
            build(self.root, allow_missing_visual_assets=True)

    def test_sparse_manifest_tampering_is_rejected(self):
        data, manifest = self.generate()
        manifest['import_mode'] = 'logic_only_sparse_assets'
        (self.out / 'manifest.json').write_bytes(json_bytes(manifest))
        with self.assertRaisesRegex(ValueError, 'Import mode mismatch'):
            verify(self.out)

    def test_enums_with_explicit_values(self):
        data, _ = self.generate()
        self.assertEqual(data['enums']['CardCategory'], {'None': 0, 'Resource': 4, 'Character': 5})

    def test_repeated_import_is_byte_identical(self):
        one, manifest_one = build(self.root)
        two, manifest_two = build(self.root)
        self.assertEqual(json_bytes(one), json_bytes(two))
        self.assertEqual(json_bytes(manifest_one), json_bytes(manifest_two))

    def test_standalone_and_source_verification(self):
        self.generate()
        self.assertEqual(verify(self.out)['status'], 'verified')
        self.assertTrue(verify(self.out, self.root)['source_reimported'])

    def test_corrupt_data_rejected(self):
        self.generate()
        path = self.out / 'stackcraft.json'
        path.write_text(path.read_text().replace('test-card', 'changed'))
        with self.assertRaisesRegex(ValueError, 'SHA-256'):
            verify(self.out)

    def test_changed_source_rejected(self):
        self.generate()
        self.card.write_text(self.card.read_text().replace('sellPrice: 5', 'sellPrice: 6'))
        with self.assertRaisesRegex(ValueError, 'Changed source'):
            verify(self.out, self.root)

    def test_count_mismatch_rejected_even_with_updated_hash(self):
        data, manifest = self.generate()
        data['counts']['cards'] = 9
        payload = json_bytes(data)
        manifest['stackcraft_json_sha256'] = hashlib.sha256(payload).hexdigest()
        (self.out / 'stackcraft.json').write_bytes(payload)
        (self.out / 'manifest.json').write_bytes(json_bytes(manifest))
        with self.assertRaisesRegex(ValueError, 'Count mismatch'):
            verify(self.out)

    def test_dangling_gameplay_reference_rejected(self):
        with self.card.open('a') as stream:
            stream.write('  missing: {fileID: 11400000, guid: ' + 'c' * 32 + ', type: 2}\n')
        with self.assertRaisesRegex(ValueError, 'Unresolved gameplay'):
            build(self.root)

    def test_duplicate_guid_rejected(self):
        self.write('Resources/Cards/Copy.asset', self.card.read_text(), CARD_GUID)
        with self.assertRaisesRegex(ValueError, 'Duplicate GUID'):
            build(self.root)

    def test_duplicate_yaml_field_rejected(self):
        with self.card.open('a') as stream:
            stream.write('  sellPrice: 6\n')
        with self.assertRaisesRegex(ValueError, 'Duplicate YAML key'):
            parse_unity(self.card)

    def test_multi_document_and_large_ids(self):
        self.card.write_text(HEADER + '  reference: {fileID: 9139900829123107160}\n'
                             '--- !u!4 &9139900829123107160 stripped\nTransform:\n  m_LocalPosition: {x: 1, y: 2, z: 3}\n')
        docs = parse_unity(self.card)
        self.assertEqual(len(docs), 2)
        self.assertEqual(docs[0]['fields']['reference']['fileID'], '9139900829123107160')
        self.assertEqual(docs[1]['file_id'], '9139900829123107160')

    def test_external_scene_reference_explicitly_reported(self):
        self.write('Scenes/Main.unity', HEADER + '  m_Script: {fileID: 11500000, guid: ' + 'd' * 32 + ', type: 3}\n', 'e' * 32)
        data, manifest = self.generate()
        self.assertEqual(len(manifest['references']['unresolved_external']), 1)
        self.assertEqual(verify(self.out)['unresolved_external'], 1)

    def test_null_reference_is_not_dangling(self):
        self.assertEqual(list(references({'null': {'fileID': '0', 'guid': 'f' * 32}})), [])

    def test_prefab_dependencies_are_recursive(self):
        self.write('Scenes/Main.unity', HEADER + '  prefab: {fileID: 1000, guid: ' + 'c' * 32 + ', type: 3}\n', 'e' * 32)
        self.write('Prefabs/Outer.prefab', HEADER + '  nested: {fileID: 1000, guid: ' + 'd' * 32 + ', type: 3}\n', 'c' * 32)
        self.write('Prefabs/Inner.prefab', HEADER + '  loop: {fileID: 1000, guid: ' + 'c' * 32 + ', type: 3}\n', 'd' * 32)
        data, _ = self.generate()
        self.assertEqual(data['counts']['referenced_prefabs'], 2)
        self.assertEqual(verify(self.out)['unresolved_external'], 0)

if __name__ == '__main__':
    unittest.main()
