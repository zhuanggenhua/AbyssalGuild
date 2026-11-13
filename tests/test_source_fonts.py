from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from import_source_fonts import build, blob_sha
from source_font_metadata import font_reference

class SourceFontTests(unittest.TestCase):
    def fixture(self, root):
        asset = '''--- !u!114 &11400000
MonoBehaviour:
  m_SourceFontFileGUID: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  m_FaceInfo: {m_FamilyName: Synthetic, m_StyleName: Regular, m_PointSize: 20}
  m_GlyphTable: [{m_Index: 1, m_Metrics: {m_HorizontalAdvance: 10}}]
  m_CharacterTable: [{m_Unicode: 65, m_GlyphIndex: 1}]
'''
        files = {'font.asset': asset.encode(), 'font.asset.meta': b'guid: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n',
                 'font.ttf': b'synthetic-font-input-not-an-original-font', 'font.ttf.meta': b'guid: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n', 'LICENSE': b'synthetic license fixture'}
        for name, data in files.items(): (root / name).write_bytes(data)
        return {'source_commit': '1' * 40, 'repository': 'synthetic/test',
                'files': {name: {'git_blob_sha1': blob_sha(root / name), 'repository_path': 'Assets/' + name} for name in files},
                'fonts': [{'asset': 'font.asset', 'asset_meta': 'font.asset.meta', 'ttf': 'font.ttf', 'ttf_meta': 'font.ttf.meta', 'license': 'LICENSE'}]}

    def test_guid_chain_metrics_hash_provenance_and_determinism(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'source'; source.mkdir(); lock = self.fixture(source)
            output = Path(tmp) / 'out'; result = build(source, lock, output)
            record = result['fonts']['a' * 32]
            self.assertEqual(record['ttf_guid'], 'b' * 32)
            self.assertEqual(record['family'], 'Synthetic')
            self.assertEqual((output / record['font_path']).read_bytes(), (source / 'font.ttf').read_bytes())
            self.assertEqual(result['inputs']['font.ttf']['repository_path'], 'Assets/font.ttf')
            first = (output / 'manifest.json').read_bytes()
            build(source, lock, output)
            self.assertEqual(first, (output / 'manifest.json').read_bytes())

    def test_missing_is_explicit_and_never_fabricates_binding(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'source'; source.mkdir(); lock = self.fixture(source)
            (source / 'font.ttf').unlink()
            result = build(source, lock, Path(tmp) / 'out')
            self.assertEqual(result['fonts'], {})
            self.assertEqual(result['missing'], ['font.ttf'])

    def test_tampering_fails_before_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'source'; source.mkdir(); lock = self.fixture(source)
            (source / 'font.ttf').write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'blob mismatch'): build(source, lock, Path(tmp) / 'out')
            self.assertFalse((Path(tmp) / 'out').exists())

    def test_mismatched_ttf_guid_rejected_even_with_updated_hash(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'source'; source.mkdir(); lock = self.fixture(source)
            (source / 'font.ttf.meta').write_text('guid: cccccccccccccccccccccccccccccccc\n')
            lock['files']['font.ttf.meta']['git_blob_sha1'] = blob_sha(source / 'font.ttf.meta')
            with self.assertRaisesRegex(ValueError, 'GUID does not match'): build(source, lock, Path(tmp) / 'out')

    def test_path_escape_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError): build(Path(tmp), {'source_commit': '1' * 40, 'files': {'../escape': {}}}, Path(tmp) / 'out')

    def test_component_guid_and_missing_are_explicit(self):
        self.assertEqual(font_reference({'m_fontAsset': {'guid': 'source', 'fileID': 11400000}})['font_guid'], 'source')
        self.assertEqual(font_reference({})['font_guid'], '')

    def test_source_revision_must_match_catalog(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'source'; source.mkdir(); lock = self.fixture(source)
            with self.assertRaisesRegex(ValueError, 'differs from StackCraft catalog'):
                build(source, lock, Path(tmp) / 'out', '2' * 40)

    def test_default_tmp_font_is_not_inferred_from_static_font(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'source'; source.mkdir(); lock = self.fixture(source)
            (source / 'settings.asset').write_text("--- !u!114 &1\nMonoBehaviour:\n  m_defaultFontAsset: {guid: cccccccccccccccccccccccccccccccc, fileID: 11400000}\n")
            lock['tmp_settings'] = 'settings.asset'
            lock['files']['settings.asset'] = {'git_blob_sha1': blob_sha(source / 'settings.asset'), 'repository_path': 'Assets/TMP Settings.asset'}
            result = build(source, lock, Path(tmp) / 'out')
            self.assertEqual(result['tmp_default_font_guid'], 'c' * 32)
            self.assertNotIn('c' * 32, result['fonts'])
