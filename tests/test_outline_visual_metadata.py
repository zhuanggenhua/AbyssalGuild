import json
import tempfile
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from outline_visual_metadata import outline_metadata

class OutlineMetadataTests(unittest.TestCase):
    def test_reference_and_defaults(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            (source / 'Shaders').mkdir()
            props = {'_OutlineSize': 0.2, '_OutlineColor': {'r': .1, 'g': .2, 'b': .3, 'a': .4}, '_MinAlpha': .3, '_RotationSpeed': 7}
            (source / 'Shaders/CardOutline.shadergraph').write_text('\n'.join(json.dumps({'m_Type': 'TestShaderProperty', 'm_DefaultReferenceName': key, 'm_Value': value}) for key, value in props.items()))
            manager = {'cardSettings': {'guid': 'settings', 'fileID': 4}}
            reference = {'guid': 'graph', 'fileID': -12}
            read = lambda guid: [{'object_type': 'MonoBehaviour', 'file_id': 4, 'fields': {'outlineMaterial': reference}}] if guid == 'settings' else []
            index = {'graph': {'source_path': 'Shaders/CardOutline.shadergraph'}}
            result = outline_metadata(manager, read, index, source)
            self.assertEqual(result['properties'], props)
            self.assertEqual(result['reference'], reference)
            self.assertEqual(outline_metadata({}, read, index, source), {})
            reference['fileID'] = 12
            self.assertEqual(outline_metadata(manager, read, index, source), {})

if __name__ == '__main__': unittest.main()
