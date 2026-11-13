import itertools
import math
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from source_lit_equations import (DIFFUSE, FLT_MIN, direction, finite_rgb,
    godot_custom_direct, safe_normalize, source_direct, specular, srgb_to_linear)


class SourceLitEquationTests(unittest.TestCase):
    def test_normal_incidence(self):
        result = source_direct((.5,) * 3, (0, 0, 1), (0, 0, 1), (0, 0, 1))
        self.assertAlmostEqual(result[0], .48 + .04 / (6 * 1.00001 ** 2), places=14)

    def test_diffuse_is_not_an_authored_tint_mutation(self):
        albedo = (.4, .2, .6)
        source_direct(albedo, (0, 0, 1), direction(35), direction(0))
        self.assertEqual(albedo, (.4, .2, .6))
        self.assertEqual(DIFFUSE, .96)

    def test_bridge_grid_2295_cases(self):
        count = 0
        for light_angle, view_angle, intensity, attenuation, albedo in itertools.product(
                range(-80, 81, 20), range(-80, 81, 10), (0.0, .5, 1.0), (.1, 1.0, 2.0, .75, .25), ((.4, .2, .6),)):
            args = (albedo, (0, 0, 1), direction(light_angle), direction(view_angle), (intensity,) * 3, attenuation)
            for actual, expected in zip(godot_custom_direct(*args), source_direct(*args)):
                self.assertAlmostEqual(actual, expected, places=14)
            count += 1
        self.assertEqual(count, 2295)

    def test_opposite_halfway_is_finite(self):
        self.assertEqual(safe_normalize((0., 0., 0.)), (0., 0., 0.))
        self.assertAlmostEqual(specular((0, 0, 1), (0, 0, -1)), .04 / (.6 * 1.00001 ** 2))

    def test_near_opposite_is_finite(self):
        for tiny in (1e-8, 1e-16, 1e-20, 1e-30):
            result = source_direct((.4, .2, .6), (0, 0, 1), (0, 0, 1), (tiny, 0, -1))
            self.assertTrue(finite_rgb(result))

    def test_tiny_guard_is_source_float_min_not_epsilon(self):
        self.assertEqual(FLT_MIN, 1.175494351e-38)
        self.assertAlmostEqual(safe_normalize((1e-20, 0, 0))[0], 1e-20 / math.sqrt(FLT_MIN))
        self.assertLess(safe_normalize((1e-20, 0, 0))[0], 1)

    def test_back_light_is_zero(self):
        self.assertEqual(source_direct((.5,) * 3, (0, 0, 1), (0, 0, -1), (0, 0, 1)), (0., 0., 0.))

    def test_light_color_and_attenuation(self):
        base = source_direct((.5,) * 3, (0, 0, 1), (0, 0, 1), (0, 0, 1))[0]
        result = source_direct((.5,) * 3, (0, 0, 1), (0, 0, 1), (0, 0, 1), (1, 2, 3), .2)
        for c, expected in zip(result, (base * .2, base * .4, base * .6)):
            self.assertAlmostEqual(c, expected)

    def test_oblique_specular_is_not_constant(self):
        self.assertGreater(specular(direction(75), direction(-30)), specular(direction(0), direction(0)))

    def test_black_retains_dielectric_specular(self):
        self.assertGreater(source_direct((0,) * 3, (0, 0, 1), (0, 0, 1), (0, 0, 1))[0], 0)

    def test_srgb_boundary(self):
        self.assertAlmostEqual(srgb_to_linear(.04045), .04045 / 12.92)
        self.assertEqual(srgb_to_linear(1.), 1.)


if __name__ == '__main__':
    unittest.main()
