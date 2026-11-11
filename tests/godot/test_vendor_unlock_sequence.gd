extends SceneTree
const Sequence = preload("res://scripts/ui/vendor_unlock_sequence.gd")
const TradeZoneView = preload("res://scripts/ui/trade_zone_view.gd")
const CameraMotion = preload("res://scripts/ui/camera_motion.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func zone(index: int, active: bool = false, title: String = "Sample") -> Dictionary:
	return {"kind": "vendor", "index": index, "pack_guid": "pack", "active": active, "title": title, "center": Vector3(index, 0, 4)}

func same(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(a, "", true, true) == JSON.stringify(b, "", true, true)

func _init() -> void:
	_test_order_and_clock()
	_test_restore_and_interruption()
	_test_event_reentry()
	_test_pace_and_save()
	_test_highlight_view()
	print("Vendor unlock sequence: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _test_order_and_clock() -> void:
	var sequence := Sequence.new()
	var starts: Array = []
	var finishes: Array = []
	sequence.sequence_started.connect(func(value): starts.append(value))
	sequence.sequence_finished.connect(func(value): finishes.append(value))
	sequence.restore([zone(1, true, "Initial"), zone(2), zone(3)])
	check(not sequence.is_active() and starts.is_empty(), "Initially available vendor is silent")
	var zones: Array = [zone(1, true, "Initial"), zone(2, true, "Second"), zone(3, true, "Third"), {"kind": "buyer", "index": 0, "active": true}]
	sequence.update_zones(zones)
	check(starts.is_empty(), "UI synchronization alone cannot trigger a reveal")
	sequence.on_quest_completed(zones)
	check(sequence.is_active() and sequence.stage == "focus" and sequence.remaining == 0.5, "Quest starts exact source half-second camera move")
	check(starts.size() == 1 and starts[0].index == 2 and sequence.pending == [3], "New vendors queue in offered order; buyer and initial vendor skipped")
	check(sequence.info() == {"header": "Pack Unlocked", "body": "You can buy Second card pack here."}, "Source unlock header and vendor body")
	sequence.on_quest_completed(zones)
	check(sequence.pending == [3] and starts.size() == 1, "Repeated and nested quest events cannot duplicate queued vendors")
	for invalid in [0.0, -1.0, NAN, INF]: sequence.advance(invalid)
	check(sequence.remaining == 0.5, "Nonpositive/nonfinite frame cannot advance or poison timer")
	sequence.advance(0.25)
	check(sequence.stage == "focus" and sequence.remaining == 0.25, "Focus uses realtime halves")
	sequence.advance(5.0)
	check(sequence.stage == "hold" and sequence.remaining == 2.0 and finishes.is_empty(), "Oversized focus frame retains complete two-second wait")
	sequence.advance(1.99)
	check(sequence.is_active() and finishes.is_empty(), "Full two seconds elapse after focus")
	zones[2].center = Vector3(8, 0, 9)
	sequence.update_zones(zones)
	sequence.advance(0.01)
	check(finishes.size() == 1 and finishes[0].index == 2 and starts.size() == 2 and starts[1].index == 3, "Cleanup precedes next reveal")
	check(sequence.remaining == 0.5 and sequence.current.center == Vector3(8, 0, 9), "Queued vendor samples latest bounds and has a fresh focus wait")
	sequence.advance(0.5)
	sequence.advance(2.0)
	check(not sequence.is_active() and sequence.pending.is_empty() and sequence.info().is_empty() and finishes.size() == 2, "Queue drains with no leftover pause/info ownership")
	sequence.on_quest_completed(zones)
	check(starts.size() == 2 and not sequence.is_active(), "Later quests do not replay previous reveals")
	# Distinct vendor objects may offer the same pack. Key by scene zone, not GUID.
	sequence.restore([zone(4), zone(5)])
	sequence.on_quest_completed([zone(4, true), zone(5, true)])
	check(sequence.current.index == 4 and sequence.pending == [5], "Same-pack vendor instances each reveal once")

func _test_restore_and_interruption() -> void:
	var sequence := Sequence.new()
	var finished: Array = []
	sequence.sequence_finished.connect(func(value): finished.append(value.index))
	sequence.restore([zone(1), zone(2)])
	sequence.on_quest_completed([zone(1, true), zone(2, true)])
	sequence.cancel()
	sequence.cancel()
	sequence.advance(50)
	check(finished == [1] and not sequence.is_active() and sequence.pending.is_empty(), "Title/destroy cancellation clears queue and releases active reveal once")
	sequence.restore([zone(1, true), zone(2, true)])
	sequence.on_quest_completed([zone(1, true), zone(2, true)])
	check(not sequence.is_active(), "Restore does not replay completed quest unlocks or ephemeral saved queue")
	sequence.restore([zone(1)])
	sequence.on_quest_completed([zone(1, true)])
	check(sequence.is_active(), "Fresh scene baseline does not inherit prior scene zone IDs")
	sequence.restore([zone(9, true)])
	check(not sequence.is_active() and finished == [1, 1], "Rebind interrupts old sequence before establishing silent new baseline")
	sequence.restore([zone(1), zone(2)])
	sequence.on_quest_completed([zone(1, true), zone(2, true)])
	sequence.update_zones([zone(1, true)])
	sequence.advance(0.5)
	sequence.advance(2.0)
	check(not sequence.is_active() and sequence.pending.is_empty(), "Removed queued zone cannot leave a lock behind")

func _test_event_reentry() -> void:
	var sequence := Sequence.new()
	var starts: Array = []
	var zones: Array = [zone(1, true), zone(2, true)]
	var on_start := func(value):
		starts.append(value.index)
		sequence.on_quest_completed(zones)
	sequence.sequence_started.connect(on_start)
	sequence.restore([zone(1), zone(2)])
	sequence.on_quest_completed(zones)
	check(starts == [1] and sequence.pending == [2], "Synchronous start listener reentry does not duplicate activations")
	var on_finish := func(_value): sequence.restore([zone(8, true)])
	sequence.sequence_finished.connect(on_finish)
	sequence.advance(0.5)
	sequence.advance(2.0)
	check(not sequence.is_active() and starts == [1] and sequence.pending.is_empty(), "Finish listener scene rebind cannot start stale queue")
	sequence.sequence_started.disconnect(on_start)
	sequence.sequence_finished.disconnect(on_finish)

func _test_pace_and_save() -> void:
	var catalog := Catalog.new()
	catalog.configure({"cards": [], "recipes": [], "scenes": [{"name": "Main", "documents": []}]})
	var session := Session.new()
	session.configure(catalog, 91)
	session.speed = 2.0
	session.elapsed = 17.0
	var baseline: Dictionary = Codec.capture(session)
	var sequence := Sequence.new()
	sequence.restore([zone(1)])
	sequence.on_quest_completed([zone(1, true)])
	var camera := CameraMotion.new()
	var current := Vector3(0, 10, 4)
	camera.configure(current)
	camera.move_to(current, sequence.current.center, Vector3(0, -1, 0), Sequence.FOCUS_SECONDS)
	# External pause is a composition of owners, never a write to user pace.
	var menu_paused: bool = true
	var cycle_paused: bool = true
	for delta in [0.5, 2.0]:
		var external_pause: bool = menu_paused or sequence.is_active()
		if external_pause:
			session.combat.tick(0, delta)
			session.cycle.advance(delta)
		else: session.tick(delta)
		current = camera.step(current, delta, not sequence.is_active())
		sequence.advance(delta)
	check(same(Codec.capture(session), baseline), "Reveal pause never changes saved pace, time, RNG or model state")
	check(menu_paused and cycle_paused and not sequence.is_active(), "Cleanup removes only reveal ownership, preserving other pause owners")
	check(current == Vector3(1, 8, 4), "Unscaled camera finishes despite world-input and gameplay pause")
	check(session.speed == 2.0 and not session.paused, "Fast selected pace survives complete sequence")
	session.paused = true
	baseline = Codec.capture(session)
	sequence.restore([zone(1)])
	sequence.on_quest_completed([zone(1, true)])
	sequence.advance(0.5)
	sequence.advance(2.0)
	check(same(Codec.capture(session), baseline) and session.paused, "Manually paused pace also survives complete sequence")
	check(not baseline.has("vendor_unlock") and not baseline.session.has("vendor_unlock"), "No ephemeral reveal fields enter native save schema")

func _test_highlight_view() -> void:
	var view := TradeZoneView.new()
	var shape: Dictionary = zone(1, true)
	shape["transform"] = Transform3D(Basis.IDENTITY, shape.center)
	shape["local_bounds"] = AABB(Vector3(-0.4, 0, -0.5), Vector3(0.8, 0, 1))
	shape["price_text"] = "Price: 3"
	view.configure(shape, "1 / 4 found")
	check(not view.highlighted and not view.highlight_outline.visible, "Trade outline starts hidden")
	view.set_highlighted(true)
	check(view.highlighted and view.highlight_outline.visible and view.highlight_outline.mesh.get_surface_count() == 1, "Unlock owns a visible independent outline")
	shape.center = Vector3(3, 0, 8)
	shape["transform"].origin = shape.center
	view.configure(shape, "2 / 4 found")
	check(view.highlighted and view.highlight_outline.visible and view.position == Vector3(3, 0, -8), "Collection/layout refresh preserves outline and source-space reflection")
	view.set_highlighted(false)
	check(not view.highlight_outline.visible and view.caption.text.contains("2 / 4 found"), "Reveal cleanup hides outline without deleting current caption")
	view.free()
