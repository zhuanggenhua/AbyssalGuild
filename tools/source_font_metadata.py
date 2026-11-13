"""Retain source TMP font identity rather than treating an external GUID as absent."""
def font_reference(fields):
    reference = fields.get('m_fontAsset', {})
    return {'font_guid': str(reference.get('guid', '')),
            'font_file_id': str(reference.get('fileID', '0')),
            'font_style': fields.get('m_fontStyle'),
            'font_weight': fields.get('m_fontWeight')}
