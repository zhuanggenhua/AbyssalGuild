extends SceneTree
## Actual viewport/collider route with injected mouse records, not hardware.
const Board = preload("res://scripts/ui/board.gd")
const DragInput = preload("res://scripts/ui/card_drag_input.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
class QuietAudio extends "res://scripts/ui/audio_feedback.gd":
	var calls: Array[String] = []
	func play_event(kind: String) -> bool:
		calls.append(kind)
		return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)

func pointer(point: Vector2, down: Variant = null, device := 0) -> void:
	var event: InputEvent
	if down == null:
		event=InputEventMouseMotion.new()
	else:
		event=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
	event.device=device
	event.position=point
	root.push_input(event,true)

func spawn(b, label: String, at: Vector2) -> int:
	return b.session.spawn_card(b.catalog.find_by_name(label),at,-1,{"refuse_attach":true})

func start_portal(b) -> bool:
	var gate := spawn(b,"Grand Portal",Vector2(3,-1))
	var worker := spawn(b,"Villager",Vector2(3,-2))
	return b.session.move_to_stack(worker,b.session.cards[gate].stack_id) and b.session.crafting.advance(5) and b.session.travel_pending

func clear_board(b) -> void:
	b.vendor_unlock.cancel()
	b.session.cycle.reset()
	b.session.phase="playing"
	b.session.paused=false
	for id in b.session.cards.keys(): b.session._remove_card(id)
	b.session.spawn_target_selector=Callable()
	b.session.spawn_layout_resolver=Callable()
	b._refresh()

func reachable(b,id: int) -> Vector2:
	var center: Vector3=b.views[id].global_position
	for z in range(-30,31):
		var point: Vector2=b.camera.unproject_position(center+Vector3(0,0,z*.025))
		if b._pick(point)==id and root.get_visible_rect().has_point(point): return point
	return Vector2.INF

func row(snapshot: Dictionary, id: int) -> Dictionary:
	for data: Dictionary in snapshot.get("session",{}).get("cards",[]):
		if data.id==id: return data
	return {}

func exercise(origin: String, release_in_fade: bool) -> void:
	var b := Board.new()
	b.feedback.free()
	var audio := QuietAudio.new()
	b.feedback=audio
	var target := "user://source-fade-card-%d"%Time.get_ticks_usec()
	b.slot_root=target+"/slots"
	b.options_path=target+"/options.json"
	b.legacy_paths.clear()
	root.add_child(b)
	await process_frame
	check(b.data_error==OK,"locked source data loaded")
	if b.data_error!=OK: b.queue_free(); return
	b.start_new()
	b.set_process(false)
	clear_board(b)
	if origin=="Island":
		check(start_portal(b),"arrive Island through original gate")
		b._process(1)
		b._process(1)
		clear_board(b)
	check(b.session.scene_name==origin,"depart expected original scene")
	b.camera.position=Vector3(0,12,1)
	b.camera_motion.configure(b.camera.position)
	b._clamp_camera()
	var wood:=spawn(b,"Wood",Vector2(-2,-.8))
	var stone:=spawn(b,"Stone",Vector2(1,-1.8))
	b._refresh()
	await physics_frame
	await process_frame
	var pick:=reachable(b,wood)
	var other:=reachable(b,stone)
	check(pick.is_finite() and other.is_finite(),"real source colliders are pickable")
	if not pick.is_finite() or not other.is_finite(): b.queue_free(); return
	pointer(pick)
	pointer(pick,true)
	b._process(.04)
	check(b.dragging==wood and b.session.drag.active_for(wood) and audio.calls.count("CardPick")==1,
		"left Down captures ordinary old receiver through production viewport")
	if b.dragging!=wood: b.queue_free(); return
	var pre_point:=pick+Vector2(-28,0)
	pointer(pre_point)
	b._process(.03)
	var old=b.session
	var saved_pos: Vector2=old.cards[wood].position
	var old_view: WeakRef = weakref(b.views[wood])
	check(start_portal(b),"ordinary source Grand Portal request snapshots before fade")
	check(b.scene_transition.phase=="out" and b.scene_transition.blocks_input() and b._outbound_mouse_hold.get("id")==wood,
		"genuine old capture authorized without opening fresh input")
	var capture: String=FileAccess.get_sha256(b._active_slot_path())
	var save: Variant=JSON.parse_string(FileAccess.get_file_as_string(b._active_slot_path()))
	check(save is Dictionary and not capture.is_empty(),"read actual isolated departure save")
	if not save is Dictionary or b.scene_transition.phase!="out": b.queue_free(); return
	var saved_row:=row(save.scenes[origin],wood)
	check(not saved_row.is_empty() and Vector2(saved_row.position[0],saved_row.position[1]).is_equal_approx(saved_pos)
		and save.scenes[origin].session.cards.size()==2,"source checkpoint retains held target and excludes travelers")
	var bound: Array=b.scene_transition._commit.get_bound_arguments()
	var candidate=bound[1]
	var frozen:=Codec.capture(candidate)
	var frozen_elapsed: float=old.elapsed
	var during:=pre_point+Vector2(-19,-28)
	pointer(during)
	b._process(.15)
	var rendered: Vector3=b.views[wood].global_position
	var landed:=Vector2(rendered.x,-rendered.z)
	check(b.session==old and b.scene_transition.phase=="out" and is_equal_approx(old.elapsed,frozen_elapsed)
		and not landed.is_equal_approx(saved_pos) and landed.is_equal_approx(old.cards[wood].position),
		"mouse follows while old scene still exists but scaled time is paused")
	check(FileAccess.get_sha256(b._active_slot_path())==capture and Codec.capture(candidate)==frozen,
		"outgoing movement leaves existing file and destination candidate unchanged")
	if release_in_fade:
		var up:=other+Vector2(55,-23)
		check(not b._board_point(up).is_equal_approx(landed),"release coordinates deliberately differ")
		pointer(up,false,InputEvent.DEVICE_ID_EMULATION)
		check(b.dragging==wood and audio.calls.count("CardDrop")==0,"emulated up does not claim physical capture")
		pointer(up,false)
		check(b.dragging<0 and not old.drag.active() and old.combat.dragged.is_empty()
			and audio.calls.count("CardDrop")==1 and old.cards[wood].position.is_equal_approx(landed),
			"ordinary Up commits last drawn pose once; clears exact hold")
		pointer(up,false)
		pointer(other,true)
		pointer(other,false)
		b._process(.1)
		check(b.dragging<0 and audio.calls.count("CardPick")==1 and audio.calls.count("CardDrop")==1,
			"fresh Down through fade and duplicate Up never target another card")
		check(FileAccess.get_sha256(b._active_slot_path())==capture and Codec.capture(candidate)==frozen,
			"outgoing drop never writes a second save or mutates frozen traveler candidate")
	else:
		check(b.dragging==wood and audio.calls.count("CardDrop")==0,"leave the old physical press down at black")
	b._process(1)
	await process_frame
	check(b.session==candidate and b.scene_transition.phase=="in" and b.dragging<0
		and not b.session.drag.active() and b._outbound_mouse_hold.is_empty() and old_view.get_ref()==null,
		"black swaps owner and destroys old capture and receiver")
	check(FileAccess.get_sha256(b._active_slot_path())==capture and Codec.capture(candidate).session.cards.size()==frozen.session.cards.size(),
		"arrival does not overwrite departure file, nor duplicate travelers")
	pointer(other,false)
	b._process(.1)
	check(b.dragging<0 and audio.calls.count("CardDrop")==int(release_in_fade),
		"old Up after swap cannot drop a new or numerically reused card")
	b.queue_free()
	await process_frame

# Use the normal source factory for world placement and read its raw query
# before attachment; do not replace it with a fake standalone spawn.
func chest_exercise(scene_name: String, merge_currency: bool, short_drag: bool) -> void:
	var b := Board.new()
	b.feedback.free()
	var audio := QuietAudio.new()
	b.feedback=audio
	var target := "user://source-fade-chest-%d"%Time.get_ticks_usec()
	b.slot_root=target+"/slots"
	b.options_path=target+"/options.json"
	b.legacy_paths.clear()
	root.add_child(b)
	await process_frame
	check(b.data_error==OK,"locked chest data loaded")
	if b.data_error!=OK: b.queue_free(); return
	b.start_new()
	b.set_process(false)
	clear_board(b)
	if scene_name=="Island":
		check(start_portal(b),"proper Grand Portal takes fixture to Island")
		b._process(1)
		b._process(1)
		clear_board(b)
	var old=b.session
	check(old.scene_name==scene_name,"chest uses the active board")
	var currency: String=old.world.currency_guid
	# Resolve the exact authored TradeManager reference, not the English noun.
	var manager_currency := ""
	for scene: Dictionary in b.catalog.data.scenes:
		if scene.name==scene_name:
			for doc: Dictionary in scene.documents:
				if doc.get("script_class")=="TradeManager":
					manager_currency=b.catalog.ref_guid(doc.fields.currencyCard)
	check(not currency.is_empty() and currency==manager_currency,"local scene TradeManager currency is bound")
	b.camera.position=Vector3(0,12,1)
	b.camera_motion.configure(b.camera.position)
	b._clamp_camera()
	var chest:=spawn(b,"Card_Chest_WoodenChest",Vector2(-2,-.8))
	var deposit: int=old.spawn_card(currency,Vector2(-1,-2.8),-1,{"refuse_attach":true})
	var chest_stack: int=old.cards[chest].stack_id
	check(old.move_to_stack(deposit,chest_stack) and not old.cards.has(deposit) and old.cards[chest].stored_coins==1,
		"load one coin using ChestLogic stacking, not a test balance setter")
	var width: float=b._card_footprint(chest).x
	var loose: int=-1
	var loose_stack: int=-1
	if merge_currency:
		loose=old.spawn_card(currency,Vector2(-2+width+.12,-.8),-1,{"refuse_attach":true})
		loose_stack=old.cards[loose].stack_id
	b._refresh()
	await physics_frame
	await process_frame
	var pick:=reachable(b,chest)
	check(pick.is_finite(),"the original Wooden Chest collider can receive mouse Down")
	if not pick.is_finite(): b.queue_free(); return
	audio.calls.clear()
	pointer(pick)
	pointer(pick,true)
	b._process(.04)
	check(b.dragging==chest and old.drag.active_for(chest) and audio.calls==["CardPick"],"a real press captures only this Wooden Chest")
	if b.dragging!=chest: b.queue_free(); return
	var down: Vector3=b.drag_start_position
	var at_down:=Vector2(down.x,down.z)
	var currency_before := 1 if merge_currency else 0
	check(start_portal(b),"real Grand Portal begins outbound with held chest")
	check(b.scene_transition.phase=="out" and b._outbound_mouse_hold.get("id")==chest,"authored chest is retained without granting fresh input")
	if b.scene_transition.phase!="out": b.queue_free(); return
	var file: String=b._active_slot_path()
	var sha:=FileAccess.get_sha256(file)
	var save: Variant=JSON.parse_string(FileAccess.get_file_as_string(file))
	check(save is Dictionary and not sha.is_empty(),"retrieve actual isolated departure save")
	if not save is Dictionary: b.queue_free(); return
	var saved: Dictionary=save.scenes[scene_name]
	var saved_chest:=row(saved,chest)
	check(saved_chest.get("stored_coins")==1 and saved.session.cards.size()==1+currency_before,
		"departure excludes both travelers and has the pre-withdrawal chest balance")
	var candidate_args: Array=b.scene_transition._commit.get_bound_arguments()
	var candidate=candidate_args[1]
	var frozen:=Codec.capture(candidate)
	var traces: Array[Dictionary]=[]
	var events: Array[String]=[]
	var created: Array[int]=[]
	var puff_poses: Array[Vector3]=[]
	old.event_occurred.connect(func(kind, payload):
		if kind=="puff_requested" and payload.card_id==chest:
			events.append("puff"); puff_poses.append(payload.position)
		if kind=="card_created" and payload.base_definition_guid==currency:
			events.append("coin"); created.append(payload.card_id))
	old.spawn_target_selector=func(id, ignored):
		var selected: int=b._select_spawn_target(id,ignored)
		if old.cards[id].base_definition_guid==currency: traces.append({"point":old.cards[id].position,"ignored":ignored,"selected":selected})
		return selected
	old.spawn_layout_resolver=b._resolve_layout
	var threshold:=float(DragInput.source_settings(b.catalog,scene_name).get("clickThreshold",.02))
	var original: Vector3=b.views[chest].global_position
	var shift: float=threshold*.45 if short_drag else threshold*4
	var screen_shift: Vector2=b.camera.unproject_position(original+Vector3(shift,0,0))-b.camera.unproject_position(original)
	pointer(pick+screen_shift)
	b._process(.08)
	var draw: Vector3=b.views[chest].global_position
	var rendered:=Vector2(draw.x,-draw.z)
	check(rendered.distance_to(at_down)>.0005 and DragInput.is_click(down,rendered,DragInput.source_settings(b.catalog,scene_name))==short_drag,
		"last rendered pose moved nonzero, on the intended side of the exact click threshold")
	var up:=pick+Vector2(170,35)
	check(b._board_point(up).distance_to(rendered)>threshold*4,"physical Up screen ray is far outside the click threshold")
	var clock: float=old.elapsed
	pointer(up,false,InputEvent.DEVICE_ID_EMULATION)
	check(b.dragging==chest and created.is_empty(),"touch-mouse emulation cannot discharge captured chest")
	pointer(up,false)
	check(b.dragging<0 and not old.drag.active() and b._outbound_mouse_hold.is_empty(),"exact receiver releases, no residual hold")
	if short_drag:
		check(old.cards[chest].stored_coins==0 and old.card_target_position(chest).is_equal_approx(at_down)
			and old.cards[chest].stack_id==chest_stack,"successful click returns same chest to its press target")
		check(audio.calls==["CardPick","CardDrop","Puff","Coin"] and events==["puff","coin"],"one drop, puff, create and withdrawal sound in source order")
		check(puff_poses.size()==1 and puff_poses[0].is_equal_approx(Vector3(draw.x,draw.y,-draw.z)),
			"source puff uses the rendered chest position before it returns")
		check(traces.size()==1 and traces[0].point.is_equal_approx(rendered+Vector2(width,0)) and traces[0].ignored==chest_stack,
			"raw coin factory query uses rendered pose plus chest width and excludes only withdrawing chest")
		if created.size()==1 and old.cards.has(created[0]):
			var coin_stack: int=old.cards[created[0]].stack_id
			check((merge_currency and coin_stack==loose_stack and old.stacks[loose_stack].card_ids==[loose,created[0]])
				or (not merge_currency and old.stacks[coin_stack].card_ids==[created[0]]),
				"new regional coin uses real factory stacking when a compatible loose pile is present")
		else: check(false,"one live newly created currency card")
	else:
		check(old.cards[chest].stored_coins==1 and old.card_target_position(chest).is_equal_approx(rendered)
			and audio.calls==["CardPick","CardDrop"] and events.is_empty() and traces.is_empty(),
			"above-threshold release uses regular drop, not chest withdrawal")
	pointer(up,false)
	pointer(pick,true)
	pointer(pick,false)
	check(audio.calls.count("CardDrop")==1 and created.size()==int(short_drag) and is_equal_approx(old.elapsed,clock),
		"duplicate and fresh faded edges neither move time nor repeat effects")
	check(FileAccess.get_sha256(file)==sha and Codec.capture(candidate)==frozen,"departing chest cannot rewrite frozen save or future world")
	b._process(1)
	await process_frame
	check(b.session==candidate and b.scene_transition.phase=="in" and b.dragging<0 and FileAccess.get_sha256(file)==sha,
		"arrival consumes staged world, not the post-save chest transaction")
	pointer(up,false)
	check(audio.calls.count("Coin")==int(short_drag) and b._outbound_mouse_hold.is_empty(),"stale Up after swap cannot target replacement world")
	old.spawn_target_selector=Callable()
	old.spawn_layout_resolver=Callable()
	b.queue_free()
	await process_frame

func pack_exercise(scene_name: String, prior_draws: int) -> void:
	var b := Board.new()
	b.feedback.free()
	var audio := QuietAudio.new()
	b.feedback=audio
	var target := "user://source-fade-pack-%d"%Time.get_ticks_usec()
	b.slot_root=target+"/slots"
	b.options_path=target+"/options.json"
	b.legacy_paths.clear()
	root.add_child(b)
	await process_frame
	check(b.data_error==OK,"locked regional pack data loaded")
	if b.data_error!=OK: b.queue_free(); return
	b.start_new()
	b.set_process(false)
	clear_board(b)
	if scene_name=="Island":
		check(start_portal(b),"proper Grand Portal takes pack fixture to Island")
		b._process(1)
		b._process(1)
		clear_board(b)
	var old=b.session
	check(old.scene_name==scene_name,"depart expected regional pack board")
	var first_world := scene_name=="Main"
	var pack_name := "00_Pack_Starter" if first_world else "10_Pack_Island"
	var pack: int=old.spawn_card(b.catalog.find_by_name(pack_name,"packs"),Vector2(-2,-.8),-1,{"refuse_attach":true})
	check(old.cards.has(pack),"authored regional pack loaded through its normal factory")
	if not old.cards.has(pack): b.queue_free(); return
	var pack_stack: int=old.cards[pack].stack_id
	for i in prior_draws:
		var drawn: int=old.open_pack(pack)
		check(drawn>=0 and old.cards.has(drawn),"consume an earlier genuine slot")
		if old.cards.has(drawn): old._remove_card(drawn)
	var remaining: int=old.cards[pack].uses_left
	check(remaining==(4 if first_world else 5)-prior_draws,"no direct setting of pack progress")
	b._refresh()
	await physics_frame
	await process_frame
	var pick:=reachable(b,pack)
	check(pick.is_finite(),"the authored Pack collider can receive physical Down")
	if not pick.is_finite(): b.queue_free(); return
	audio.calls.clear()
	pointer(pick)
	pointer(pick,true)
	b._process(.04)
	check(b.dragging==pack and old.drag.active_for(pack),"native viewport captures the real pack receiver")
	if b.dragging!=pack: b.queue_free(); return
	check(start_portal(b) and b._outbound_mouse_hold.get("id")==pack,
		"original portal keeps exact captured regional pack")
	if b.scene_transition.phase!="out": b.queue_free(); return
	var file: String=b._active_slot_path()
	var sha:=FileAccess.get_sha256(file)
	var save: Variant=JSON.parse_string(FileAccess.get_file_as_string(file))
	if not save is Dictionary: check(false,"departure save missing"); b.queue_free(); return
	var saved: Dictionary=save.scenes[scene_name]
	check(row(saved,pack).get("uses_left")==remaining and saved.session.cards.size()==1,
		"pre-fade save retains exactly the unspent pack with travelers excluded")
	var bound: Array=b.scene_transition._commit.get_bound_arguments()
	var candidate=bound[1]
	var frozen:=Codec.capture(candidate)
	var rng_before: int=old.rng.state
	var expected_rng:=RandomNumberGenerator.new()
	expected_rng.state=rng_before
	expected_rng.randi_range(0,99)
	var queries: Array[Dictionary]=[]
	var opened: Array[Dictionary]=[]
	var kills: Array[int]=[]
	var puff: Array[Vector3]=[]
	var terminal_card := "Card_Wood" if first_world else "Card_BasaltColumns"
	var expected_card: String=b.catalog.find_by_name("Card_Villager" if prior_draws==0 else terminal_card)
	old.event_occurred.connect(func(kind,payload):
		if kind=="pack_opened": opened.append(payload)
		if kind=="card_killed": kills.append(payload.card_id)
		if kind=="puff_requested" and payload.card_id==pack: puff.append(payload.position))
	old.spawn_target_selector=func(id,ignored):
		if old.cards[id].base_definition_guid==expected_card:
			queries.append({"position":old.cards[id].position, "height":old.spawn_query_height,
				"ignored":ignored,"pack_live":old.cards.has(pack),"pack_locked":b.layout_locks.has(pack_stack)})
		return b._select_spawn_target(id,ignored)
	old.spawn_layout_resolver=b._resolve_layout
	var settings:=DragInput.source_settings(b.catalog,scene_name)
	var visible: Vector3=b.views[pack].global_position
	var offset:=float(settings.clickThreshold)*.4
	var pixels: Vector2=b.camera.unproject_position(visible+Vector3(offset,0,0))-b.camera.unproject_position(visible)
	pointer(pick+pixels)
	b._process(.08)
	var drawn_at: Vector3=b.views[pack].global_position
	var held_target: Vector2=old.card_target_position(pack)
	var pressed: Vector3=b.drag_start_position
	var up:=pick+Vector2(180,40)
	check(held_target.is_equal_approx(Vector2(drawn_at.x,-drawn_at.z))
		and held_target.distance_to(Vector2(pressed.x,pressed.z))>.0005
		and DragInput.is_click(pressed,held_target,settings)
		and b._board_point(up).distance_to(held_target)>float(settings.clickThreshold)*4,
		"rendered click and lifted target are distinct from press and the physical release ray")
	pointer(up,false,InputEvent.DEVICE_ID_EMULATION)
	check(b.dragging==pack and opened.is_empty(),"emulated Up has no pack ownership")
	pointer(up,false)
	check(b.dragging<0 and not old.drag.active() and b._outbound_mouse_hold.is_empty(),
		"the captured Up consumes the exact receipt")
	check(opened.size()==1 and opened[0].slot==prior_draws and old.cards.has(int(opened[0].card_id))
		and old.cards[int(opened[0].card_id)].base_definition_guid==expected_card
		and old.rng.state==expected_rng.state and old.rng.state!=rng_before,
		"one authored card and one real weighted roll on the departing owner")
	var queried_height:=float(settings.dragHeight)+.1
	check(queries.size()==1 and queries[0].position.is_equal_approx(held_target)
		and is_equal_approx(queries[0].height,queried_height) and queries[0].ignored==-1
		and queries[0].pack_live and queries[0].pack_locked,
		"normal factory queries pack held target + .1 height while pack is live and locked")
	if remaining>1:
		check(old.cards.has(pack) and old.cards[pack].uses_left==remaining-1 and old.cards[pack].stack_id==pack_stack
			and old.card_target_position(pack).is_equal_approx(held_target) and kills.is_empty() and puff.is_empty(),
			"nonfinal draw preserves the grounded same pack and decreases remaining slots")
	else:
		check(not old.cards.has(pack) and not old.stacks.has(pack_stack) and kills==[pack]
			and puff.size()==1 and puff[0].is_equal_approx(Vector3(drawn_at.x,drawn_at.y,-drawn_at.z)),
			"final slot kills the pack once and puffs at the actual released view")
	check(not b.layout_locks.has(pack_stack),"no retained pack layout lock")
	pointer(up,false)
	pointer(pick,true)
	pointer(pick,false)
	check(opened.size()==1 and audio.calls.count("CardDrop")==1 and old.rng.state==expected_rng.state,
		"duplicate/fresh fade edges cannot roll again")
	check(FileAccess.get_sha256(file)==sha and saved.session.rng_state==str(rng_before) and Codec.capture(candidate)==frozen,
		"only old live board changes; pre-fade file and staged arrival are frozen")
	b._process(1)
	await process_frame
	check(b.session==candidate and b.scene_transition.phase=="in" and FileAccess.get_sha256(file)==sha,
		"real arrival cannot overwrite the saved pack or reroll")
	pointer(up,false)
	check(opened.size()==1 and b.dragging<0 and b._outbound_mouse_hold.is_empty(),"stale Up cannot affect a new receiver")
	old.spawn_target_selector=Callable()
	old.spawn_layout_resolver=Callable()
	b.queue_free()
	await process_frame

func run() -> void:
	root.size=Vector2i(1240,820)
	await exercise("Main",true)
	await exercise("Island",true)
	await exercise("Main",false)
	await chest_exercise("Main",false,true)
	await chest_exercise("Island",true,true)
	await chest_exercise("Main",false,false)
	await pack_exercise("Main",0)
	await pack_exercise("Main",3)
	await pack_exercise("Island",0)
	await pack_exercise("Island",4)
	print("Source fade held cards, Wooden Chest and regional packs: %d checks, %d failures"%[checks,failures])
	quit(int(failures>0))
