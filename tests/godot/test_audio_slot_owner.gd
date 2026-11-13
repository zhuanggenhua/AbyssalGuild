extends SceneTree
const Owner = preload("res://scripts/ui/audio_slot_owner.gd")
const Audio = preload("res://scripts/ui/audio_feedback.gd")
const Listener = preload("res://scripts/ui/source_listener.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String):
	checks += 1
	if not value: failures += 1; printerr("FAIL ",label)
func _init(): call_deferred("run")
func sample():
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 8000
	wav.stereo = true
	var bytes := PackedByteArray(); bytes.resize(64000)
	wav.data = bytes
	return wav
func state(mode: float, pitch: float = 1.0):
	return {"spatial_blend":mode,"pitch":pitch,"world_position":Vector3(1,2,-3)}
func run():
	var anchor := AudioStreamPlayer.new(); root.add_child(anchor)
	var owner = Owner.new(anchor)
	var wav = sample()
	check(not owner.play(state(1),wav),"production spatial rejects without renderer")
	check(owner.play(state(0),wav),"default nonspatial works")
	check(owner.play(state(0,1.05),wav) and owner.voices.size()==2,"overlapping slot reuse")
	check(is_equal_approx(owner.voices[0].pitch_scale,1.05),"old voice shares source pitch")
	owner.shutdown(); anchor.queue_free()
	var audio = Audio.new(); root.add_child(audio)
	# Test-only renderer policy: node plumbing, not an acoustic parity proposal.
	var calls: Array = []
	audio.spatial_policy = func(voice, source_state): calls.append(voice.get_instance_id())
	audio.cooldown=0; audio.source_settings={"_randomizeSFXPitch":false}
	audio.clips={"Test":"sample"}; audio.stream_cache.sample=wav
	anchor=AudioStreamPlayer.new(); audio.add_child(anchor); audio.pool.append(anchor)
	check(audio.play_source_event("Test",Vector3(1,2,-3)),"real spatial voice admitted by explicit test policy")
	owner=audio._owner_for(anchor)
	var first: Node=owner.voices[0]
	check(first is AudioStreamPlayer3D and first.global_position==Vector3(1,2,3),"mapped real node")
	check(first.stream.stereo,"no mono conversion")
	audio.set_user_sfx_gain(-18)
	check(first.volume_db==-18,"gain reaches 3D voice")
	check(audio.play_source_event("Test",Vector3(4,5,-6)),"reuse spatial pool")
	check(owner.voices.size()==2 and first.global_position==Vector3(4,5,6),"position affects old overlapping voices")
	check(audio.play_source_event("Test"),"position to null migrates whole slot")
	check(owner.voices.size()==3 and owner.voices.all(func(v):return v is AudioStreamPlayer),"all voices become truly nonspatial")
	check(first.stream==null,"old 3D stream cleared")
	check(audio.play_source_event("Test") and owner.voices.size()==4,"next null still uses persistent owner")
	check(audio.requests.slots[0].world_position==Vector3(4,5,-6),"null retains source position")
	check(audio.play_source_event("Test",Vector3(8,9,-10)),"back to spatial")
	check(owner.voices.size()==5 and owner.voices.all(func(v):return v is AudioStreamPlayer3D),"all overlap migrates back")
	var owned=owner.voices.duplicate()
	audio._stop_slot(anchor)
	check(owned.all(func(v):return v.stream==null and not v.playing),"stop owns every dimensional voice")
	audio.play_source_event("Test",Vector3.ZERO)
	owned=owner.voices.duplicate()
	audio.shutdown()
	check(owner.closed and owned.all(func(v):return v.stream==null),"shutdown closes and clears renderer voices")
	check(not audio.play_source_event("Test"),"shutdown closes admission")
	# Real reconfigure while spatial voices and mixer wait are active.
	audio.shutting_down=false
	audio.stream_cache.sample=wav
	audio.play_source_event("Test",Vector3.ONE)
	owner=audio._owner_for(anchor)
	owned=owner.voices.duplicate()
	audio.source_initialized=true
	audio.requests.request_interrupt(2)
	audio.configure({"data":{"referenced_prefabs":[]}},null)
	check(owner.closed and owned.all(func(v):return v.stream==null),"reconfigure stops and closes previous owner")
	check(audio.requests.waits.size()==1 and audio.requests.mixer_bgm_db==-80,"reconfigure preserves source-persistent mixer coroutine")
	# Reconfigure closes old owner but retains pending persistent mixer wait.
	var catalog = {"data":{"referenced_prefabs":[]}}
	audio.configure(catalog,null)
	check(audio.slot_owners.is_empty() and audio.pool.is_empty(),"empty reconfigure clean")
	var listener=Listener.new(); root.add_child(listener)
	check(listener.apply_source_pose(Vector3(0,1,-10),Quaternion.IDENTITY),"source listener independent pose")
	check(listener.global_position==Vector3(0,1,10) and listener.is_current(),"Title listener mapped, not native shell camera")
	check(not listener.apply_source_pose(Vector3(INF,0,0),Quaternion.IDENTITY),"invalid pose rejected")
	listener.queue_free(); audio.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Slot lifecycle: %d/%d (no acoustic parity claim)"%[checks-failures,checks])
	quit(1 if failures else 0)
