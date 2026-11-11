"""Private, scene-referenced Puff metadata for the explicitly supported subset."""
from __future__ import annotations
import copy
import math
from visual_scene_metadata import transform_chain


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def vector(value, keys):
    return isinstance(value, dict) and all(number(value.get(k)) for k in keys)


def value_range(value, positive=False):
    if not isinstance(value, dict) or value.get('minMaxState') not in (0, 3):
        return None
    high = value.get('scalar')
    low = value.get('minScalar') if value['minMaxState'] == 3 else high
    if not number(low) or not number(high) or low > high or low < 0 or (positive and low <= 0):
        return None
    return {'min': low, 'max': high}


def constant(value, expected):
    return isinstance(value, dict) and value.get('minMaxState') == 0 and value.get('scalar') == expected


def curve_keys(value):
    if not isinstance(value, dict) or value.get('minMaxState') != 1 or value.get('scalar') != 1:
        return None
    curve = value.get('maxCurve', {}).get('m_Curve', [])
    if len(curve) < 2:
        return None
    result = []
    for key in curve:
        names = ('time', 'value', 'inSlope', 'outSlope', 'inWeight', 'outWeight', 'weightedMode')
        if not all(number(key.get(k)) for k in names) or key['weightedMode'] not in (0, 1, 2, 3):
            return None
        if not 0 <= key['time'] <= 1 or not 0 <= key['inWeight'] <= 1 or not 0 <= key['outWeight'] <= 1:
            return None
        if result and key['time'] <= result[-1]['time']:
            return None
        result.append({k: key[k] for k in names})
    return result if result[0]['time'] == 0 and result[-1]['time'] == 1 else None


def opacity_keys(value):
    if not isinstance(value, dict) or value.get('minMaxState') != 1:
        return None
    gradient = value.get('maxGradient', {})
    if gradient.get('m_Mode') != 0:
        return None
    count = gradient.get('m_NumColorKeys', 0)
    alpha_count = gradient.get('m_NumAlphaKeys', 0)
    if not isinstance(count, int) or not isinstance(alpha_count, int) or not 1 <= count <= 8 or not 2 <= alpha_count <= 8:
        return None
    # This checkpoint does not invent gamma-space interpolation for colored ramps.
    for index in range(count):
        if any(gradient.get(f'key{index}', {}).get(k) != 1 for k in 'rgb'):
            return None
    result = []
    for index in range(alpha_count):
        time, alpha = gradient.get(f'atime{index}'), gradient.get(f'key{index}', {}).get('a')
        if not number(time) or not number(alpha) or not 0 <= time <= 65535 or not 0 <= alpha <= 1:
            return None
        if result and time / 65535 <= result[-1]['time']:
            return None
        result.append({'time': time / 65535, 'value': alpha})
    return result if result[0]['time'] == 0 and result[-1]['time'] == 1 else None


def puff_metadata(documents, reference):
    component = next((d for d in documents if d['object_type'] == 'MonoBehaviour' and str(d['file_id']) == str(reference.get('fileID'))), {})
    owner = component.get('fields', {}).get('m_GameObject')
    if not owner:
        return {}
    system = next((d['fields'] for d in documents if d['object_type'] == 'ParticleSystem' and d['fields'].get('m_GameObject') == owner), {})
    renderer = next((d['fields'] for d in documents if d['object_type'] == 'ParticleSystemRenderer' and d['fields'].get('m_GameObject') == owner), {})
    if not system or not renderer:
        return {}
    result = {'prefab_guid': reference.get('guid', ''), 'transform_chain': transform_chain(documents, owner),
              'materials': copy.deepcopy(renderer.get('m_Materials', [])), 'renderer_mode': renderer.get('m_RenderMode'),
              'renderer_fields': {k: copy.deepcopy(renderer.get(k)) for k in ('m_CastShadows', 'm_ReceiveShadows', 'm_SortMode', 'm_MinParticleSize', 'm_MaxParticleSize', 'm_RenderAlignment', 'm_Pivot', 'm_Flip')},
              'unsupported': [], 'material_equivalence': 'unresolved_builtin_shader', 'rng_equivalence': 'independent_presentation_rng', 'auto_random_seed': system.get('autoRandomSeed'), 'source_random_seed': system.get('randomSeed')}
    errors = result['unsupported']
    def require(ok, reason):
        if not ok:
            errors.append(reason)
    active = {'InitialModule', 'ShapeModule', 'EmissionModule', 'SizeModule', 'ColorModule'}
    for key, value in system.items():
        if key.endswith('Module') and isinstance(value, dict) and value.get('enabled') and key not in active:
            errors.append('enabled module: ' + key)
    for key, expected in {'looping': 0, 'prewarm': 0, 'playOnAwake': 1, 'useUnscaledTime': 1, 'moveWithTransform': 0, 'simulationSpeed': 1, 'stopAction': 0, 'ringBufferMode': 0}.items():
        require(system.get(key) == expected, key)
    require(constant(system.get('startDelay'), 0), 'start delay')
    duration = system.get('lengthInSec')
    require(number(duration) and duration > 0, 'duration')
    pose = result['transform_chain']
    require(len(pose) == 1 and pose[0].get('m_LocalScale') == {'x': 1, 'y': 1, 'z': 1}, 'root scale/hierarchy')
    initial = system.get('InitialModule', {})
    require(initial.get('enabled') == 1 and initial.get('size3D') == 0 and initial.get('rotation3D') == 0, 'initial module axes')
    ranges = {key: value_range(initial.get(field), key in ('lifetime', 'size')) for key, field in [('lifetime', 'startLifetime'), ('speed', 'startSpeed'), ('size', 'startSize')]}
    for key, value in ranges.items(): require(value is not None, key + ' range')
    require(all(constant(initial.get(key), 0) for key in ('gravityModifier', 'startRotation', 'startRotationX', 'startRotationY')), 'gravity/start rotation')
    require(initial.get('randomizeRotationDirection') == 0, 'random rotation')
    color = initial.get('startColor', {})
    require(color.get('minMaxState') == 0 and vector(color.get('maxColor'), 'rgba'), 'start color')
    emission = system.get('EmissionModule', {})
    require(emission.get('enabled') == 1 and constant(emission.get('rateOverTime'), 0) and constant(emission.get('rateOverDistance'), 0), 'continuous emission')
    bursts = emission.get('m_Bursts', [])
    require(emission.get('m_BurstCount') == 1 and isinstance(bursts, list) and len(bursts) == 1, 'single burst')
    burst = bursts[0] if isinstance(bursts, list) and len(bursts) == 1 else {}
    count = burst.get('countCurve', {}).get('scalar')
    require(number(count) and count == int(count) and 1 <= count <= 1000 and constant(burst.get('countCurve'), count), 'burst count')
    require(burst.get('time') == 0 and burst.get('cycleCount') == 1 and burst.get('probability') == 1, 'burst schedule')
    require(number(initial.get('maxNumParticles')) and number(count) and initial['maxNumParticles'] >= count, 'particle capacity')
    shape = system.get('ShapeModule', {})
    required_shape = {'enabled': 1, 'type': 10, 'radiusThickness': 1, 'randomDirectionAmount': 0, 'sphericalDirectionAmount': 1, 'randomPositionAmount': 0, 'alignToDirection': 0}
    for key, expected in required_shape.items(): require(shape.get(key) == expected, 'shape ' + key)
    for key in ('m_Position', 'm_Rotation', 'm_Scale'): require(vector(shape.get(key), 'xyz'), 'shape ' + key)
    require(shape.get('m_Scale') == {'x': 1, 'y': 1, 'z': 1}, 'shape scale')
    radius = shape.get('radius', {})
    require(number(radius.get('value')) and radius['value'] > 0 and radius.get('mode') == 0, 'shape radius')
    require(shape.get('arc', {}).get('value') == 360 and shape.get('arc', {}).get('mode') == 0, 'shape arc')
    size = system.get('SizeModule', {})
    keys = curve_keys(size.get('curve'))
    require(size.get('enabled') == 1 and size.get('separateAxes') == 0 and keys is not None, 'weighted size curve')
    colors = system.get('ColorModule', {})
    alphas = opacity_keys(colors.get('gradient'))
    require(colors.get('enabled') == 1 and alphas is not None, 'white linear color/opacity ramp')
    require(renderer.get('m_RenderMode') == 2 and len(result['materials']) == 1, 'horizontal billboard/material reference')
    result['supported'] = not errors
    if not errors:
        result.update({'duration': duration, 'cleanup_scaled_seconds': duration + 0.1, 'burst_count': int(count),
                       'ranges': ranges, 'start_color': copy.deepcopy(color['maxColor']), 'size_keys': keys, 'opacity_keys': alphas,
                       'shape': {'radius': radius['value'], 'position': copy.deepcopy(shape['m_Position']), 'rotation_degrees': copy.deepcopy(shape['m_Rotation'])},
                       'birth_sampling': 'uniform_area_disk; outward_from_system_origin; native_rng_not_Unity'})
    return result


def scene_puff_metadata(manager_fields, read):
    reference = manager_fields.get('cardSettings', {})
    if not reference.get('guid'):
        return {}
    settings = next((d['fields'] for d in read(reference['guid']) if d['object_type'] == 'MonoBehaviour' and str(d['file_id']) == str(reference.get('fileID'))), {})
    puff = settings.get('puffParticle', {})
    if not puff.get('guid'):
        return {}
    result = puff_metadata(read(puff['guid']), puff)
    if result:
        result['settings_guid'] = reference['guid']
    return result
