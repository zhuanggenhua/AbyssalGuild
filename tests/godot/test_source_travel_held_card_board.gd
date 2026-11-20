extends SceneTree
## Actual viewport/collider route with injected mouse records, not hardware.
const Board = preload("res://scripts/ui/board.gd")
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

func run() -> void:
	root.size=Vector2i(1240,820)
	await exercise("Main",true)
	await exercise("Island",true)
	await exercise("Main",false)
	print("Source fade held card: %d checks, %d failures"%[checks,failures])
	quit(int(failures>0))
