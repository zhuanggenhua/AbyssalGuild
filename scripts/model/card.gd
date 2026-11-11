extends RefCounted
## A card instance. Position belongs to the board plane, independent of rendering.
var id: int
var definition_guid: String
var base_definition_guid: String
var stack_id: int = -1
var uses_left: int = 1
var nutrition: int = 0
var health: int = 0
var position: Vector2 = Vector2.ZERO
var stored_coins: int = 0

func _init(instance_id: int, guid: String, fields: Dictionary) -> void:
	id = instance_id
	definition_guid = guid
	base_definition_guid = guid
	uses_left = int(fields.get("uses", 1)) if fields.get("hasDurability", false) else 1
	nutrition = int(fields.get("nutrition", 0))
	health = int(fields.get("maxHealth", 15))
