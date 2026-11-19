extends SceneTree
const Board := preload("res://scripts/ui/board.gd")
const Fill := preload("res://scripts/ui/source_day_progress_fill.gd")
class Silence extends "res://scripts/ui/audio_feedback.gd":
	func play_music() -> bool: return false
	func play_event(_id: String) -> bool: return false

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	if not FileAccess.file_exists("res://data/stackcraft.json") or not FileAccess.file_exists("res://assets/imported/manifest.json"):
		print("SKIP 原日进度纹理：需要锁定数据与私有原图")
		quit()
		return
	var board := Board.new()
	board.feedback.free()
	board.feedback=Silence.new()
	board.slot_root="user://source-day-progress-render/slots"
	board.options_path="user://source-day-progress-render/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	board.set_process(false)
	await process_frame
	board.start_new()
	var clock = board.day_clock
	check(board.running and clock.is_visible_in_tree() and clock.source_fill.visible
		and clock.source_fill.source_texture!=null and clock.source_fill.mouse_filter==Control.MOUSE_FILTER_IGNORE
		and clock.progress.get_theme_stylebox("fill") is StyleBoxEmpty,
		"真正 Main HUD 原精灵生效，原生量化填充隐藏，且不拥有点击")
	var unproved: Dictionary = clock.source_config.fill_record.duplicate(true)
	unproved.m_PreserveAspect=1
	var probe := Fill.new()
	check(not probe.configure(board.visual_assets,unproved,Color.WHITE)
		and not probe.visible,"不同作者规则不假冒原左起全矩形条件")
	var record: Dictionary=clock.source_config.fill_record.duplicate(true)
	var tint: Color=clock.source_config.color
	for scene in ["Main","Island"]:
		clock.configure(board.catalog.data,scene,board.visual_assets)
		board.session.elapsed=board.session.day_duration*.12345
		clock.sync(board.session,true,false)
		var rect: Rect2=clock.source_fill.fill_rect()
		var uv: Rect2=clock.source_fill.source_uv_pixels()
		check(clock.source_fill.visible and absf(rect.size.x-clock.source_fill.size.x*.12345)<.0001
			and absf(uv.size.x-64*.12345)<.0001 and rect.position==Vector2.ZERO,
			"相同原图布局使用浮点右边与不重拉伸的 UV: "+scene)
		board.session.elapsed=board.session.day_duration*.000999
		clock.sync(board.session,true,false)
		check(not clock.source_fill.fill_rect().has_area() and clock.progress.value>0,
			"0.001 临界以前有正时间但原 Image 不发出网格: "+scene)
		board.session.elapsed=board.session.day_duration*.001
		clock.sync(board.session,true,false)
		check(clock.source_fill.fill_rect().has_area() and clock.source_fill.fill_rect().size.x<1.0,
			"临界值产生真实亚像素宽度、不会预先取整: "+scene)
	clock.configure(board.catalog.data,"Main",null)
	check(not clock.source_fill.visible and clock.progress.get_theme_stylebox("fill") is StyleBoxFlat,
		"移除私有图资源只回退绘制；不保留过时图或空白条")
	if DisplayServer.get_name()!="headless":
		var layer := CanvasLayer.new()
		layer.layer=102
		root.add_child(layer)
		var bg := ColorRect.new()
		bg.color=Color.BLACK
		layer.add_child(bg)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.add_child(probe)
		probe.position=Vector2(20,20)
		probe.size=Vector2(800,36)
		check(probe.configure(board.visual_assets,record,tint),"原生探针使用已核实的同一纹理")
		for i in range(4): await RenderingServer.frame_post_draw
		probe.set_ratio(.000999)
		await RenderingServer.frame_post_draw
		var below := root.get_texture().get_image()
		probe.set_ratio(.00125)
		await RenderingServer.frame_post_draw
		var above := root.get_texture().get_image()
		probe.set_ratio(.12345)
		await RenderingServer.frame_post_draw
		var wide := root.get_texture().get_image()
		check(_count_tinted(below)==0 and _count_tinted(above)>0 and _count_tinted(wide)>_count_tinted(above)*20,
			"X11帧读回：阈值下无色，阈值上实画，正常时间条向右延展")
		print("Day progress native tinted pixel counts: %d %d %d" % [_count_tinted(below),_count_tinted(above),_count_tinted(wide)])
		layer.queue_free()
	else:
		probe.free()
	board.queue_free()
	await process_frame
	print("Source day progress fill: %d/%d passed (%s)" % [checks-failures,checks,DisplayServer.get_name()])
	quit(1 if failures else 0)

func _count_tinted(image: Image) -> int:
	var n := 0
	var view := root.get_visible_rect().size
	var ratio := Vector2(image.get_size())/view
	var left := int(15*ratio.x)
	var right := mini(int(840*ratio.x),image.get_width())
	for y in range(int(25*ratio.y),mini(int(52*ratio.y),image.get_height()),3):
		for x in range(left,right):
			var pixel := image.get_pixel(x,y)
			if pixel.b>.45 and pixel.g>.3 and pixel.r<.4: n+=1
	return n
