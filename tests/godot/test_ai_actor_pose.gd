extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
var checks := 0
var failures := 0
var poses: Dictionary = {}
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func sample(id: int) -> Variant: return poses.get(id)
func _init() -> void:
	var catalog = Catalog.new()
	catalog.configure({"cards": [
		{"guid": "mob", "fields": {"category": 9, "faction": 2, "isAggressive": true, "attackRadius": 1.5, "aggroRadius": 5.0}},
		{"guid": "hero", "fields": {"category": 2, "faction": 1}}]})
	var s = Session.new(); s.configure(catalog, 123)
	var mob: int = s.spawn_card("mob", Vector2.ZERO)
	var near: int = s.spawn_card("hero", Vector2(1, 0))
	var far: int = s.spawn_card("hero", Vector2(8, 0))
	check(s.world.aggressive_intent(mob).action == "attack_player", "no-view fallback preserves settled model behavior")
	s.world.actor_pose_sampler = sample
	poses = {mob: Vector3.ZERO, near: Vector3(10, 0, 0), far: Vector3(3, 0, 0)}
	var intent: Dictionary = s.world.aggressive_intent(mob)
	check(intent.card_id == far and intent.action == "approach_player", "current poses reverse model nearest-target and prevent premature attack")
	check(intent.position_3d == poses[far], "intent carries sampled current target")
	poses[far] = Vector3(1, 2, 0)
	check(s.world.aggressive_intent(mob).action == "approach_player", "vertical distance prevents premature planar attack")
	poses[far] = Vector3(1.5, 0, 0)
	check(s.world.aggressive_intent(mob).action == "attack_player", "source inclusive exact attack boundary")
	poses[far] = Vector3(3, 0, 0); poses[near] = Vector3(-3, 0, 0)
	check(s.world.aggressive_intent(mob).card_id == near, "equal live distances preserve source registration order")
	poses[near] = Vector3(100, 0, 0); poses[far] = Vector3(101, 0, 0)
	check(s.world.aggressive_intent(mob).card_id == near, "source player search still ignores aggroRadius")
	poses[mob] = Vector3(8, 0, 0)
	var fights := [{"id": 42, "ongoing": true, "has_player": true, "position": Vector2(9, 0)}]
	check(s.world.aggressive_intent(mob, fights).action == "join_combat", "current actor location admits nearby fight despite distant model target")
	poses[mob] = Vector3(20, 0, 0)
	check(s.world.aggressive_intent(mob, fights).action == "approach_player", "current location excludes distant fight even with stale model geometry")
	poses[mob] = Vector3(2, 0, 0); poses[near] = Vector3(5, 0, 0); poses[far] = Vector3(50, 0, 0)
	s.ai.point_validator = func(_point, _stack): return true
	s.ai._act_aggressively(mob)
	var expected: Vector3 = poses[mob] + (poses[near] - poses[mob]).normalized() * s.ai.move_radius
	check(s.card_target_position(mob).is_equal_approx(Vector2(expected.x, expected.z)), "ground approach starts at actual pose")
	poses[mob] = Vector3(2, 2, 0)
	var flat_origin: Vector2 = s.card_target_position(mob)
	var flat_destination: Vector2 = s.card_target_position(near)
	s.ai._act_aggressively(mob)
	check(s.card_target_position(mob).is_equal_approx(flat_origin + flat_origin.direction_to(flat_destination) * s.ai.move_radius), "elevated approach explicitly preserves prior flat placement pending vertical port")
	var previous: Vector2 = s.card_target_position(mob)
	s.ai.point_validator = func(_point, _stack): return false
	s.ai._act_aggressively(mob)
	check(s.card_target_position(mob) == previous, "live pose does not bypass board rejection")
	poses[mob] = Vector3(INF, 0, 0)
	check(s.world.actor_pose(mob) == s.card_target_position_3d(mob), "nonfinite pose safely falls back")
	poses[mob] = Vector2(9, 9)
	check(s.world.actor_pose(mob) == s.card_target_position_3d(mob), "wrong pose type safely falls back")
	poses.erase(mob)
	check(s.world.actor_pose(mob) == s.card_target_position_3d(mob), "missing actor view safely falls back")
	s.world.configure(s, "Island")
	check(s.world.actor_pose_sampler == Callable(self, "sample"), "configure preserves geometry adapter across scene entry")
	check(s.world.actor_pose(-99) == Vector3.ZERO, "unknown actor does not invoke external sampler")
	test_production()
	print("AI actor pose: %d/%d passed" % [checks-failures, checks])
	quit(1 if failures else 0)

func test_production() -> void:
	var catalog = Catalog.new()
	catalog.configure({"cards": [
		{"guid": "cow", "fields": {"category": 9, "produceCard": {"guid": "milk"}, "produceInterval": 10}},
		{"guid": "milk", "fields": {"category": 3}}],
		"referenced_prefabs": [{"guid": "ai", "documents": [{"script_class": "CardAI"}]}],
		"scenes": [{"name": "Main", "documents": [{"script_class": "CardManager", "fields": {"cardPrefabs": [{"category": 9, "prefab": {"guid": "ai"}}]}}]}]})
	var s = Session.new(); s.configure(catalog, 123)
	var cow: int = s.spawn_card("cow", Vector2(8, 9))
	s.world.actor_pose_sampler = sample; poses = {cow: Vector3(2, 0, 3)}
	var captured: Array = []
	s.ai.produce_spawner = func(guid, position, ignored): captured.append([guid, position, ignored])
	s.world.production_timers[cow] = 0; s.ai.tick(0.01)
	check(captured == [["milk", Vector2(2, 3), -1]], "due production adapter receives current ground origin, not queued target")
	check(s.card_target_position(cow) == Vector2(8, 9), "sampling production origin never moves producer")
	check(s.world.production_timers[cow] == 10.0, "current origin preserves interval reset")
	poses[cow] = Vector3(2, 1, 3)
	check(s.world.production_origin(cow) == Vector2(8, 9), "elevated production keeps explicit prior planar fallback")
	poses[cow] = Vector3(INF, 0, 3)
	check(s.world.production_origin(cow) == Vector2(8, 9), "invalid production sample falls back")
	poses[cow] = Vector3(2, 0, 3); s.ai.produce_spawner = Callable()
	s.world.production_timers[cow] = 0; s.ai.tick(0.01)
	check(s.card_target_position(s.cards.keys().back()) == Vector2(2, 3), "default runtime spawn receives current ground origin")
	s.world.production_timers[cow] = 0
	var created: Array = s.world.tick_production(0.01)
	check(created.size() == 1 and s.card_target_position(created[0]) == Vector2(2, 3), "standalone world production shares same source origin")
	s.combat.dragged[cow] = true; captured.clear()
	s.ai.produce_spawner = func(guid, position, ignored): captured.append([guid, position, ignored])
	s.world.production_timers[cow] = 0; s.ai.tick(0.01)
	check(captured.is_empty(), "current pose does not bypass source CanMove drag exclusion")
