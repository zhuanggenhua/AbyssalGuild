extends RefCounted
## Ordered bottom-to-top instance IDs; recipe time is measured in seconds.
var id: int
var card_ids: Array = []
var position: Vector2 = Vector2.ZERO
var recipe_guid: String = ""
var progress: float = 0.0
var paused: bool = false
## Live task identity; serialized ordering is owned by CraftingOrder.
var craft_generation: int = 0

func _init(instance_id: int) -> void:
	id = instance_id

func cancel_craft() -> void:
	craft_generation += 1
	recipe_guid = ""
	progress = 0.0
	paused = false
