"""Candidate algebra, not GPU or Unity runtime evidence."""
import itertools, math, unittest
from pathlib import Path

def encode(x): return max(1.055*max(x,0)**(1/2.4)-.055,0)
def old_shadow(a,d): return encode(a)+encode(d)
def candidate(a,d): return encode(a+d)
def linear_ambient(c): return c/12.92 if c<.04045 else ((c+.055)/1.055)**2.4

def direct_parts(albedo,light,attenuation,cosine,half):
    spec=.04/(6*max(.1,half*half)*1.00001*1.00001)
    diff=light*attenuation*cosine*(.96/math.pi)
    specular=light*attenuation*cosine*(spec/math.pi)
    return diff*albedo+specular

def moved_parts(albedo,light,attenuation,cosine,half):
    spec=.04/(6*max(.1,half*half)*1.00001*1.00001)
    return light*attenuation*cosine*(albedo*.96+spec)/math.pi

class EquationChecks(unittest.TestCase):
    def test_direct_is_identical_for_attenuation_and_view_sweep(self):
        n=0
        for a,l,t,c,h in itertools.product([0,.01,.2,.7,1,2],[0,.3,1,math.pi,8],[0,.02,.5,1],[0,.1,.7071068,1],[0,.1,.5,1]):
            self.assertAlmostEqual(direct_parts(a,l,t,c,h),moved_parts(a,l,t,c,h),places=12)
            n+=1
        print('Direct algebra samples',n)
    def test_ambient_is_not_shadow_attenuated(self):
        for a,d,t in itertools.product([0,.02,.2,1],[0,.1,1],[0,.25,.75,1]):
            self.assertAlmostEqual((a+d*t)-d*t,a,places=12)
            self.assertAlmostEqual(candidate(a,d*t),encode(a+d*t),places=12)
    def test_old_native_case_has_large_wrong_composition(self):
        self.assertGreater(old_shadow(.05,.1)-candidate(.05,.1),.15)
    def test_non_general_solution_rejects_missing_or_extra_lights(self):
        a,d=.1,.2
        self.assertNotAlmostEqual(encode(0),candidate(a,0))
        self.assertNotAlmostEqual(encode(a+d)+encode(a+d),encode(a+2*d))
    def test_no_source_data_correction_or_global_shader_change(self):
        s=(Path(__file__).resolve().parents[1] / 'scripts/ui/source_flat_board_lighting.gd').read_text()
        self.assertIn('material.shader.code == Lit.BOARD_FRAGMENT + Lit.DIRECT_LIGHT_CODE',s)
        self.assertIn('lights.size() != 1',s)
        self.assertNotIn('environment.ambient_light_color =',s)
        self.assertNotIn('shadow_enabled =',s)
        self.assertNotIn('source_color = Color(',s)

if __name__=='__main__': unittest.main(verbosity=2)
