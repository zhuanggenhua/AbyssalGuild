"""Bounded, fail-closed extraction of source Universal Lit direct-light inputs.

This independently authored adapter contains no original graph data. Unknown
schemas and geometry overrides deliberately retain the existing fallback path.
"""
import hashlib
import json

SG = 'UnityEditor.ShaderGraph.'
URP = 'UnityEditor.Rendering.Universal.ShaderGraph.'


def graph_objects(text):
    """Read ShaderGraph's concatenated JSON objects, rejecting duplicate IDs."""
    remaining = text.lstrip('\ufeff').strip()
    def unique_keys(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('Duplicate JSON key')
            result[key] = value
        return result
    decoder = json.JSONDecoder(object_pairs_hook=unique_keys)
    objects = {}
    while remaining:
        item, end = decoder.raw_decode(remaining)
        if not isinstance(item, dict):
            raise ValueError('Graph object must be a dictionary')
        identity = item.get('m_ObjectId')
        if not isinstance(identity, str) or not identity or identity in objects:
            raise ValueError('Missing or duplicate graph object ID')
        objects[identity] = item
        remaining = remaining[end:].strip()
    return objects


def source_lit_metadata(text):
    """Return schema 2 contract, or {} when the supported facts are unproven."""
    try:
        objects = graph_objects(text)
        graphs = [x for x in objects.values() if x.get('m_Type') == SG + 'GraphData']
        if len(graphs) != 1:
            return {}
        graph = graphs[0]
        if graph.get('m_SGVersion') != 3 or graph.get('m_Keywords') != []:
            return {}

        def resolve(reference):
            return objects[reference['m_Id']]

        targets = [resolve(r) for r in graph['m_ActiveTargets']]
        targets = [x for x in targets if x.get('m_Type') == URP + 'UniversalTarget']
        if len(targets) != 1:
            return {}
        target = targets[0]
        expected = {'m_SGVersion': 1, 'm_SurfaceType': 0,
                    'm_AllowMaterialOverride': False, 'm_AlphaClip': False, 'm_RenderFace': 2}
        if any(target.get(k) != v for k, v in expected.items()):
            return {}
        subtarget = resolve(target['m_ActiveSubTarget'])
        if subtarget.get('m_Type') != URP + 'UniversalLitSubTarget':
            return {}
        expected = {'m_SGVersion': 2, 'm_WorkflowMode': 1,
                    'm_ClearCoat': False, 'm_NormalDropOffSpace': 0}
        if any(subtarget.get(k) != v for k, v in expected.items()):
            return {}
        nodes = {r['m_Id'] for r in graph['m_Nodes']}
        incoming = {e['m_InputSlot']['m_Node']['m_Id'] for e in graph['m_Edges']}

        def blocks(context):
            result = {}
            for reference in graph[context]['m_Blocks']:
                node = resolve(reference)
                name = node['m_SerializedDescriptor']
                if (node['m_ObjectId'] not in nodes or name in result or
                        node.get('m_Type') != SG + 'BlockNode' or node.get('m_SGVersion') != 0):
                    raise ValueError('Unknown or repeated active block')
                if not isinstance(node.get('m_Slots'), list) or not node['m_Slots']:
                    raise ValueError('Missing active block slots')
                for slot_reference in node['m_Slots']:
                    resolve(slot_reference)
                result[name] = node
            return result

        vertex = blocks('m_VertexContext')
        fragment = blocks('m_FragmentContext')
        if set(vertex) != {'VertexDescription.' + n for n in ('Position', 'Normal', 'Tangent')}:
            return {}
        allowed = {'SurfaceDescription.' + n for n in
                   ('BaseColor', 'NormalTS', 'Metallic', 'Smoothness', 'Emission', 'Occlusion')}
        if set(fragment) != allowed:
            return {}

        def fixed_slot(node, kind, stage):
            if node['m_ObjectId'] in incoming or len(node['m_Slots']) != 1:
                raise ValueError('Connected or ambiguous fixed block')
            slot = resolve(node['m_Slots'][0])
            expected = {'m_Type': SG + kind, 'm_SGVersion': 0,
                        'm_StageCapability': stage, 'm_SlotType': 0, 'm_Id': 0}
            if any(slot.get(k) != v for k, v in expected.items()):
                raise ValueError('Unsupported slot schema')
            return slot

        for name, kind, space, stage, context in (
            ('Position', 'PositionMaterialSlot', 0, 1, vertex),
            ('Normal', 'NormalMaterialSlot', 0, 1, vertex),
            ('Tangent', 'TangentMaterialSlot', 0, 1, vertex),
            ('NormalTS', 'NormalMaterialSlot', 3, 2, fragment),
        ):
            prefix = 'VertexDescription.' if stage == 1 else 'SurfaceDescription.'
            slot = fixed_slot(context[prefix + name], kind, stage)
            zero = {'x': 0, 'y': 0, 'z': 0}
            # These zero values denote unchanged vertex attributes, not zero normals.
            if slot.get('m_Space') != space or slot.get('m_Value') != zero or slot.get('m_DefaultValue') != zero:
                return {}
        for name in ('Metallic', 'Smoothness'):
            slot = fixed_slot(fragment['SurfaceDescription.' + name], 'Vector1MaterialSlot', 2)
            if type(slot.get('m_Value')) not in (float, int) or slot['m_Value'] != 0:
                return {}
        return {'schema_version': 2, 'geometry': 'unmodified_object_vertices_tangent_normal',
                'target': 'universal_lit', 'workflow': 'metallic', 'metallic': 0,
                'smoothness': 0, 'opaque': True, 'double_sided': True,
                'clearcoat': False, 'material_override': False,
                'graph_sha256': hashlib.sha256(text.encode('utf-8')).hexdigest()}
    except (ValueError, KeyError, TypeError, AttributeError):
        return {}
