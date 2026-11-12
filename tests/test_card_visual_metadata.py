"""Independent synthetic fixtures for card annotation references and anchors."""
import copy
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from card_visual_metadata import annotations


def doc(kind, key, **fields):
    return {'object_type': kind, 'file_id': str(key), 'fields': fields}


def transform(owner, parent='0', position=None):
    return {'m_GameObject': {'fileID': str(owner)}, 'm_Father': {'fileID': str(parent)},
            'm_LocalPosition': position or {'x': 0, 'y': 0, 'z': 0},
            'm_LocalRotation': {'x': 0, 'y': 0, 'z': 0, 'w': 1},
            'm_LocalScale': {'x': 1, 'y': 1, 'z': 1}}


class CardVisualMetadataTests(unittest.TestCase):
    def fixture(self):
        rect = transform(3, 2, {'x': 0, 'y': 0, 'z': -7})
        rect.update({'m_AnchoredPosition': {'x': -4, 'y': 0.02}, 'm_SizeDelta': {'x': 2, 'y': 3}})
        return [doc('Transform', 2, **transform(1)),
                doc('MonoBehaviour', 10, m_GameObject={'fileID': '1'}, priceText={'fileID': '5'},
                    healthText={'fileID': '0'}, nutritionText={'fileID': '0'}, equipmentPanel={'fileID': '8'}),
                doc('GameObject', 3, m_Name='Arbitrary text name'),
                doc('RectTransform', 4, **rect),
                doc('MonoBehaviour', 5, m_GameObject={'fileID': '3'}, m_fontColor={'r': 1, 'g': 0, 'b': 0, 'a': 1}, m_fontSize=2),
                doc('Transform', 7, **transform(6, 2, {'x': 1, 'y': 2, 'z': 3})),
                doc('MonoBehaviour', 8, m_GameObject={'fileID': '6'}),
                doc('MeshFilter', 9, m_GameObject={'fileID': '6'}, m_Mesh={'guid': 'panel_mesh'}),
                doc('MeshRenderer', 11, m_GameObject={'fileID': '6'}, m_Materials=[{'guid': 'panel_material'}]),
                doc('BoxCollider', 12, m_GameObject={'fileID': '6'}, m_Size={'x': 9, 'y': 0, 'z': 3}, m_Center={'x': 0, 'y': 0, 'z': 0})]

    def test_explicit_roles_and_anchored_position(self):
        docs = self.fixture()
        original = copy.deepcopy(docs)
        result = annotations(docs, {'fileID': '1'})
        self.assertEqual(set(result['labels']), {'price'})
        price = result['labels']['price']
        self.assertEqual(price['transform_chain'][-1]['m_LocalPosition'], {'x': -4, 'y': 0.02, 'z': -7})
        self.assertEqual(price['rect_size'], {'x': 2, 'y': 3})
        self.assertEqual(price['color']['g'], 0)
        self.assertEqual(docs, original)

    def test_panel_owner_and_transform_chain(self):
        result = annotations(self.fixture(), {'fileID': '1'})['equipment_panel']
        self.assertEqual(result['mesh']['guid'], 'panel_mesh')
        self.assertEqual(result['materials'][0]['guid'], 'panel_material')
        self.assertEqual(len(result['transform_chain']), 2)
        self.assertEqual(result['size']['x'], 9)

    def test_title_fit_settings_are_preserved_without_mutation(self):
        docs = self.fixture()
        docs[1]['fields']['titleText'] = docs[1]['fields'].pop('priceText')
        docs[4]['fields'].update(m_enableAutoSizing=1, m_enableWordWrapping=0,
                                 m_fontSizeMin=3, m_fontSizeMax=9, m_overflowMode=0,
                                 m_margin={'x': .1, 'y': .2, 'z': .3, 'w': .4},
                                 m_HorizontalAlignment=2, m_VerticalAlignment=512)
        original = copy.deepcopy(docs)
        title = annotations(docs, {'fileID': '1'})['labels']['title']
        self.assertEqual((title['auto_size'], title['word_wrap'], title['overflow_mode']), (1, 0, 0))
        self.assertEqual((title['font_size_min'], title['font_size_max']), (3, 9))
        self.assertEqual(title['margin'], {'x': .1, 'y': .2, 'z': .3, 'w': .4})
        self.assertEqual(title['horizontal_alignment'], 2)
        title['margin']['x'] = 99
        self.assertEqual(docs, original)

    def test_older_text_settings_remain_explicitly_unknown(self):
        price = annotations(self.fixture(), {'fileID': '1'})['labels']['price']
        self.assertIsNone(price['auto_size'])
        self.assertIsNone(price['word_wrap'])
        self.assertEqual(price['margin'], {})

    def test_unreferenced_same_name_is_not_a_display(self):
        docs = self.fixture()
        docs[1]['fields']['priceText'] = {'fileID': '0'}
        docs[2]['fields']['m_Name'] = 'Price'
        self.assertEqual(annotations(docs, {'fileID': '1'})['labels'], {})

    def test_unknown_or_rect_parent_is_not_guessed(self):
        docs = self.fixture()
        docs[3]['fields']['m_Father'] = {'fileID': 'missing'}
        self.assertEqual(annotations(docs, {'fileID': '1'})['labels'], {})
        docs[0]['object_type'] = 'RectTransform'
        self.assertEqual(annotations(docs, {'fileID': '1'})['labels'], {})

    def test_missing_panel_mesh_does_not_borrow_card_mesh(self):
        docs = self.fixture()
        docs[8]['fields']['m_GameObject'] = {'fileID': '1'}
        self.assertEqual(annotations(docs, {'fileID': '1'})['equipment_panel'], {})


if __name__ == '__main__':
    unittest.main()
