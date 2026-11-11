extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Spawn = preload("res://scripts/model/scene_spawn.gd")
var total := 0
var failed := 0
func check(value: bool, label: String) -> void:
	total += 1
	if not value:
		failed += 1
		push_error(label)
func sample(rng: RandomNumberGenerator) -> Vector2:
	var point := Vector3(2, 2, 2)
	while point.length_squared() > 1:
		point = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	return Vector2(point.x, point.z)
func _init() -> void:
	var catalog := Catalog.new()
	if catalog.load_file() != OK:
		print("Scene spawn: SKIP private source data unavailable")
		quit()
		return
	for scene_name in ["Main", "Island"]:
		var session := Session.new()
		session.configure(catalog, 321, scene_name)
		var defaults: Dictionary = session.campaign._defaults(scene_name)
		var refs: Array = defaults.defaultSpawnCards
		var rng := RandomNumberGenerator.new()
		rng.seed = 321
		var expected := Vector2(float(defaults.defaultSpawnPosition.x), float(defaults.defaultSpawnPosition.z)) + sample(rng) * float(defaults.defaultSpawnRadius)
		var id := session.start_new_game()
		check(id > 0, scene_name + " creates default")
		check(session.cards[id].definition_guid == catalog.ref_guid(refs[0]), scene_name + " default definition")
		check(session.cards[id].position.is_equal_approx(expected), scene_name + " source position and radius")
		check(session.rng.state == rng.state, scene_name + " preserves RNG consumption")
		check(session.cards.size() == refs.size(), scene_name + " source list count")
	var main := Session.new()
	main.configure(catalog, 876)
	var defaults: Dictionary = main.campaign._defaults("Main")
	var saved: Dictionary = defaults.duplicate(true)
	# Exercise multiple entries and source-specified non-pack defaults.
	var wood: String = catalog.find_by_name("Wood")
	defaults.defaultSpawnCards = [saved.defaultSpawnCards[0], {"guid": wood}]
	defaults.defaultSpawnPosition = {"x": 8.0, "y": 9.0, "z": -7.0}
	defaults.defaultSpawnRadius = 0.4
	var rng := RandomNumberGenerator.new()
	rng.seed = 876
	var expected_first := Vector2(8, -7) + sample(rng) * 0.4
	var expected_second := Vector2(8, -7) + sample(rng) * 0.4
	var first := main.start_new_game()
	check(main.cards.size() == 2, "Multiple default entries")
	check(main.cards[first].position.is_equal_approx(expected_first), "Changed scene center applies")
	check(main.cards.values()[1].definition_guid == wood, "Non-pack source default")
	check(main.cards.values()[1].position.is_equal_approx(expected_second), "Second random offset")
	check(main.rng.state == rng.state, "One rejection sample per default")
	defaults.defaultSpawnCards = []
	var state: int = main.rng.state
	check(main.start_new_game() == -1 and main.cards.is_empty(), "Empty defaults do not invent starter")
	check(main.rng.state == state, "Empty defaults do not draw RNG")
	defaults.clear()
	defaults.merge(saved)
	var main_packs: Array = []
	for scene in catalog.data.scenes:
		if scene.name == "Main":
			for document in scene.documents:
				if document.get("script_class", "") == "TradeManager":
					main_packs = document.fields.offeredPacks
	var pack: String = catalog.ref_guid(main_packs[0])
	check(Spawn.vendor_position(catalog, "Main", pack).is_equal_approx(Vector2(-3.3, 1.85)), "Serialized initial header placement")
	check(Spawn.vendor_position(catalog, "Main", catalog.ref_guid(main_packs[-1])).is_equal_approx(Vector2(4.4, 1.85)), "Last vendor with buyer first")
	check(Spawn.vendor_position(catalog, "Main", pack, Rect2(-12, -8, 24, 16)).is_equal_approx(Vector2(-3.3, 5.85)), "Expanded board header placement")
	check(Spawn.vendor_position(catalog, "Main", pack, Rect2(4, 10, 12, 8), 2).is_equal_approx(Vector2(6.7, 15.6)), "Translated board and custom margin")
	check(Spawn.vendor_position(catalog, "Main", "missing") == null, "Unlisted vendor unresolved")
	check(Spawn.vendor_position(catalog, "missing", pack) == null, "Missing scene unresolved")
	# Integrate whole-price and installment purchase positions without UI overrides.
	main.start_new_game()
	main.board_bounds = Rect2(-12, -8, 24, 16)
	var fields: Dictionary = catalog.fields(pack)
	var old_fields := fields.duplicate(true)
	fields.minQuests = 0
	fields.buyPrice = 2
	var coin: String = catalog.find_by_name("Coin")
	main.spawn_card(coin)
	main.spawn_card(coin)
	state = main.rng.state
	var purchased := main.buy_pack(pack)
	check(purchased > 0 and main.cards[purchased].position.is_equal_approx(Vector2(-3.3, 5.85)), "Whole-price vendor spawn")
	check(main.rng.state == state, "Buying does not draw RNG")
	var coin_id := main.spawn_card(coin)
	var payment: Dictionary = main.pay_vendor(pack, main.cards[coin_id].stack_id)
	check(payment.accepted and payment.pack_id == -1 and payment.paid == 1, "Partial payment does not spawn")
	coin_id = main.spawn_card(coin)
	payment = main.pay_vendor(pack, main.cards[coin_id].stack_id)
	check(payment.accepted and payment.pack_id > 0 and main.cards[payment.pack_id].position.is_equal_approx(Vector2(-3.3, 5.85)), "Installment vendor spawn")
	check(main.rng.state == state, "Installment does not draw RNG")
	fields.clear()
	fields.merge(old_fields)
	print("Scene spawn: %d/%d passed" % [total - failed, total])
	quit(1 if failed else 0)
