"""Copy explicit panel interaction fields into the ignored private manifest only."""
import copy
import math


def interaction_metadata(fields):
    names = ('weaponAttachPoint', 'armorAttachPoint', 'accessoryAttachPoint')
    points = {}
    for slot, name in enumerate(names):
        value = fields.get(name)
        if not isinstance(value, dict) or not all(isinstance(value.get(axis), (int, float)) and math.isfinite(value[axis]) for axis in ('x', 'y', 'z')):
            return {}
        points[str(slot)] = copy.deepcopy(value)
    radius, speed = fields.get('animationRadius'), fields.get('animationSpeed')
    if not all(isinstance(v, (int, float)) and math.isfinite(v) and v >= 0 for v in (radius, speed)):
        return {}
    return {'attach_points': points, 'animation_radius': radius, 'animation_speed': speed}
