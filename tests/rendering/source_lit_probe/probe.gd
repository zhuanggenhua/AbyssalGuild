extends Node
## Synthetic, source-independent geometry. Native renderer required for readback.
const COLOR := Color(0.4, 0.2, 0.6, 1.0)
const ANGLES := [Vector2(0, 0), Vector2(35, 0), Vector2(60, 30), Vector2(75, -30)]
const TOLERANCE := 0.006
var failures: Array[String] = []
var samples: Array = []
var maximum_error := 0.0

func _ready() -> void:
    if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "gl_compatibility":
        print("Source direct-light GPU probe NOT RUN: native Compatibility renderer required.")
        get_tree().quit(2)
        return
    await run_probe()

func modes() -> Array[String]:
    return ["source_formula", "stock_diagnostic"]

func material_for(mode: String) -> Material:
    if mode == "stock_diagnostic":
        var stock := StandardMaterial3D.new()
        stock.albedo_color = COLOR
        stock.roughness = 1.0
        stock.metallic = 0.0
        stock.cull_mode = BaseMaterial3D.CULL_DISABLED
        return stock
    var material := ShaderMaterial.new()
    material.shader = preload("res://direct_probe.gdshader")
    material.set_shader_parameter("source_base_color", COLOR)
    return material

func direction(degrees: float) -> Vector3:
    return Vector3(sin(deg_to_rad(degrees)), 0, cos(deg_to_rad(degrees)))

func reference(angles: Vector2) -> Color:
    var light := direction(angles.x)
    var view := direction(angles.y)
    var half_sum := light + view
    var halfway := half_sum / sqrt(maxf(1.175494351e-38, half_sum.length_squared()))
    var loh := clampf(light.dot(halfway), 0.0, 1.0)
    var specular := 0.04 / (6.0 * maxf(0.1, loh * loh) * 1.00001 * 1.00001)
    var linear := COLOR.srgb_to_linear()
    return Color((0.96 * linear.r + specular) * light.z,
        (0.96 * linear.g + specular) * light.z,
        (0.96 * linear.b + specular) * light.z, 1.0)

func run_probe() -> void:
    for mode in modes():
        for angles in ANGLES:
            var viewport := SubViewport.new()
            viewport.size = Vector2i(128, 128)
            viewport.own_world_3d = true
            viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
            add_child(viewport)
            var environment := WorldEnvironment.new()
            environment.environment = Environment.new()
            environment.environment.background_mode = Environment.BG_COLOR
            environment.environment.background_color = Color.BLACK
            environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
            environment.environment.reflected_light_source = 1 # Runtime ReflectedLightSource enum: Disabled.
            environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
            viewport.add_child(environment)
            var mesh := MeshInstance3D.new()
            mesh.mesh = QuadMesh.new()
            mesh.mesh.size = Vector2(3, 3)
            var material := material_for(mode)
            if material == null:
                failures.append(mode + ": material admission failed")
                viewport.queue_free()
                continue
            mesh.material_override = material
            viewport.add_child(mesh)
            var camera := Camera3D.new()
            camera.projection = Camera3D.PROJECTION_ORTHOGONAL
            camera.size = 1.0
            camera.position = direction(angles.y) * 3.0
            viewport.add_child(camera)
            camera.look_at(Vector3.ZERO)
            camera.current = true
            var light := DirectionalLight3D.new()
            light.rotation.y = deg_to_rad(angles.x)
            light.light_color = Color.WHITE
            light.light_energy = 1.0
            light.shadow_enabled = false
            viewport.add_child(light)
            for frame in 4:
                await get_tree().process_frame
                await RenderingServer.frame_post_draw
            var image := viewport.get_texture().get_image()
            if image == null or image.is_empty():
                failures.append(mode + ": no framebuffer image")
                viewport.queue_free()
                continue
            var observed := Color(0, 0, 0, 0)
            for x in range(62, 66):
                for y in range(62, 66):
                    observed += image.get_pixel(x, y).srgb_to_linear() / 16.0
            var expected := reference(angles)
            var error := maxf(absf(observed.r - expected.r), maxf(absf(observed.g - expected.g), absf(observed.b - expected.b)))
            var asserted: bool = mode != "stock_diagnostic"
            if asserted:
                maximum_error = maxf(maximum_error, error)
                if not is_finite(error) or error > TOLERANCE:
                    failures.append("%s (%s): error %s" % [mode, angles, error])
            samples.append({"mode":mode,"light_degrees":angles.x,"view_degrees":angles.y,
                "linear_readback":[observed.r, observed.g, observed.b],
                "linear_expected":[expected.r, expected.g, expected.b],"max_error":error,"asserted":asserted})
            viewport.queue_free()
            await get_tree().process_frame
    var report := {"status":"pass" if failures.is_empty() else "fail", "scope":"synthetic direct light only",
        "engine":Engine.get_version_info(), "display":DisplayServer.get_name(),
        "renderer":RenderingServer.get_current_rendering_method(), "adapter":RenderingServer.get_video_adapter_name(),
        "authored_color":[COLOR.r,COLOR.g,COLOR.b],"sample_pixels":16,"tolerance":TOLERANCE,
        "maximum_asserted_error":maximum_error,"samples":samples,"failures":failures}
    var output := "res://result.json"
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
    var handle := FileAccess.open(output, FileAccess.WRITE)
    if handle == null:
        push_error("Cannot save probe result: " + output)
        get_tree().quit(1)
        return
    handle.store_string(JSON.stringify(report, "  ") + "\n")
    print("Source direct-light GPU probe: ", report.status, "; samples=", samples.size(), "; max error=", maximum_error)
    get_tree().quit(0 if failures.is_empty() else 1)
