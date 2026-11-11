"""Independent synthetic Puff records: no licensed particle export fixtures."""
import copy
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from puff_visual_metadata import puff_metadata, scene_puff_metadata, curve_keys, opacity_keys


def doc(kind, key, **fields):
    return {'object_type': kind, 'file_id': str(key), 'fields': fields}


def constant(value): return {'minMaxState': 0, 'scalar': value}
def range_value(low, high): return {'minMaxState': 3, 'minScalar': low, 'scalar': high}
def key(time, value, slope=0, mode=0, weight=.3):
    return {'time': time, 'value': value, 'inSlope': slope, 'outSlope': slope, 'inWeight': weight, 'outWeight': weight, 'weightedMode': mode}


def fixture(count=7):
    owner = {'fileID': '1'}
    system = {'m_GameObject': owner, 'looping': 0, 'prewarm': 0, 'playOnAwake': 1, 'useUnscaledTime': 1, 'moveWithTransform': 0, 'simulationSpeed': 1,
              'stopAction': 0, 'ringBufferMode': 0, 'startDelay': constant(0), 'lengthInSec': 2,
              'InitialModule': {'enabled': 1, 'size3D': 0, 'rotation3D': 0, 'randomizeRotationDirection': 0, 'maxNumParticles': 100,
                  'startLifetime': range_value(.2,.8), 'startSpeed': range_value(1,2), 'startSize': range_value(.1,.2),
                  'startColor': {'minMaxState': 0, 'maxColor': {'r': .4, 'g': .5, 'b': .6, 'a': .7}},
                  **{name: constant(0) for name in ('gravityModifier','startRotation','startRotationX','startRotationY')}},
              'EmissionModule': {'enabled': 1, 'rateOverTime': constant(0), 'rateOverDistance': constant(0), 'm_BurstCount': 1,
                  'm_Bursts': [{'time': 0, 'countCurve': constant(count), 'cycleCount': 1, 'probability': 1}]},
              'ShapeModule': {'enabled': 1, 'type': 10, 'radiusThickness': 1, 'randomDirectionAmount': 0, 'sphericalDirectionAmount': 1,
                  'randomPositionAmount': 0, 'alignToDirection': 0, 'm_Position': {'x': 0,'y': .2,'z': 0}, 'm_Rotation': {'x': 10,'y': 20,'z': 30},
                  'm_Scale': {'x': 1,'y': 1,'z': 1}, 'radius': {'value': .4,'mode': 0}, 'arc': {'value': 360,'mode': 0}},
              'SizeModule': {'enabled': 1, 'separateAxes': 0, 'curve': {'minMaxState': 1, 'scalar': 1, 'maxCurve': {'m_Curve': [key(0,0,1),key(1,1,1)]}}},
              'ColorModule': {'enabled': 1, 'gradient': {'minMaxState': 1, 'maxGradient': {'m_Mode': 0, 'm_NumColorKeys': 2,'m_NumAlphaKeys': 2,
                  'key0': {'r':1,'g':1,'b':1,'a':1}, 'key1': {'r':1,'g':1,'b':1,'a':0}, 'atime0':0,'atime1':65535}}}}
    return [doc('MonoBehaviour',2,m_GameObject=owner),doc('Transform',3,m_GameObject=owner,m_Father={'fileID':'0'},
                m_LocalPosition={'x':0,'y':0,'z':0},m_LocalRotation={'x':0,'y':0,'z':0,'w':1},m_LocalScale={'x':1,'y':1,'z':1}),
            doc('ParticleSystem',4,**system),doc('ParticleSystemRenderer',5,m_GameObject=owner,m_RenderMode=2,m_Materials=[{'guid':'material'}])]


class PuffVisualMetadataTests(unittest.TestCase):
    def test_reference_ownership_ranges_and_provenance(self):
        docs = fixture()
        old = copy.deepcopy(docs)
        result = puff_metadata(docs, {'fileID':'2','guid':'puff'})
        self.assertTrue(result['supported'],result['unsupported'])
        self.assertEqual(result['burst_count'],7)
        self.assertEqual(result['cleanup_scaled_seconds'],2.1)
        self.assertEqual(result['ranges']['speed'],{'min':1,'max':2})
        self.assertEqual(result['materials'][0]['guid'],'material')
        self.assertEqual(result['material_equivalence'],'unresolved_builtin_shader')
        self.assertEqual(docs,old)
        self.assertEqual(puff_metadata(docs,{'fileID':'wrong'}),{})
        docs[3]['fields']['m_GameObject']={'fileID':'other'}
        self.assertEqual(puff_metadata(docs,{'fileID':'2'}),{})

    def test_unequal_scene_settings_resolve_exact_guid_and_component(self):
        sources = {'a':[doc('MonoBehaviour',9,puffParticle={'fileID':'2','guid':'pa'})],
                   'b':[doc('MonoBehaviour',9,puffParticle={'fileID':'2','guid':'pb'})], 'pa':fixture(5),'pb':fixture(11)}
        read = lambda guid:sources.get(guid,[])
        a = scene_puff_metadata({'cardSettings':{'guid':'a','fileID':'9'}},read)
        b = scene_puff_metadata({'cardSettings':{'guid':'b','fileID':'9'}},read)
        self.assertEqual((a['burst_count'],b['burst_count']),(5,11))
        self.assertEqual((a['settings_guid'],b['settings_guid']),('a','b'))
        self.assertEqual(scene_puff_metadata({'cardSettings':{'guid':'a','fileID':'wrong'}},read),{})
        self.assertEqual(scene_puff_metadata({},read),{})

    def test_unsupported_modules_report_reason_not_silent_approximation(self):
        docs=fixture();docs[2]['fields']['NoiseModule']={'enabled':1}
        result=puff_metadata(docs,{'fileID':'2'})
        self.assertFalse(result['supported']);self.assertIn('enabled module: NoiseModule',result['unsupported'])
        self.assertNotIn('ranges',result)
        docs[2]['fields']['NoiseModule']['enabled']=0
        self.assertTrue(puff_metadata(docs,{'fileID':'2'})['supported'])

    def test_emission_and_time_domain_changes_rejected(self):
        for field,value in [('useUnscaledTime',0),('looping',1),('lengthInSec',float('nan'))]:
            docs=fixture();docs[2]['fields'][field]=value
            self.assertFalse(puff_metadata(docs,{'fileID':'2'})['supported'])
        docs=fixture();docs[2]['fields']['EmissionModule']['m_Bursts'][0]['probability']=.5
        self.assertIn('burst schedule',puff_metadata(docs,{'fileID':'2'})['unsupported'])
        docs=fixture();docs[2]['fields']['InitialModule']['maxNumParticles']=1
        self.assertIn('particle capacity',puff_metadata(docs,{'fileID':'2'})['unsupported'])

    def test_weighted_curve_retains_weights_and_rejects_invalid_time(self):
        curve={'minMaxState':1,'scalar':1,'maxCurve':{'m_Curve':[key(0,0,2,2,.6),key(1,1,0,1,.2)]}}
        self.assertEqual(curve_keys(curve)[0]['outWeight'],.6)
        curve['maxCurve']['m_Curve'][1]['time']=0
        self.assertIsNone(curve_keys(curve))
        curve['maxCurve']['m_Curve'][1]['time']=1
        curve['maxCurve']['m_Curve'][0]['outSlope']=float('inf')
        self.assertIsNone(curve_keys(curve))

    def test_opacity_time_is_uint16_normalized_and_color_is_not_guessed(self):
        gradient=fixture()[2]['fields']['ColorModule']['gradient']
        gradient['maxGradient'].update({'m_NumAlphaKeys':3,'atime1':32767,'atime2':65535,'key2':{'a':0}})
        gradient['maxGradient']['key1']['a']=1
        self.assertEqual(opacity_keys(gradient)[1]['time'],32767/65535)
        gradient['maxGradient']['key1']['r']=.3
        self.assertIsNone(opacity_keys(gradient))

    def test_shape_orientation_and_range_validation(self):
        docs=fixture();docs[2]['fields']['ShapeModule']['m_Scale']['x']=2
        self.assertIn('shape scale',puff_metadata(docs,{'fileID':'2'})['unsupported'])
        docs=fixture();docs[2]['fields']['InitialModule']['startLifetime']=range_value(2,1)
        self.assertIn('lifetime range',puff_metadata(docs,{'fileID':'2'})['unsupported'])


if __name__=='__main__':unittest.main()
