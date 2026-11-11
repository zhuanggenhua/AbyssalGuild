extends SceneTree
const Trade = preload("res://scripts/model/trade_layout.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Spawn = preload("res://scripts/model/scene_spawn.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func coin(id: int) -> Dictionary:
	return {"id": id, "category": 7, "is_chest": false, "stored_coins": 0}
func _init() -> void:
	var zone := {"kind": "vendor", "active": true, "paid": 0, "total_price": 2}
	var coins := [coin(1), coin(2), coin(3)]
	var original := coins.duplicate(true)
	var plan := Trade.payment_plan(zone, coins)
	check(plan.accepted and plan.purchased and plan.paid == 0, "Paid purchase resets installments")
	check(plan.consumed_ids == [3, 2] and plan.remaining_ids == [1], "Consume last-first, preserve excess coins")
	check(not plan.terminal and plan.stats_changed and coins == original, "Nonterminal partial stack; no mutation")
	plan = Trade.payment_plan(zone, [coin(1)])
	check(plan.accepted and not plan.purchased and plan.paid == 1 and plan.terminal, "Partial installment with emptied stack is terminal")
	var chest := {"id": 4, "category": 8, "is_chest": true, "stored_coins": 1}
	plan = Trade.payment_plan(zone, [coin(1), chest])
	check(plan.paid == 1 and plan.remaining_ids == [1, 4] and plan.stored_after[4] == 0 and not plan.terminal, "Empty last chest blocks earlier currency")
	chest.stored_coins = 5
	plan = Trade.payment_plan(zone, [coin(1), chest])
	check(plan.purchased and plan.stored_after[4] == 3 and not plan.terminal, "Purchased via chest still falls through drop actions")
	check(Trade.can_trade(zone, [coin(1)]), "Any Currency category valid regardless of GUID")
	check(not Trade.can_trade(zone, [coin(1), {"id": 5, "category": 1, "stored_coins": 9}]), "Nonchest stored amount cannot impersonate payment")
	chest.stored_coins = 0
	check(not Trade.can_trade(zone, [coin(1), chest]), "Whole stack with empty chest rejected")
	zone.active = false
	check(not Trade.payment_plan(zone, coins).accepted, "Inactive vendor rejects")
	zone.active = true
	zone.total_price = 0
	plan = Trade.payment_plan(zone, [coin(1)])
	check(plan.purchased and not plan.stats_changed and not plan.terminal, "Free pack leaves payment stack intact")
	var buyer := {"kind": "buyer", "active": true}
	check(Trade.can_trade(buyer, [chest]), "Empty chest sellable")
	chest.stored_coins = 1
	check(not Trade.can_trade(buyer, [chest]), "Nonempty chest unsellable")
	check(not Trade.can_trade(buyer, [{"is_sellable": false}]), "Unsellable card blocks entire buyer drop")
	# Pure collider tests include rotation, nonuniform scale, zero thickness and ties.
	var shape := {"index": 0, "transform": Transform3D.IDENTITY, "center": Vector3.ZERO, "local_bounds": AABB(Vector3(-0.4, 0, -0.5), Vector3(0.8, 0, 1)), "collider_enabled": true, "active": false}
	check(Trade.intersects(shape, Vector3(0.6, 0, 0), 0.25), "Raw face intersects even if center beyond radius")
	check(not Trade.intersects(shape, Vector3(0.7, 0, 0), 0.25), "No extra card margin in trade collider")
	check(not Trade.intersects(shape, Vector3(0, 0.3, 0), 0.25), "Sphere query uses height")
	var farther := shape.duplicate(true)
	farther.index = 1
	farther.center = Vector3(0.1, 0, 0)
	farther.active = true
	check(Trade.nearest_zone([shape, farther], Vector3.ZERO, 0.25).index == 0, "Nearest inactive zone chosen before validation")
	farther.center = Vector3.ZERO
	check(Trade.nearest_zone([farther, shape], Vector3.ZERO, 0.25).index == 1, "Equal center ties preserve supplied hit order")
	shape.transform = Transform3D(Basis(Vector3.UP, PI / 2).scaled_local(Vector3(2, 1, 3)), Vector3(5, 0, 6))
	shape.center = shape.transform.origin
	check(Trade.intersects(shape, Vector3(6.6, 0, 6), 0.2), "Rotated nonuniform OBB nearest face")
	shape.collider_enabled = false
	check(not Trade.intersects(shape, shape.center, 1), "Disabled collider not queried")
	var catalog := Catalog.new()
	if catalog.load_file() != OK:
		print("Trade layout: %d/%d synthetic passed; private source unavailable" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	for scene_name in ["Main", "Island"]:
		var resolved := Trade.zones(catalog, scene_name, Rect2(-6, -4, 12, 8))
		var expected := 9 if scene_name == "Main" else 2
		check(resolved.errors.is_empty() and resolved.zones.size() == expected, scene_name + " every source trade zone resolved")
		var first: Dictionary = resolved.zones[0]
		check(Vector2(first.spawn_position.x, first.spawn_position.z).is_equal_approx(Spawn.buyer_position(catalog, scene_name, Rect2(-6, -4, 12, 8))), scene_name + " buyer spawn existing API agrees")
		check(first.local_bounds.size.is_equal_approx(Vector3(0.8, 0, 1.0000004)), scene_name + " raw source collider size")
		check(first.world_bounds.size.is_equal_approx(Vector3(0.9, 0, 1.12500045)), scene_name + " zoneScale applied to collider")
		for vendor in resolved.zones.slice(1):
			check(vendor.active == (vendor.min_quests <= 0), "Quest gate derives active state")
			check(Vector2(vendor.spawn_position.x, vendor.spawn_position.z).is_equal_approx(Spawn.vendor_position(catalog, scene_name, vendor.pack_guid, Rect2(-6, -4, 12, 8))), "Vendor spawn existing API agrees")
		var vendor: Dictionary = resolved.zones[1]
		var grown := Trade.zones(catalog, scene_name, Rect2(-12, -8, 24, 16), 1.5, 999, {vendor.pack_guid: 1})
		check(grown.zones[1].active and grown.zones[1].remaining_price == grown.zones[1].total_price - 1, "Unlock and installment metadata")
		check(is_equal_approx(grown.zones[0].center.z, 7.25) and is_equal_approx(grown.zones[0].spawn_position.z, 5.85), "Grown board header and world offset")
		var sticky := Trade.zones(catalog, scene_name, null, 1.5, -1, {}, {vendor.pack_guid: true})
		check(sticky.zones[1].active, "Previously activated vendor stays active")
	# Mutate a copied source parent, not constants: world transforms must propagate.
	var transformed := Catalog.new()
	transformed.configure(catalog.data.duplicate(true))
	for scene in transformed.data.scenes:
		if scene.name != "Main": continue
		for document in scene.documents:
			if document.get("file_id", "") == "1211518933":
				document.fields.m_LocalScale = {"x": 2, "y": 1, "z": 3}
				document.fields.m_LocalRotation = {"x": 0, "y": sin(PI / 4), "z": 0, "w": cos(PI / 4)}
	var rotated := Trade.zones(transformed, "Main", Rect2(-6, -4, 12, 8))
	check(rotated.errors.is_empty(), "Orthogonal transformed parent supported")
	check(rotated.zones[0].center.is_equal_approx(Vector3(0, 0, 12.05)), "Parent scale and rotation apply to zone local center")
	check(rotated.zones[0].spawn_position.is_equal_approx(Vector3(0, 0, 10.65)), "World spawn offset is not rotated or scaled")
	check(rotated.zones[0].world_bounds.size.is_equal_approx(Vector3(3.37500135, 0, 1.8)), "Parent and zone scales affect raw collider independently")
	check(Trade.intersects(rotated.zones[0], rotated.zones[0].center + Vector3(1.8, 0, 0), 0.25), "Rotated source collider broad phase")
	var session := Session.new()
	session.configure(catalog)
	check(not Trade.card_snapshots(session, [999]).ok, "Invalid snapshot not confused with empty stack")
	var id := session.spawn_card(catalog.find_by_name("Coin"))
	var snapshot := Trade.card_snapshots(session, [id])
	check(snapshot.ok and snapshot.cards[0].category == 7, "Session payment snapshot")
	check(not Trade.zones(catalog, "missing").errors.is_empty(), "Missing scene explicit")
	print("Trade layout: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
