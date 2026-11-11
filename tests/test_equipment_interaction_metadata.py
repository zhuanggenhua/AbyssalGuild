import copy
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from equipment_interaction_metadata import interaction_metadata


class EquipmentInteractionMetadataTests(unittest.TestCase):
    def fixture(self):
        return {'weaponAttachPoint': {'x': -2, 'y': 0.3, 'z': 0.1},
                'armorAttachPoint': {'x': 0.2, 'y': 0.4, 'z': -3},
                'accessoryAttachPoint': {'x': 2.5, 'y': 0.5, 'z': 0.2},
                'animationRadius': 0.2, 'animationSpeed': 0.8}

    def test_explicit_slots_and_animation_values(self):
        fields = self.fixture()
        original = copy.deepcopy(fields)
        result = interaction_metadata(fields)
        self.assertEqual([result['attach_points'][str(s)]['x'] for s in range(3)], [-2, 0.2, 2.5])
        self.assertEqual(result['animation_radius'], 0.2)
        self.assertEqual(result['animation_speed'], 0.8)
        result['attach_points']['0']['x'] = 9
        self.assertEqual(fields, original)

    def test_missing_or_invalid_fields_do_not_invent_a_layout(self):
        for key in self.fixture():
            fields = self.fixture()
            fields.pop(key)
            self.assertEqual(interaction_metadata(fields), {})
        fields = self.fixture()
        fields['armorAttachPoint']['x'] = float('nan')
        self.assertEqual(interaction_metadata(fields), {})
        fields = self.fixture()
        fields['animationRadius'] = -1
        self.assertEqual(interaction_metadata(fields), {})


if __name__ == '__main__':
    unittest.main()
