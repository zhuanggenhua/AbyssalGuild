extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func _init() -> void:
	var catalog = Catalog.new()
	check(catalog.load_file() == OK, "private source catalog required")
	for kind in ["ground", "elevated", "invalid", "missing", "singleton"]:
		var s = Session.new(); s.configure(catalog, 123)
		var cow: int = s.spawn_card(catalog.find_by_name("Cow"), Vector2(5, 5))
		var other: int = s.spawn_card(catalog.find_by_name("Cow"), Vector2(8, 5))
		if kind != "singleton": check(s.move_to_stack(other, s.cards[cow].stack_id), "source Cow stack allowed")
		var old = s.stacks[s.cards[cow].stack_id]
		var samples: Array = []
		s.world.actor_pose_sampler = func(id):
			samples.append([id, old.card_ids.duplicate()])
			match kind:
				"ground", "singleton": return Vector3(-2, 0, 1)
				"elevated": return Vector3(-2, 0.002, 1)
				"invalid": return Vector3(INF, 0, 1)
			return null
		s.ai._detach(cow)
		if kind == "singleton":
			check(samples.is_empty() and s.cards[cow].stack_id == old.id and old.position == Vector2(5, 5), "singleton never samples or relocates")
			continue
		check(samples == [[cow, [cow, other]]], "pose sampled before any stack membership mutation")
		check(s.card_target_position(cow) == (Vector2(-2, 1) if kind == "ground" else Vector2(5, 5)), "only established ground origin replaces settled fallback: " + kind)
		check(old.card_ids == [other] and old.position == Vector2(5, 5), "source remaining stack stays at previous target")
	print("AI detach pose: %d/%d passed" % [checks-failures, checks])
	quit(1 if failures else 0)
