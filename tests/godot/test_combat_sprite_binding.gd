extends SceneTree
const Assets = preload("res://scripts/ui/visual_assets.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const Binding = preload("res://scripts/ui/combat_sprite_binding.gd")
const SourceCamera = preload("res://scripts/ui/source_camera.gd")
var checks := 0

func _init() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func pose(scale: Vector3 = Vector3.ONE, position: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"m_LocalPosition":{"x":position.x,"y":position.y,"z":position.z},"m_LocalRotation":{"x":0,"y":0,"z":0,"w":1},"m_LocalScale":{"x":scale.x,"y":scale.y,"z":scale.z}}

func role(size: Vector2, pivot: Vector2 = Vector2(0.5,0.5), position: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"pose":pose(Vector3.ONE,position),"size":{"x":size.x,"y":size.y},"pivot":{"x":pivot.x,"y":pivot.y},
		"color":{"r":0.2,"g":0.4,"b":0.6,"a":0.8},"material":{"fileID":"0"},"image_type":0,"preserve_aspect":false,"font_size":0.3}

func fixture():
	var assets = Assets.new()
	assets.manifest = {"assets":{},"scenes":{"Synthetic":{"combat":{"projectiles":{},"hit_ui":{}}}}}
	for key in ["arrow","magic","miss","normal","critical","advantage","disadvantage"]:
		var image := Image.create(40,80,false,Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		assets.texture_cache[key] = ImageTexture.create_from_image(image)
		assets.manifest.assets[key] = {"sprite":{"mode":"single_full_image","pixel_size":{"x":40,"y":80},"pixels_per_unit":20,"pivot":{"x":0.25,"y":0.75},"filter_mode":1}}
	for key in ["2","3"]:
		assets.manifest.scenes.Synthetic.combat.projectiles[key] = {"transform_chain":[pose(Vector3(2,3,1),Vector3(9,8,7))],"duration":0.7,
			"sprite":{"guid":"arrow" if key == "2" else "magic"},"color":{"r":0.5,"g":0.6,"b":0.7,"a":0.8},"flip_x":true,"flip_y":false,"draw_mode":0,
			"materials":[{"fileID":"10754","guid":"0000000000000000f000000000000000"}]}
	var hit := {"root_scale":{"x":1,"y":1,"z":1},"roles":{"hit":role(Vector2(2,4)),"effectiveness":role(Vector2(0.6,0.8),Vector2.ONE,Vector3(1.3,2.2,0)),"damage":role(Vector2(2,4))},"sprites":{}}
	for key in ["miss","normal","critical","advantage","disadvantage"]: hit.sprites[key] = {"guid":key}
	assets.manifest.scenes.Synthetic.combat.hit_ui = hit
	return assets

func bounds(sprite: Sprite3D, transform: Transform3D = Transform3D.IDENTITY) -> AABB:
	var faces: PackedVector3Array = sprite.generate_triangle_mesh().get_faces()
	var result := AABB(transform * faces[0],Vector3.ZERO)
	for vertex in faces: result = result.expand(transform * vertex)
	return result

func run() -> void:
	var card = CardView.new()
	card.configure(1,"Synthetic",2,false)
	var base: Color = card.material.albedo_color
	var original: Transform3D = card.transform
	card.highlight(true)
	card.set_hurt_flash(0.6)
	check(is_equal_approx(card.hurt_flash,0.6),"flash state")
	check(card.material.albedo_color.is_equal_approx(Color(base.lerp(Color.WHITE,0.6)*1.3,base.a)),"fallback flash formula")
	check(card.material.emission_enabled,"flash does not unset selected emission")
	card.highlight(false)
	check(is_equal_approx(card.hurt_flash,0.6),"highlight does not reset flash")
	card.set_hurt_flash(INF)
	check(is_equal_approx(card.hurt_flash,0.6),"nonfinite input ignored")
	card.set_hurt_flash(2)
	check(card.hurt_flash == 1,"flash clamps high")
	card.set_hurt_flash(-1)
	check(card.material.albedo_color.is_equal_approx(base),"flash restores original fallback color")
	check(card.transform == original,"flash cannot change card/pick pose")
	var shader := ShaderMaterial.new()
	shader.shader = preload("res://scripts/ui/shaders/card_surface.gdshader")
	card.source_material = shader
	card.highlight(true)
	var emission: Variant = shader.get_shader_parameter("selection_emission")
	card.set_hurt_flash(0.4)
	check(is_equal_approx(shader.get_shader_parameter("flash_amount"),0.4),"source shader receives flash")
	check(shader.get_shader_parameter("selection_emission") == emission,"source selection emission independent")
	card.update_state({"health":5})
	check(is_equal_approx(shader.get_shader_parameter("flash_amount"),0.4),"stat update preserves ongoing flash")
	card.free()
	var assets = fixture()
	for type in [2,3]:
		var projectile: Sprite3D = assets.create_projectile(type,"Synthetic")
		check(projectile != null,"projectile built from references")
		check(projectile.texture == assets.texture_cache["arrow" if type == 2 else "magic"],"projectile texture identity")
		check(is_equal_approx(projectile.pixel_size,0.05),"sprite source pixels/unit")
		check(projectile.scale == Vector3(2,3,1) and projectile.position == Vector3.ZERO,"Fire overrides position/rotation, preserves scale")
		check(projectile.flip_h and not projectile.flip_v,"sprite flip flags")
		check(projectile.modulate.is_equal_approx(Color(0.5,0.6,0.7,0.8)),"sprite tint")
		check(projectile.offset == Vector2(10,-20),"noncenter pivot")
		check(bounds(projectile).size.is_equal_approx(Vector3(2,4,0)),"PPU not serialized simple-renderer m_Size")
		check(bounds(projectile).position.is_equal_approx(Vector3(-0.5,-3,0)),"sprite pivot geometric bounds")
		check(is_equal_approx(projectile.get_meta("source_duration"),0.7),"duration metadata not gameplay timer")
		check(not projectile.shaded and not projectile.no_depth_test and projectile.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"unlit world sprite/no shadow")
		projectile.free()
	for kind in ["miss","normal","critical"]:
		for advantage in [-1,0,1]:
			var popup: Node3D = assets.create_hit_popup(kind,"42",advantage,"Synthetic")
			check(popup != null,"complete popup binding")
			check(is_equal_approx(popup.rotation_degrees.x,-90),"fixed source world-plane rotation, not billboard")
			check(popup.get_node("Hit").texture == assets.texture_cache[kind],"hit type sprite identity")
			check(popup.get_node("Damage").text == ("" if kind == "miss" else "42"),"miss empty damage, critical no invented exclamation")
			check(popup.has_node("Effectiveness") == (advantage != 0),"exact advantage visibility")
			if advantage != 0:
				var effect: Sprite3D = popup.get_node("Effectiveness")
				check(effect.texture == assets.texture_cache["advantage" if advantage == 1 else "disadvantage"],"effectiveness sprite identity")
				var box := bounds(effect,effect.transform)
				check(box.size.is_equal_approx(Vector3(0.6,0.8,0)),"effectiveness rect size")
				check(box.position.is_equal_approx(Vector3(0.7,1.4,0)),"anchor plus noncenter pivot geometry")
			popup.free()
	check(assets.create_projectile(1,"Synthetic") == null,"melee has no fabricated sprite")
	check(assets.create_projectile(2,"Missing") == null,"missing scene fallback")
	check(assets.create_hit_popup("unknown","1",0,"Synthetic") == null,"unknown outcome fallback")
	var record: Dictionary = assets.manifest.scenes.Synthetic.combat.projectiles["2"].duplicate(true)
	record.materials[0].fileID = "unsupported"
	check(Binding.projectile(assets,record) == null,"unknown material fallback")
	record = assets.manifest.scenes.Synthetic.combat.projectiles["2"].duplicate(true)
	record.draw_mode = 1
	check(Binding.projectile(assets,record) == null,"sliced sprite fallback")
	assets.manifest.assets.arrow.sprite.mode = "atlas"
	check(assets.create_projectile(2,"Synthetic") == null,"atlas regions never guessed")
	assets.texture_cache.erase("advantage")
	check(assets.create_hit_popup("normal","4",1,"Synthetic") == null,"missing required icon falls back as whole popup")
	var no_effect: Node3D = assets.create_hit_popup("normal","4",0,"Synthetic")
	check(no_effect != null,"unused missing icon does not block no-effect popup")
	no_effect.free()
	print("Combat sprite/flash synthetic checks: %d passed" % checks)
	private_checks()
	quit()

func private_checks() -> void:
	var assets = Assets.new()
	if assets.load_manifest() != OK:
		print("Private combat sprites: SKIP (private visual manifest unavailable)")
		return
	if assets.scene_configuration("Main").get("combat",{}).is_empty():
		print("Private combat sprites: SKIP (regenerate private visual metadata)")
		return
	for scene in ["Main","Island"]:
		var combat: Dictionary = assets.scene_configuration(scene).combat
		for key in combat.projectiles:
			var projectile: Sprite3D = assets.create_projectile(int(key),scene)
			check(projectile != null,"actual projectile PNG binding")
			var record: Dictionary = combat.projectiles[key]
			var importer: Dictionary = assets.manifest.assets[str(record.sprite.guid)].sprite
			check(projectile.texture == assets.texture(str(record.sprite.guid)),"actual referenced projectile texture")
			check(is_equal_approx(projectile.pixel_size,1.0 / float(importer.pixels_per_unit)),"actual sprite PPU")
			var expected := Vector3(float(importer.pixel_size.x),float(importer.pixel_size.y),0) / float(importer.pixels_per_unit)
			check(bounds(projectile).size.is_equal_approx(expected),"actual PNG-derived footprint")
			check(is_equal_approx(projectile.get_meta("source_duration"),float(record.duration)),"actual serialized flight duration")
			projectile.free()
		var config: Dictionary = combat.hit_ui
		for kind in ["miss","normal","critical"]:
			for advantage in [-1,0,1]:
				var popup: Node3D = assets.create_hit_popup(kind,"7",advantage,scene)
				check(popup != null,"actual popup complete")
				check(popup.get_node("Hit").texture == assets.texture(str(config.sprites[kind].guid)),"actual hit PNG identity")
				check(popup.get_node("Damage").text == ("" if kind == "miss" else "7"),"actual damage semantics")
				check(popup.has_node("Effectiveness") == (advantage != 0),"actual effectiveness semantics")
				var roles := ["hit","effectiveness"] if advantage != 0 else ["hit"]
				for name in roles:
					var sprite: Sprite3D = popup.get_node(name.capitalize())
					var r: Dictionary = config.roles[name]
					var size := Vector3(float(r.size.x),float(r.size.y),0)
					var box := bounds(sprite,sprite.transform)
					check(box.size.is_equal_approx(size),"actual source rectangle dimensions")
					var position := Vector3(float(r.pose.m_LocalPosition.x),float(r.pose.m_LocalPosition.y),-float(r.pose.m_LocalPosition.z))
					check(box.position.is_equal_approx(position - size * Vector3(float(r.pivot.x),float(r.pivot.y),0)),"actual source anchored rectangle")
				popup.free()
		var card = CardView.new()
		card.configure(1,"Private flash",2,false,assets,{},scene)
		card.highlight(true)
		card.set_hurt_flash(0.75)
		if card.source_material != null:
			check(is_equal_approx(card.source_material.get_shader_parameter("flash_amount"),0.75),"actual cached card flash binding")
			check(card.source_material.get_shader_parameter("selection_emission") == Vector3.ZERO,"source flash does not add invented selection emission")
		else:
			print("Private card flash shader: SKIP (FBX cache unavailable; fallback tested)")
		card.free()
	print("Private combat sprites: PASS (both scenes, two projectile resources, all nine hit/advantage combinations)")
	print("Combat sprite/flash total checks: %d passed; no GPU/manual visual acceptance" % checks)
