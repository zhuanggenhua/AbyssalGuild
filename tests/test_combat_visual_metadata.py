"""Synthetic combat component ownership, sprite import and rectangle tests."""
import copy
from pathlib import Path
import struct
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from combat_visual_metadata import sprite_metadata, projectile_metadata, hit_ui_metadata, combat_metadata, canvas_reference_ppu
from import_visual_assets import build


def doc(kind, key, **fields):
    return {'object_type': kind, 'file_id': str(key), 'fields': fields}


def pose(owner, parent='0'):
    return {'m_GameObject': {'fileID': str(owner)}, 'm_Father': {'fileID': str(parent)},
            'm_LocalPosition': {'x': 9, 'y': 8, 'z': 0}, 'm_LocalRotation': {'x': 0, 'y': 0, 'z': 0, 'w': 1},
            'm_LocalScale': {'x': 1, 'y': 1, 'z': 1}}


def rect(owner, parent='0', size=(2, 4), pivot=(.5, .5), amin=(.5, .5), amax=(.5, .5), anchored=(0, 0)):
    return dict(pose(owner, parent), **{'m_SizeDelta': dict(zip('xy', size)), 'm_Pivot': dict(zip('xy', pivot)),
                'm_AnchorMin': dict(zip('xy', amin)), 'm_AnchorMax': dict(zip('xy', amax)), 'm_AnchoredPosition': dict(zip('xy', anchored))})


def hit_docs():
    color = {'r': .2, 'g': .4, 'b': .6, 'a': .8}
    return [doc('RectTransform', 10, **rect(1)),
            doc('RectTransform', 20, **rect(2, '10', (.6, .8), (1, 1), (1, 1), (1, 1), (.3, .2))),
            doc('RectTransform', 30, **rect(3, '10', (0, 0), (.5, .5), (0, 0), (1, 1))),
            doc('MonoBehaviour', 40, m_GameObject={'fileID': '1'}, hitImage={'fileID': '41'}, effectivenessImage={'fileID': '42'}, damageLabel={'fileID': '43'},
                missSprite={'guid': 'miss'}, normalSprite={'guid': 'normal'}, criticalSprite={'guid': 'critical'}, advantageSprite={'guid': 'adv'}, disadvantageSprite={'guid': 'disadv'}),
            doc('MonoBehaviour', 41, m_GameObject={'fileID': '1'}, m_Color=color, m_Material={'fileID': '0'}, m_Type=0, m_PreserveAspect=0),
            doc('MonoBehaviour', 42, m_GameObject={'fileID': '2'}, m_Color=color, m_Material={'fileID': '0'}, m_Type=0, m_PreserveAspect=0),
            doc('MonoBehaviour', 43, m_GameObject={'fileID': '3'}, m_fontColor=color, m_fontSize=.3, m_fontAsset={'guid': 'font'})]


class CombatVisualMetadataTests(unittest.TestCase):
    def test_single_sprite_requires_explicit_importer_not_filename(self):
        data = b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>II', 40, 80)
        importer = {'textureType': 8, 'spriteMode': 1, 'alignment': 9, 'spritePixelsToUnits': 20, 'spritePivot': {'x': .2, 'y': .8}, 'textureSettings': {'filterMode': 1}}
        result = sprite_metadata(importer, data)
        self.assertEqual(result['pixel_size'], {'x': 40, 'y': 80})
        self.assertEqual(result['pixels_per_unit'], 20)
        for change in [{'spriteMode': 2}, {'alignment': 1}, {'spritePixelsToUnits': 0}, {'spritePixelsToUnits': float('nan')}, {'spritePivot': {}}]:
            self.assertEqual(sprite_metadata(dict(importer, **change), data), {})
        self.assertEqual(sprite_metadata(importer, b'not a PNG'), {})

    def test_projectile_uses_exact_component_owner(self):
        documents = [doc('MonoBehaviour', 1, m_GameObject={'fileID': '2'}, duration=.7),
                     doc('Transform', 3, **pose(2)), doc('SpriteRenderer', 4, m_GameObject={'fileID': 'other'}, m_Sprite={'guid': 'wrong'}),
                     doc('SpriteRenderer', 5, m_GameObject={'fileID': '2'}, m_Sprite={'guid': 'correct'}, m_DrawMode=0)]
        self.assertEqual(projectile_metadata(documents, {'fileID': '1'})['sprite']['guid'], 'correct')
        self.assertEqual(projectile_metadata(documents, {'fileID': 'missing'}), {})
        documents[0]['fields']['duration'] = float('inf')
        self.assertEqual(projectile_metadata(documents, {'fileID': '1'}), {})

    def test_hit_rect_anchors_pivot_and_stretch(self):
        docs = hit_docs()
        before = copy.deepcopy(docs)
        result = hit_ui_metadata(docs, {'fileID': '40'})
        self.assertEqual(result['roles']['hit']['size'], {'x': 2, 'y': 4})
        self.assertEqual(result['roles']['hit']['pose']['m_LocalPosition'], {'x': 0, 'y': 0, 'z': 0})
        self.assertEqual(result['roles']['effectiveness']['pose']['m_LocalPosition'], {'x': 1.3, 'y': 2.2, 'z': 0})
        self.assertEqual(result['roles']['effectiveness']['pivot'], {'x': 1, 'y': 1})
        self.assertEqual(result['roles']['damage']['size'], {'x': 2, 'y': 4})
        self.assertEqual(result['roles']['damage']['font_size'], .3)
        self.assertEqual(result['sprites']['critical']['guid'], 'critical')
        self.assertEqual(docs, before)

    def test_missing_role_nested_parent_or_invalid_layout_is_not_guessed(self):
        for index, key, value in [(3, 'damageLabel', {'fileID': 'missing'}), (1, 'm_Father', {'fileID': '30'}), (0, 'm_SizeDelta', {'x': -1, 'y': 2}), (2, 'm_LocalScale', {'x': float('nan'), 'y': 1, 'z': 1})]:
            docs = hit_docs()
            docs[index]['fields'][key] = value
            self.assertEqual(hit_ui_metadata(docs, {'fileID': '40'}), {})

    def test_scene_reference_identity_not_prefab_name(self):
        read = lambda guid: hit_docs() if guid == 'renamed' else []
        result = combat_metadata({'hitUIPrefab': {'guid': 'renamed', 'fileID': '40'}}, read)
        self.assertEqual(result['hit_ui']['prefab_guid'], 'renamed')
        self.assertEqual(result['projectiles'], {})
        self.assertNotIn('hit_ui', combat_metadata({'hitUIPrefab': {'guid': 'unresolved'}}, read))

    def test_stretched_rectangle_uses_component_and_its_own_image(self):
        owner = {'fileID': '2'}
        child = rect(2, '10', (0, 0), amin=(0, 0), amax=(1, 1))
        child['m_LocalPosition'] = {'x': 0, 'y': 0, 'z': .025}
        child['m_LocalRotation']['y'] = '-0'
        root = rect(1, pivot=(.3,.7))
        root['m_LocalPosition'] = {'x': 0, 'y': 0, 'z': 0}
        docs = [doc('RectTransform', 10, **root), doc('RectTransform', 11, **child),
                doc('GameObject', 2, m_IsActive=1), doc('CanvasRenderer', 3, m_GameObject=owner),
                doc('MonoBehaviour', 4, m_GameObject=owner, m_Script={'guid':'fe87c0e1cc204ed48ad3b37840f39efc'},
                    m_Enabled=1, m_Material={'fileID':0}, m_RaycastTarget=0, m_FillCenter=1, m_Type=1,
                    m_PreserveAspect=0, m_PixelsPerUnitMultiplier=128, m_Color=dict.fromkeys('rgba',1),
                    m_Sprite={'fileID':21300000,'guid':'source-sprite'}),
                doc('MonoBehaviour', 5, m_GameObject={'fileID':'1'})]
        read = lambda guid: docs if guid == 'source-prefab' else []
        selected = {'combatRectPrefab': {'fileID': '5', 'guid': 'source-prefab'}}
        result = combat_metadata(selected, read)['rectangle']
        self.assertEqual(result['sprite']['guid'], 'source-sprite')
        self.assertEqual(result['sprite_ppu_multiplier'], 128)
        self.assertEqual(result['normal_offset'], .025)
        self.assertEqual(result['pivot'], {'x':.3,'y':.7})
        self.assertTrue(result['fill_center'])
        for key, wrong in [('m_Type',0),('m_Material',{'fileID':6}),('m_RaycastTarget',1),('m_PixelsPerUnitMultiplier',0)]:
            before = docs[4]['fields'][key]
            docs[4]['fields'][key] = wrong
            self.assertNotIn('rectangle',combat_metadata(selected, read))
            docs[4]['fields'][key] = before
        docs[1]['fields']['m_AnchorMax'] = {'x':.5,'y':1}
        self.assertNotIn('rectangle',combat_metadata(selected,read))

    def test_canvas_scaler_resolves_only_world_canvas_owner(self):
        owner = {'fileID': '2'}
        fields = [doc('MonoBehaviour', 1, m_GameObject=owner, m_Script={'guid':'d5480d6e0dbe4a343a6a4a6bfaff57fb'}),
                  doc('Canvas', 3, m_GameObject=owner, m_RenderMode=2,m_Enabled=1),
                  doc('MonoBehaviour', 4, m_GameObject={'fileID':'6'}, m_ReferencePixelsPerUnit=200),
                  doc('MonoBehaviour', 5, m_GameObject=owner, m_Enabled=1, m_ReferencePixelsPerUnit=100,
                      m_Script={'guid':'0cd44c1031e13a943bb63640046fad76'})]
        self.assertEqual(canvas_reference_ppu(fields),100)
        fields[1]['fields']['m_RenderMode'] = 0
        self.assertIsNone(canvas_reference_ppu(fields))

    def test_private_import_records_sprite_metadata_input_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'source'
            source.mkdir()
            (source / 'sprite.png').write_bytes(b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>II', 16, 32))
            (source / 'sprite.png.meta').write_text('TextureImporter:\n  textureType: 8\n  spriteMode: 1\n  alignment: 0\n  spritePixelsToUnits: 8\n  spritePivot: {x: 0.5, y: 0.5}\n')
            result = build(source, {'guid_index': {'sprite': {'source_path': 'sprite.png'}}, 'scenes': []}, Path(directory) / 'out')
            self.assertEqual(result['assets']['sprite']['sprite']['pixel_size']['y'], 32)
            self.assertIn('sprite.png.meta', result['inputs'])


if __name__ == '__main__':
    unittest.main()
