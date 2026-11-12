import sys
from pathlib import Path
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from import_visual_assets import build

class TextureAlphaMetadataTests(unittest.TestCase):
    def test_preserves_alpha_usage_without_modifying_original_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / 'source'; source.mkdir()
            pixels = b'synthetic fixture, not a source artwork'
            (source / 'gray.png').write_bytes(pixels)
            (source / 'gray.png.meta').write_text('TextureImporter:\n  alphaUsage: 2\n  alphaIsTransparency: 0\n  mipmaps: {enableMipMap: 1, sRGBTexture: 1}\n')
            result = build(source, {'guid_index': {'gray': {'source_path': 'gray.png'}}, 'scenes': []}, Path(temp) / 'out')
            self.assertEqual(result['assets']['gray']['texture_importer']['alpha_usage'], 2)
            self.assertEqual(result['assets']['gray']['conversion'], 'byte-identical copy')
            self.assertEqual((Path(temp) / 'out/gray.png').read_bytes(), pixels)
