extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks := 0
var failures := 0
var catalog = Catalog.new()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", label)
func session():
	var result = Session.new()
	result.configure(catalog, 417)
	return result
func fruit(s, progress: float = 3) -> Array:
	var apple: int = s.spawn_card(catalog.find_by_name("Apple"), Vector2(-4, 0))
	var berry: int = s.spawn_card(catalog.find_by_name("Berry"), Vector2(-2, 0))
	check(s.move_to_stack(berry, s.cards[apple].stack_id), "real Apple/Berry recipe assembles")
	var stack = s.stacks[s.cards[apple].stack_id]
	check(catalog.fields(catalog.ref_guid(catalog.fields(stack.recipe_guid).get("resultingCard", {}))).get("displayName") == "Fruit Salad", "real Fruit Salad task selected")
	stack.progress = progress
	return [apple, berry, stack]
func _init() -> void:
	check(catalog.load_file() == OK, "locked private source catalog loads")
	if catalog.data.is_empty(): quit(1); return
	var s = session(); var ids := fruit(s, 9.9)
	s.drag.begin(ids[1]); s.tick(0.2)
	check(s.cards.has(ids[1]) and ids[2].paused and ids[2].progress == 9.9, "real 9.9-second Fruit Salad cannot consume held Berry")
	var restored = session()
	check(Codec.restore(restored, Codec.capture(s)).ok, "real held Fruit Salad checkpoint restores")
	check(restored.cards[ids[0]].stack_id != restored.cards[ids[1]].stack_id and restored.stacks[ids[2].id].recipe_guid.is_empty(), "real held save records separated cards and lawful stopped recipe")
	check(s.move_to_stack(ids[1], ids[2].id, s.drag.original_stack_id(ids[1])), "real Berry returns to original strict craft")
	s.drag.finish_standard(ids[2].id)
	check(ids[2].progress == 9.9 and not ids[2].paused, "real return preserves elapsed progress")
	s.tick(0.2)
	check(not s.cards.has(ids[1]), "real resumed Fruit Salad completes")
	# Travel remains an active timed recipe on whole-stack pickup, but pauses on
	# traveler-tail pickup. Native scene commit clears every old hold identity.
	var travel: Dictionary = {}
	for entry in catalog.data.recipes:
		if entry.script_class == "TravelRecipe": travel = entry
	s = session()
	var portal: int = s.spawn_card(catalog.find_by_name("Grand Portal"), Vector2(5, 3))
	var person: int = s.spawn_card(catalog.find_by_name("Villager"))
	s.move_to_stack(person, s.cards[portal].stack_id)
	var portal_stack = s.stacks[s.cards[portal].stack_id]
	portal_stack.progress = float(travel.fields.craftingDuration) - 0.1
	s.drag.begin(person); s.tick(0.2)
	check(s.scene_name == "Main" and portal_stack.paused, "held traveler tail cannot complete travel")
	s.move_to_stack(person, portal_stack.id, s.drag.original_stack_id(person)); s.drag.finish_standard(portal_stack.id)
	s.drag.begin(portal); s.tick(0.2)
	check(s.scene_name == "Island" and not s.drag.active(), "whole-stack travel can complete and clears old scene hold")
	check(s.campaign.saved_scenes.has("Main") and s.campaign.saved_scenes.Main.session.cards.is_empty(), "travel departure checkpoint leaves no orphan travelers")
	# A different traveling stack can change scene while a fruit tail is held.
	s = session(); ids = fruit(s)
	s.drag.begin(ids[1])
	portal = s.spawn_card(catalog.find_by_name("Grand Portal"), Vector2(6, 0))
	person = s.spawn_card(catalog.find_by_name("Villager"))
	s.move_to_stack(person, s.cards[portal].stack_id)
	portal_stack = s.stacks[s.cards[portal].stack_id]
	portal_stack.progress = float(travel.fields.craftingDuration) - 0.1
	s.tick(0.2)
	check(s.scene_name == "Island" and not s.drag.active(), "unrelated travel invalidates old held card context")
	var saved: Dictionary = s.campaign.saved_scenes.Main
	check(saved.session.cards.size() == 2 and saved.session.stacks.size() == 2, "inactive departure scene preserves real held split")
	var old_scene = session()
	check(Codec.restore(old_scene, saved).ok and not old_scene.stacks[ids[2].id].paused and old_scene.stacks[ids[2].id].recipe_guid.is_empty(), "inactive departure scene restores without permanently paused task")
	print("Source held stack checks: %d passed / %d total" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
