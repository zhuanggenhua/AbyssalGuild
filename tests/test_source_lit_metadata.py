import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from source_lit_metadata import SG, URP, source_lit_metadata


def fixture():
    """Minimal independently authored objects, not serialized original assets."""
    graph = {'m_Type': SG + 'GraphData', 'm_ObjectId': 'graph', 'm_SGVersion': 3,
             'm_Keywords': [], 'm_Nodes': [], 'm_Edges': [],
             'm_ActiveTargets': [{'m_Id': 'target'}],
             'm_VertexContext': {'m_Blocks': []}, 'm_FragmentContext': {'m_Blocks': []}}
    target = {'m_Type': URP + 'UniversalTarget', 'm_ObjectId': 'target', 'm_SGVersion': 1,
              'm_SurfaceType': 0, 'm_AllowMaterialOverride': False, 'm_AlphaClip': False,
              'm_RenderFace': 2, 'm_ActiveSubTarget': {'m_Id': 'lit'}}
    lit = {'m_Type': URP + 'UniversalLitSubTarget', 'm_ObjectId': 'lit', 'm_SGVersion': 2,
           'm_WorkflowMode': 1, 'm_ClearCoat': False, 'm_NormalDropOffSpace': 0}
    objects = [graph, target, lit]
    for name, kind, space, stage in (
        ('Position', 'PositionMaterialSlot', 0, 1), ('Normal', 'NormalMaterialSlot', 0, 1),
        ('Tangent', 'TangentMaterialSlot', 0, 1), ('NormalTS', 'NormalMaterialSlot', 3, 2),
        ('Metallic', 'Vector1MaterialSlot', None, 2), ('Smoothness', 'Vector1MaterialSlot', None, 2),
        ('BaseColor', 'ColorRGBMaterialSlot', None, 2), ('Emission', 'ColorRGBMaterialSlot', None, 2),
        ('Occlusion', 'Vector1MaterialSlot', None, 2),
    ):
        prefix = 'VertexDescription.' if stage == 1 else 'SurfaceDescription.'
        block = {'m_Type': SG + 'BlockNode', 'm_ObjectId': name, 'm_SGVersion': 0,
                 'm_SerializedDescriptor': prefix + name, 'm_Slots': [{'m_Id': name + 'slot'}]}
        value = {'x': 0, 'y': 0, 'z': 0} if space is not None else 0
        slot = {'m_Type': SG + kind, 'm_ObjectId': name + 'slot', 'm_SGVersion': 0,
                'm_StageCapability': stage, 'm_SlotType': 0, 'm_Id': 0,
                'm_Value': value, 'm_DefaultValue': copy.deepcopy(value)}
        if space is not None:
            slot['m_Space'] = space
        graph['m_Nodes'].append({'m_Id': name})
        graph['m_VertexContext' if stage == 1 else 'm_FragmentContext']['m_Blocks'].append({'m_Id': name})
        objects.extend((block, slot))
    return objects


def encode(objects):
    return '\n\n'.join(json.dumps(o) for o in objects)


def indexed(objects):
    return {o['m_ObjectId']: o for o in objects}


class SourceLitMetadataTest(unittest.TestCase):
    def test_importer_records_contract_hash_and_keywords(self):
        from import_visual_assets import build
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root / 'source'; source.mkdir()
            (source / 'Shaders').mkdir()
            graph_text = '\ufeff' + encode(fixture())
            (source / 'Shaders/SimpleLit.shadergraph').write_bytes(graph_text.encode())
            (source / 'body.mat').write_text("--- !u!21 &21\nMaterial:\n  m_Name: Synthetic\n  m_Shader: {guid: graph}\n  m_ValidKeywords: [SYNTHETIC_A]\n  m_InvalidKeywords: [SYNTHETIC_B]\n  m_ShaderKeywords: SYNTHETIC_C\n  m_SavedProperties: {}\n")
            catalog = {'guid_index': {'mat': {'source_path': 'body.mat'},
                       'graph': {'source_path': 'Shaders/SimpleLit.shadergraph'}}, 'scenes': []}
            result = build(source, catalog, root / 'output')
            material = result['materials']['mat']
            self.assertEqual(material['source_lit']['schema_version'], 2)
            self.assertEqual(material['source_lit']['graph_sha256'], result['inputs']['Shaders/SimpleLit.shadergraph'])
            self.assertEqual(material['keywords'], ['SYNTHETIC_A', 'SYNTHETIC_B', 'SYNTHETIC_C'])

    def test_contract(self):
        text = encode(fixture())
        result = source_lit_metadata(text)
        self.assertEqual(result['schema_version'], 2)
        self.assertEqual(result['geometry'], 'unmodified_object_vertices_tangent_normal')
        self.assertEqual(result['graph_sha256'], hashlib.sha256(text.encode()).hexdigest())

    def test_bom_hash_matches_bytes(self):
        text = '\ufeff' + encode(fixture())
        self.assertEqual(source_lit_metadata(text)['graph_sha256'], hashlib.sha256(text.encode()).hexdigest())

    def test_malformed_and_duplicate_objects(self):
        for text in ('', '{}', '[]', 'null', '{', '{"m_ObjectId":"a","m_ObjectId":"b"}', encode(fixture() + [fixture()[0]])):
            with self.subTest(text=text[:20]): self.assertEqual(source_lit_metadata(text), {})

    def test_target_guards(self):
        for identity, key, value in (
            ('graph', 'm_SGVersion', 99), ('graph', 'm_Keywords', [{'m_Id': 'keyword'}]),
            ('target', 'm_SurfaceType', 1), ('target', 'm_AllowMaterialOverride', True),
            ('target', 'm_AlphaClip', True), ('target', 'm_RenderFace', 0),
            ('target', 'm_SGVersion', 99), ('lit', 'm_SGVersion', 99),
            ('lit', 'm_WorkflowMode', 0), ('lit', 'm_ClearCoat', True),
            ('lit', 'm_NormalDropOffSpace', 1), ('lit', 'm_Type', URP + 'UniversalUnlitSubTarget'),
        ):
            with self.subTest(identity=identity,key=key):
                objects = fixture(); indexed(objects)[identity][key] = value
                self.assertEqual(source_lit_metadata(encode(objects)), {})

    def test_inactive_target_cannot_authorize(self):
        objects = fixture(); objects[0]['m_ActiveTargets'] = []
        self.assertEqual(source_lit_metadata(encode(objects)), {})

    def test_two_active_urp_targets_rejected(self):
        objects = fixture(); objects[0]['m_ActiveTargets'] *= 2
        self.assertEqual(source_lit_metadata(encode(objects)), {})

    def test_connected_fixed_blocks(self):
        for name in ('Position', 'Normal', 'Tangent', 'NormalTS', 'Metallic', 'Smoothness'):
            objects = fixture()
            objects[0]['m_Edges'].append({'m_InputSlot': {'m_Node': {'m_Id': name}},
                                         'm_OutputSlot': {'m_Node': {'m_Id': 'BaseColor'}}})
            with self.subTest(name=name): self.assertEqual(source_lit_metadata(encode(objects)), {})

    def test_geometry_slot_schema(self):
        for name in ('Position', 'Normal', 'Tangent', 'NormalTS'):
            for key, value in (('m_Space', 99), ('m_StageCapability', 99), ('m_SGVersion', 1),
                               ('m_Type', SG + 'Vector3MaterialSlot'), ('m_Id', 1), ('m_SlotType', 1),
                               ('m_Value', {'x': 1, 'y': 0, 'z': 0}), ('m_DefaultValue', {})):
                objects = fixture(); indexed(objects)[name + 'slot'][key] = value
                with self.subTest(name=name,key=key): self.assertEqual(source_lit_metadata(encode(objects)), {})

    def test_numeric_fixed_values(self):
        for name in ('Metallic', 'Smoothness'):
            for value in (0.1, None, '0', False):
                objects = fixture(); indexed(objects)[name+'slot']['m_Value'] = value
                with self.subTest(name=name,value=value): self.assertEqual(source_lit_metadata(encode(objects)), {})

    def test_unknown_and_duplicate_active_blocks(self):
        for name in ('NormalTS', 'Position'):
            objects = fixture(); indexed(objects)[name]['m_SerializedDescriptor'] += 'Unknown'
            self.assertEqual(source_lit_metadata(encode(objects)), {})
        objects = fixture(); objects[0]['m_FragmentContext']['m_Blocks'].append({'m_Id': 'NormalTS'})
        self.assertEqual(source_lit_metadata(encode(objects)), {})

    def test_missing_blocks_and_references(self):
        for key in ('m_VertexContext', 'm_FragmentContext'):
            objects = fixture(); objects[0][key]['m_Blocks'].pop()
            self.assertEqual(source_lit_metadata(encode(objects)), {})
        objects = fixture(); objects.pop()
        self.assertEqual(source_lit_metadata(encode(objects)), {})

    def test_inactive_blocks_do_not_override_active_value(self):
        objects = fixture(); node = copy.deepcopy(indexed(objects)['Metallic'])
        node['m_ObjectId'] = 'unused'; objects.append(node)
        self.assertTrue(source_lit_metadata(encode(objects)))
        indexed(objects)['Metallicslot']['m_Value'] = 1
        self.assertEqual(source_lit_metadata(encode(objects)), {})

    def test_fragment_color_connection_allowed(self):
        objects = fixture()
        objects[0]['m_Edges'].append({'m_InputSlot': {'m_Node': {'m_Id': 'BaseColor'}}})
        self.assertTrue(source_lit_metadata(encode(objects)))

if __name__ == '__main__':
    unittest.main()
