extends SceneTree
const Simulation = preload("res://scripts/ui/puff_simulation.gd")
const Assets = preload("res://scripts/ui/visual_assets.gd")
var checks := 0
func _init() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	assert(value,message)

func key(time: float, value: float, incoming: float, outgoing: float, mode: int = 0, in_weight: float = 0.3, out_weight: float = 0.3) -> Dictionary:
	return {"time":time,"value":value,"inSlope":incoming,"outSlope":outgoing,"weightedMode":mode,"inWeight":in_weight,"outWeight":out_weight}

func fixture() -> Dictionary:
	return {"supported":true,"unsupported":[],"duration":2.0,"cleanup_scaled_seconds":2.1,"burst_count":17,
		"ranges":{"lifetime":{"min":0.2,"max":0.8},"speed":{"min":1.0,"max":2.0},"size":{"min":0.1,"max":0.2}},
		"shape":{"radius":0.4,"position":{"x":0,"y":0.2,"z":0},"rotation_degrees":{"x":-90,"y":0,"z":0}},
		"start_color":{"r":0.4,"g":0.5,"b":0.6,"a":0.7},
		"size_keys":[key(0,0,0,2,2,0.3,0.6),key(1,1,0,0,1,0.2,0.3)],
		"opacity_keys":[{"time":0.0,"value":1.0},{"time":0.75,"value":1.0},{"time":1.0,"value":0.0}]}

func run() -> void:
	var config := fixture()
	check(Simulation.is_supported(config),"valid synthetic config")
	check(is_equal_approx(Simulation.weighted_value(config.size_keys,0.65),0.95),"weighted x(t) inversion has analytical midpoint")
	check(Simulation.weighted_value(config.size_keys,-1) == 0 and Simulation.weighted_value(config.size_keys,2) == 1,"endpoint clamp")
	var linear_keys := [key(0,0,1,1,2,0.3,0.7),key(1,1,1,1,1,0.1,0.3)]
	for index in 21:
		var value: float = index/20.0
		check(absf(Simulation.weighted_value(linear_keys,value)-value)<0.000001,"weighted linear function remains linear")
	check(is_equal_approx(Simulation.linear_value(config.opacity_keys,0.875),0.5),"opacity tail interpolation")
	check(Simulation.linear_value(config.opacity_keys,0.75) == 1,"opacity stays opaque until last interval")
	var simulation = Simulation.new()
	check(simulation.is_expired() and simulation.sample_states().is_empty(),"unconfigured empty")
	seed(3819)
	var expected_global := randf()
	seed(3819)
	check(simulation.configure(config,214),"configure explicit presentation seed")
	check(randf() == expected_global,"configure does not consume global RNG")
	check(simulation.birth_states().size() == 17,"one immediate burst")
	var births: Array[Dictionary] = simulation.birth_states()
	var equivalent = Simulation.new()
	equivalent.configure(config,214)
	check(births == equivalent.birth_states(),"native same-seed repeatability")
	equivalent.configure(config,215)
	check(births != equivalent.birth_states(),"different native seed changes births")
	for birth in births:
		check(is_equal_approx(birth.position.y,0.2),"rotated disk plane retains offset")
		check(Vector2(birth.position.x,birth.position.z).length() <= 0.40001,"disk radius")
		check(birth.velocity.length() >= 0.99999 and birth.velocity.length() <= 2.00001,"speed range")
		check(birth.velocity.normalized().is_equal_approx(birth.position.normalized()),"spherized outward direction includes offset")
		check(birth.lifetime >= 0.2 and birth.lifetime <= 0.8 and birth.size >= 0.1 and birth.size <= 0.2,"lifetime/size ranges")
	for state in simulation.sample_states(): check(is_zero_approx(state.size),"size curve starts at zero")
	births[0].position = Vector3(99,99,99)
	check(simulation.birth_states()[0].position != births[0].position,"birth snapshots cannot mutate simulation")
	config.ranges.size.max = 99
	check(simulation.birth_states()[0].size < 1,"configure copies its input")
	var state_before: int = simulation._rng.state
	check(simulation.advance(0.1,0.0),"particle time advances while gameplay paused")
	for state in simulation.sample_states():
		var birth: Dictionary = simulation.birth_states()[int(state.index)]
		check(state.position.is_equal_approx(birth.position+birth.velocity*0.1),"ballistic movement from immutable birth")
		check(is_equal_approx(state.color.a,0.7),"start alpha times opacity ramp")
	check(simulation._rng.state == state_before,"frames/sampling consume no RNG")
	var returned: Array[Dictionary] = simulation.sample_states()
	returned[0].position = Vector3.ZERO
	check(simulation.sample_states()[0].position != Vector3.ZERO,"sample snapshots immutable by copy")
	check(not simulation.advance(-1,0) and not simulation.advance(0,NAN),"invalid deltas rejected atomically")
	check(is_equal_approx(simulation.elapsed,0.1) and simulation.scaled_elapsed == 0,"invalid delta preserves both clocks")
	simulation.advance(1,0)
	check(simulation.sample_states().is_empty() and not simulation.is_expired(),"particles finish during pause but scaled destruction waits")
	simulation.advance(0,2.1)
	check(simulation.is_expired(),"scaled destruction threshold")
	check(not simulation.advance(1,1),"expired state does not advance")
	simulation.reset()
	check(simulation.elapsed == 0 and simulation.scaled_elapsed == 0 and simulation.birth_states().is_empty(),"reset drops all transient state")
	var fast := fixture()
	fast.ranges.lifetime = {"min":3.0,"max":3.0}
	simulation.configure(fast,4)
	simulation.advance(1.049,2.098)
	check(simulation.sample_states().size()==17 and not simulation.is_expired(),"fast cleanup not premature")
	simulation.advance(0.001,0.0021)
	check(simulation.is_expired() and simulation.sample_states().is_empty(),"scaled cleanup can truncate unscaled particles")
	var partition := fixture()
	simulation.configure(partition,9)
	equivalent.configure(partition,9)
	simulation.advance(0.17,0.34)
	for index in 17: equivalent.advance(0.01,0.02)
	var a: Array[Dictionary] = simulation.sample_states()
	var b: Array[Dictionary] = equivalent.sample_states()
	check(a.size()==b.size(),"frame partition preserves survivors")
	for index in a.size():
		check(a[index].position.is_equal_approx(b[index].position) and is_equal_approx(a[index].size,b[index].size),"frame partition preserves mathematical state")
	var tilted := fixture()
	tilted.shape.position = {"x":1,"y":2,"z":3}
	tilted.shape.rotation_degrees = {"x":25,"y":35,"z":45}
	equivalent.configure(tilted,8)
	var source_normal: Vector3 = Basis(Vector3.UP,deg_to_rad(35))*Basis(Vector3.RIGHT,deg_to_rad(25))*Basis(Vector3.BACK,deg_to_rad(45))*Vector3.BACK
	var reflected_normal := Vector3(source_normal.x,source_normal.y,-source_normal.z)
	for birth in equivalent.birth_states():
		check(absf((birth.position-Vector3(1,2,-3)).dot(reflected_normal))<0.000001,"Unity ZXY rotation then world Z reflection")
	var disk := fixture()
	disk.burst_count = 1000
	equivalent.configure(disk,547)
	var mean_radius_squared: float = 0
	for birth in equivalent.birth_states(): mean_radius_squared += Vector2(birth.position.x,birth.position.z).length_squared()/1000.0
	check(absf(mean_radius_squared-0.08)<0.006,"uniform disk area, not uniform radius")
	for change in [{"burst_count":0},{"supported":false},{"unsupported":["noise"]},{"size_keys":[]},{"cleanup_scaled_seconds":NAN}]:
		var invalid := fixture()
		invalid.merge(change,true)
		check(not simulation.configure(invalid,4) and simulation.is_expired() and simulation.birth_states().is_empty(),"invalid configuration clears old state")
	var bad_keys := fixture()
	bad_keys.size_keys[0].outWeight = 2
	check(not Simulation.is_supported(bad_keys),"invalid weighted tangent rejected")
	var assets = Assets.new()
	assets.manifest = {"scenes":{"A":{"puff":fixture()},"B":{"puff":fixture()}}}
	assets.manifest.scenes.B.puff.burst_count = 8
	check(assets.puff_configuration("A").burst_count==17 and assets.puff_configuration("B").burst_count==8,"active scene lookup never first global settings")
	check(assets.puff_configuration("missing").is_empty(),"missing scene no guessed Puff")
	var copy: Dictionary = assets.puff_configuration("A")
	copy.burst_count=500
	check(assets.puff_configuration("A").burst_count==17,"configuration returned by copy")
	print("Puff simulation synthetic checks: %d passed" % checks)
	private_checks()
	quit()

func private_checks() -> void:
	var assets = Assets.new()
	if assets.load_manifest()!=OK:
		print("Private Puff simulation: SKIP (private visual manifest unavailable)")
		return
	if assets.puff_configuration("Main").is_empty():
		print("Private Puff simulation: SKIP (regenerate supported private Puff metadata)")
		return
	for scene in ["Main","Island"]:
		var record: Dictionary = assets.puff_configuration(scene)
		var simulation = Simulation.new()
		check(simulation.configure(record,734),"actual metadata accepted")
		check(simulation.birth_states().size()==int(record.burst_count),"actual burst count")
		for birth in simulation.birth_states():
			check(float(birth.lifetime)>=float(record.ranges.lifetime.min) and float(birth.lifetime)<=float(record.ranges.lifetime.max),"actual lifetime bounds")
			check(birth.velocity.length()>=float(record.ranges.speed.min)-0.00001 and birth.velocity.length()<=float(record.ranges.speed.max)+0.00001,"actual speed bounds")
			check(is_equal_approx(birth.position.y,float(record.shape.position.y)),"actual offset shape plane")
		for key in record.size_keys:
			check(absf(Simulation.weighted_value(record.size_keys,float(key.time))-float(key.value))<0.000001,"actual weighted curve passes authored keys")
		for index in range(record.size_keys.size()-1):
			var left: Dictionary = record.size_keys[index]
			var right: Dictionary = record.size_keys[index+1]
			var interval: float = float(right.time)-float(left.time)
			var out_weight: float = float(left.outWeight) if int(left.weightedMode)&2 else 1.0/3.0
			var in_weight: float = float(right.inWeight) if int(right.weightedMode)&1 else 1.0/3.0
			var x_mid: float = (float(left.time)+3*(float(left.time)+interval*out_weight)+3*(float(right.time)-interval*in_weight)+float(right.time))/8.0
			var y_mid: float = (float(left.value)+3*(float(left.value)+float(left.outSlope)*interval*out_weight)+3*(float(right.value)-float(right.inSlope)*interval*in_weight)+float(right.value))/8.0
			check(absf(Simulation.weighted_value(record.size_keys,x_mid)-y_mid)<0.000001,"actual weighted segment analytical midpoint")
		check(is_equal_approx(Simulation.linear_value(record.opacity_keys,float(record.opacity_keys[-2].time)),float(record.opacity_keys[-2].value)),"actual opacity breakpoint")
		var material: Dictionary = assets.manifest.materials[str(record.materials[0].guid)]
		check(not material.shader_reference.is_empty(),"actual unresolved shader identity retained")
		var texture_guid: String = str(material.textures._MainTex.m_Texture.guid)
		check(assets.texture(texture_guid)!=null,"actual Puff texture reference resolves")
		check(assets.manifest.assets[texture_guid].has("texture_importer"),"non-sprite Puff importer metadata retained")
		check(record.material_equivalence=="unresolved_builtin_shader","does not falsely claim shader parity")
		simulation.advance(float(record.ranges.lifetime.max)+0.01,0)
		check(simulation.sample_states().is_empty() and not simulation.is_expired(),"actual particle expiry and paused cleanup differ")
		simulation.advance(0,float(record.cleanup_scaled_seconds))
		check(simulation.is_expired(),"actual scaled cleanup")
	print("Private Puff simulation: PASS (both scene references, birth ranges, weighted curves, two clocks, material/texture references)")
	print("Puff simulation total checks: %d passed; no renderer or GPU acceptance" % checks)
