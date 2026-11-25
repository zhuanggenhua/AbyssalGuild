extends SceneTree
## Actual Godot mixer PCM from the two licensed trade clips. Dummy output is
## allowed: this measures the engine bus, not speakers or Unity waveforms.
const Board = preload("res://scripts/ui/board.gd")
const BUS_NAMES := {"Puff": &"TradeProbePuff", "CashRegister": &"TradeProbeRegister"}

class MixerWitness extends "res://scripts/ui/audio_feedback.gd":
	var attempts: Array[Dictionary] = []
	var state: Callable
	var probe_buses: Dictionary
	func play_music() -> bool: return false # Keep BGM out of this test only.
	func play_event(name: String) -> bool:
		var voice := pool[next_player] if not pool.is_empty() else null
		# Fresh unused base slots only. Production playback, stream lookup,
		# per-Id clocks, voice admission, gain and pitch are not mocked.
		if is_instance_valid(voice) and not voice.playing:
			voice.bus = probe_buses.get(name, &"Master")
		var admitted := super.play_event(name)
		attempts.append({"name":name,"admitted":admitted,"state":state.call() if state.is_valid() else {},
			"bus":voice.bus if voice!=null else &"", "frame":Engine.get_process_frames()})
		return admitted

var checks := 0
var failures := 0
var meters: Dictionary = {}

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func make_meters() -> void:
	for cue in BUS_NAMES:
		var index := AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(index, BUS_NAMES[cue])
		AudioServer.set_bus_send(index, &"Master")
		var capture := AudioEffectCapture.new()
		capture.buffer_length = 2.0
		AudioServer.add_bus_effect(index, capture)
		meters[cue] = capture

func reset_meters() -> void:
	for meter in meters.values(): meter.clear_buffer()

func read_meters() -> Dictionary:
	var out := {}
	for cue in meters:
		var meter: AudioEffectCapture = meters[cue]
		var pcm := meter.get_buffer(meter.get_frames_available())
		var max_sample := 0.0
		var nonzero := 0
		for value in pcm:
			var level := maxf(absf(value.x),absf(value.y))
			if level > 0.00001: nonzero += 1
			max_sample = maxf(max_sample, level)
		out[cue] = {"frames":pcm.size(),"peak":max_sample,"nonzero":nonzero,"discarded":meter.get_discarded_frames()}
	return out

func drag_to_zone(board: Board, id: int, zone: Dictionary) -> void:
	var press := InputEventMouseButton.new()
	press.button_index=MOUSE_BUTTON_LEFT; press.pressed=true
	press.position=board.camera.unproject_position(board.views[id].global_position)
	board._unhandled_input(press)
	check(board.dragging==id and board.session.drag.active_for(id), "picked actual card from Board physics")
	var at: Vector3 = zone.center
	var position := board.camera.unproject_position(Vector3(at.x,0,-at.z))
	var motion := InputEventMouseMotion.new()
	motion.position=position
	motion.relative=position-press.position
	board._input(motion)
	check(board.drag_moved, "pointer entered physical trade zone as a drag")
	var release := InputEventMouseButton.new()
	release.position=position; release.button_index=MOUSE_BUTTON_LEFT
	board._input(release)

func trade_attempts(audio: MixerWitness) -> Array:
	return audio.attempts.filter(func(row): return BUS_NAMES.has(row.name))

func finish(board: Board, status := "") -> void:
	board.feedback.shutdown()
	board.queue_free()
	await process_frame
	await create_timer(.25).timeout
	for name in BUS_NAMES.values():
		var index := AudioServer.get_bus_index(name)
		if index>=0: AudioServer.remove_bus(index)
	if not status.is_empty(): print(status)
	else: print("Trade mixer Board: %d/%d (%s output, Godot PCM, no speaker claim)" % [
		checks-failures, checks, AudioServer.get_driver_name()])
	quit(0 if failures==0 else 1)

func run() -> void:
	var board := Board.new()
	board.feedback.free()
	var audio := MixerWitness.new()
	audio.probe_buses = BUS_NAMES
	board.feedback=audio
	board.slot_root="user://trade-pcm-%d" % Time.get_ticks_usec()
	board.options_path=board.slot_root+"/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	check(board.data_error==OK, "locked original data loaded")
	if board.data_error!=OK:
		await finish(board)
		return
	if board.visual_assets.manifest.get("assets",{}).is_empty():
		await finish(board,"SKIP trade mixer requires private imported source media")
		return
	check(audio.cooldown==0.05 and audio.pool.size()==8 and not audio.source_settings.get("_randomizeSFXPitch",true),
		"source prefab cooldown, slot count, and pitch")
	var puff := audio.stream_for_event("Puff")
	var register := audio.stream_for_event("CashRegister")
	check(puff!=null and register!=null and puff!=register, "distinct original Puff and CashRegister clips resolve")
	if puff==null or register==null:
		await finish(board)
		return
	make_meters()
	board.start_new(); board.set_process(false)
	for id in board.session.cards.keys(): board.session._remove_card(id)
	for id in board.session.quest_tracker.definitions: board.session.quest_tracker.completed_ids[id]=true
	board.session.vendor_payments.clear()
	board._refresh(); board.vendor_unlock.cancel()
	var vendor: Dictionary = board.trade_zones[1]
	var price: int = int(vendor.total_price)
	check(vendor.active and price>=3, "original vendor admits a two-coin installment")
	var offer: String = str(vendor.pack_guid)
	var previously_paid := price - 3
	board.session.vendor_payments[offer] = previously_paid
	board._refresh()
	vendor = board.trade_zones[1]
	var id: int = board.session.spawn_card(board.catalog.find_by_name("Card_Chest_WoodenChest"),
		Vector2.ZERO,-1,{"refuse_attach":true})
	board.session.cards[id].stored_coins=2
	board._refresh(); board._clear_puffs()
	await physics_frame; await physics_frame
	# Wait out startup requests, then isolate PCM from this physical drop.
	await create_timer(.7).timeout
	reset_meters()
	audio.attempts.clear()
	var chest_view = board.views[id]
	check(chest_view.stat_labels.has("price"), "actual chest price label is bound")
	var card_ids_before: Array = board.session.cards.keys()
	audio.state=func():
		return [board.session.cards[id].stored_coins if board.session.cards.has(id) else -1,
			chest_view.stat_labels.price.text if chest_view.stat_labels.has("price") else "",
			board.trade_views[1].zone_snapshot.price_text]
	drag_to_zone(board,id,vendor)
	var trace := trade_attempts(audio)
	check(trace.map(func(row): return row.name)==["Puff","Puff","Puff","CashRegister"],
		"zone, 2 withdrawals and register are distinct logical requests")
	check(trace.map(func(row): return row.admitted)==[true,false,false,true],
		"per-AudioId cooldown admits one Puff and one independent register")
	check(trace.map(func(row): return row.state)==[[2,"2","Price: 3"],[1,"1","Price: 3"],
		[0,"0","Price: 3"],[0,"0","Price: 1"]],
		"register starts after balance and visible price refresh")
	check(trace.all(func(row): return row.frame==Engine.get_process_frames()), "all four requests in one process frame")
	check(board.puffs.size()==3 and board.session.vendor_payments.get(offer,0)==previously_paid+2 and board.session.cards[id].stored_coins==0,
		"three actual puff nodes and correct retained chest/payment")
	check(board.session.cards.keys() == card_ids_before, "partial chest payment spawns neither a board coin nor a pack")
	check(not audio.attempts.any(func(row): return row.name in ["Coin", "Coins"]), "vendor withdrawal has no standalone coin cue")
	await create_timer(.28).timeout
	var accepted := read_meters()
	for cue in accepted:
		var stats: Dictionary = accepted[cue]
		check(stats.frames>1000 and stats.discarded==0 and stats.nonzero>100 and stats.peak>0.001,
			cue+" produced nonzero PCM on its own bus without overflow")
	print("ACCEPTED MIXER ", accepted)
	await create_timer(maxf(puff.get_length(),register.get_length())+.15).timeout
	reset_meters(); audio.attempts.clear()
	id=board.session.spawn_card(board.catalog.find_by_name("Wood"),Vector2.ZERO,-1,{"refuse_attach":true})
	board._refresh()
	await physics_frame; await physics_frame
	drag_to_zone(board,id,vendor)
	check(audio.attempts.any(func(row):return row.name=="CardDrop"), "rejected item still releases via ordinary drag feedback")
	check(trade_attempts(audio).is_empty() and board.session.vendor_payments.get(offer,0)==previously_paid+2,
		"rejected item cannot request either trade cue or change payment")
	await create_timer(.2).timeout
	var rejected := read_meters()
	for cue in rejected:
		check(rejected[cue].frames>1000 and rejected[cue].nonzero==0 and rejected[cue].discarded==0, cue+" bus remains silent for rejected drop")
	print("REJECTED MIXER ", rejected)
	audio.state=Callable()
	await finish(board)
