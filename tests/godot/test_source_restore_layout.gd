extends SceneTree
const Layout = preload("res://scripts/model/board_layout.gd")
const Restore = preload("res://scripts/model/source_restore_layout.gd")
class Fixture extends RefCounted:
	var cards := {}
	var stacks := {}
	var equipment := {"owners": {}}
	var rng_marker := 111
var checks := 0
var failures := 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func card(id: int, gear: Array = []) -> Dictionary:
	return {"id": id, "size": Vector2(1, 1.25), "pack": false, "equipment": gear, "equipper_supported": true}
func item(id: int, slot: int) -> Dictionary:
	var row := card(id); row.slot = slot; row.equip_succeeds = true
	return row
func stack(id: int, point: Vector2, members: Array) -> Dictionary:
	return {"id": id, "position": point, "cards": members}
func config(defaults: bool = false) -> Dictionary:
	return {"scene": "Main", "bounds": Rect2(-6, -4, 12, 8), "step": Vector3(0, 0.002, -0.18), "top_margin": 1.5, "max_iterations": 8, "combat": false, "board_boost": 0, "default_spawn": defaults}
func fixture(records: Array) -> Fixture:
	var result := Fixture.new()
	for record in records:
		var ids: Array = []
		for member in record.cards:
			ids.append(member.id)
			result.cards[member.id] = {"stack_id": record.id, "position": record.position, "health": 7, "uses": 3}
			for gear in member.equipment:
				result.cards[gear.id] = {"stack_id": -1, "position": Vector2(3, 1), "health": 15, "uses": 4}
				result.equipment.owners[gear.id] = member.id
		result.stacks[record.id] = {"card_ids": ids, "position": record.position}
	return result
func events(plan: Dictionary) -> Array:
	var rows: Array = []
	for event in plan.trace: rows.append(event.event)
	return rows
func _init():
	var single := [stack(100, Vector2.ZERO, [card(1)]), stack(200, Vector2(0.2, 0), [card(2)])]
	var frozen: Array = single.duplicate(true)
	var plan := Restore.plan(single, [], config())
	check(plan.ok and single == frozen, "plan is non-mutating")
	check(plan.states[1].position == single[1].position, "normal final saved anchor is reset, not blanket-resolved again")
	check(events(plan).count("resolve") == 2 and events(plan).count("reset_anchor") == 4, "cold per-card initialize and two normal anchor resets")
	var multi := [stack(100, Vector2.ZERO, [card(1), card(2), card(3)])]
	plan = Restore.plan(multi, [], config())
	check(plan.ok and plan.states.size() == 1 and plan.states[0].card_ids == [1, 2, 3], "temporary stacks removed, persistent stack identity and membership retained")
	check(events(plan).count("resolve") == 3 and events(plan).count("unregister_temporary_and_append") == 2, "one solver per source temporary initialize")
	var owner := card(10, [item(11, 0), item(12, 1), item(13, 2)])
	var incoming := [stack(300, Vector2(3, 1), [owner]), stack(400, Vector2(3, 1), [card(20, [item(21, 0)])])]
	plan = Restore.plan(single, incoming, config())
	check(plan.ok and plan.states.map(func(row): return row.id) == [300, 400, 100, 200], "travelers registered before saved destination")
	check(events(plan).slice(0, 9) == ["traveler_initialize", "resolve", "equipment_initialize_at_zero", "resolve", "equip_unregister", "equipment_initialize_at_zero", "resolve", "equip_unregister", "equipment_initialize_at_zero"], "owner equipment restored immediately before next traveler")
	check(events(plan).count("resolve") == 8 and events(plan).count("equip_unregister") == 4, "gear creation resolves and successful unregister adds no resolver")
	check(plan.states.size() == 4, "gear has no residual world stack")
	var packed := card(30); packed.pack = true; packed.attachment_forbidden = true
	plan = Restore.plan([stack(500, Vector2.ZERO, [packed])], incoming, config(true))
	check(plan.ok and not events(plan).has("reset_anchor"), "default pack and incoming cards have no cold anchor reset")
	var live := fixture(single + incoming)
	var before_cards := live.cards.duplicate(true)
	var before_owners: Dictionary = live.equipment.owners.duplicate()
	plan = Restore.plan(single, incoming, config())
	check(Restore.apply(live, plan).ok, "explicit commit applies validated plan")
	check(live.stacks.keys() == [300, 400, 100, 200] and live.rng_marker == 111, "apply only reorders source registry, no RNG")
	check(live.equipment.owners == before_owners and live.cards.size() == before_cards.size(), "equipment owner graph and all IDs preserved")
	for id in live.cards:
		check(live.cards[id].health == before_cards[id].health and live.cards[id].uses == before_cards[id].uses, "apply preserves stats " + str(id))
	var stale := fixture(single)
	plan = Restore.plan(single, [], config())
	stale.stacks[100].position = Vector2(4, 2)
	var before := str([stale.cards, stale.stacks, stale.equipment])
	check(not Restore.apply(stale, plan).ok and str([stale.cards, stale.stacks, stale.equipment]) == before, "stale geometry rejected atomically")
	stale = fixture(single + incoming)
	plan = Restore.plan(single, incoming, config())
	stale.equipment.owners[11] = 20
	before = str([stale.cards, stale.stacks, stale.equipment])
	check(not Restore.apply(stale, plan).ok and str([stale.cards, stale.stacks, stale.equipment]) == before, "stale equipment owner rejected atomically")
	for invalid in ["nested", "duplicate_slot", "shared_item", "unsupported_owner", "pack_query", "size", "combat", "boost", "scene"]:
		var records: Array = incoming.duplicate(true)
		var settings := config()
		match invalid:
			"nested": records[0].cards[0].equipment[0].equipment = [item(99, 1)]
			"duplicate_slot": records[0].cards[0].equipment[1].slot = 0
			"shared_item": records[1].cards[0].equipment[0].id = 11
			"unsupported_owner": records[0].cards[0].equipper_supported = false
			"pack_query": records[0].cards[0] = packed.duplicate(true); records[0].cards[0].attachment_forbidden = false
			"size": records[0].cards[0].size = Vector2.ZERO
			"combat": settings.combat = true
			"boost": settings.board_boost = 1
			"scene": settings.scene = "Unknown"
		var unchanged := str(records)
		check(not Restore.plan([], records, settings).ok and str(records) == unchanged, "unsupported " + invalid + " safely rejects without mutation")
	var expanded := config()
	expanded.board_boost = 4
	expanded.expansion = {"ok": true, "boost": 4, "initial_bounds": expanded.bounds, "final_bounds": Rect2(-6.24, -4.16, 12.48, 8.32)}
	check(Restore.plan(single, [], expanded).ok, "explicit positive source phase contract admitted")
	for invalid in ["null", "negative", "mismatch", "initial", "final"]:
		var bad := expanded.duplicate(true)
		match invalid:
			"null": bad.expansion = null
			"negative": bad.board_boost = -4; bad.expansion.boost = -4
			"mismatch": bad.expansion.boost = 8
			"initial": bad.expansion.initial_bounds = Rect2()
			"final": bad.expansion.final_bounds = Rect2(-1,-1,2,2)
		check(not Restore.plan(single, [], bad).ok, "invalid expansion phase rejected " + invalid)
	var rng := RandomNumberGenerator.new()
	rng.seed = 72135
	for trial in 200:
		var states: Array = []
		for id in rng.randi_range(1, 16):
			var point := Vector2.ZERO if trial % 3 == 0 else Vector2(rng.randf_range(-25,25), rng.randf_range(-25,25))
			states.append(Layout.stack_state(id+1, point, Vector2(rng.randf_range(0.1,4),rng.randf_range(0.1,4)), rng.randi_range(0,20), id % 5 == 0, Vector3(0,0.002,-0.18)))
		var initial := states.duplicate(true)
		var bound := Rect2(-6,-4,12,8)
		var limit := rng.randi_range(1,10)
		check(Restore._resolve_cached(states,bound,1.5,limit) == Layout.resolve_overlaps(states,[],bound,1.5,limit), "exact cached resolver result/iteration " + str(trial))
		check(states == initial, "cached resolver preserves caller input " + str(trial))
	print("Source restore layout planner: ", checks, " checks, ", failures, " failures; no live board integration")
	quit(1 if failures else 0)
