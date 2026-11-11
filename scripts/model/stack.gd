extends RefCounted
## Ordered bottom-to-top instance IDs; recipe time is measured in seconds.
var id: int
var card_ids: Array = []
var position: Vector2 = Vector2.ZERO
var recipe_guid: String = ""
var progress: float = 0.0
var paused: bool = false

func _init(instance_id: int) -> void:
	id = instance_id

func cancel_craft() -> void:
	recipe_guid = ""
	progress = 0.0
	paused = false
