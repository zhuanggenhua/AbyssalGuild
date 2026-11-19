extends Control
## 锁定 TimeProgress Image.Filled 横向左起。节点只绘制，不拥有时间或鼠标点击。
## 原 Square 是未打图集的 64×64 全白不透明图，绘制范围及 UV 都没有裁边。
const SPRITE_GUID := "57fe652483042fb4ba6612b888e7a928"
const SPRITE_SHA256 := "b7b1307f35fe0b47997101afb3e009802b6d22f2259edfd3054e022a38b84686"
const SIZE := Vector2i(64,64)
const MIN_FILL := 0.001
var source_texture: Texture2D
var source_tint := Color.WHITE
var ratio := 0.0

func _init() -> void:
	name = "SourceDayProgressFill"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	resized.connect(queue_redraw)
	hide()

## 不把缺失的私有纹理、错配 GUID 或未核实的紧密/裁剪图当作所识别的原精灵。
func configure(assets: RefCounted, record: Dictionary, tint: Color) -> bool:
	source_texture = null
	hide()
	if assets == null or not assets.has_method("texture"): return false
	var entry: Dictionary = record.get("m_Sprite",{})
	if str(entry.get("guid",""))!=SPRITE_GUID or str(entry.get("fileID",""))!="21300000" \
			or record.get("m_Enabled",0)!=1 or record.get("m_RaycastTarget",1)!=0 \
			or record.get("m_Type",-1)!=3 or record.get("m_FillMethod",-1)!=0 or record.get("m_FillOrigin",-1)!=0 \
			or record.get("m_PreserveAspect",1)!=0 or record.get("m_UseSpriteMesh",1)!=0:
		return false
	var metadata: Variant = assets.get("manifest") if "manifest" in assets else null
	if not metadata is Dictionary: return false
	var asset: Dictionary = metadata.get("assets",{}).get(SPRITE_GUID,{})
	var sprite: Dictionary = asset.get("sprite",{})
	if asset.get("sha256","")!=SPRITE_SHA256 or sprite.get("mode","")!="single_full_image": return false
	var candidate: Texture2D = assets.texture(SPRITE_GUID)
	if candidate==null or candidate.get_size()!=Vector2(SIZE): return false
	var image: Image = candidate.get_image()
	if image==null or image.get_size()!=SIZE: return false
	if image.is_compressed() and image.decompress()!=OK: return false
	# 无透明边缘、旋转或裁剪的许可边界；纹理不匹配保留原有原生回退。
	for y in SIZE.y:
		for x in SIZE.x:
			if image.get_pixel(x,y)!=Color.WHITE: return false
	source_texture=candidate
	source_tint=tint
	show()
	queue_redraw()
	return true

func set_ratio(value: float) -> void:
	var next := _f32(clampf(value,0,1)) if is_finite(value) else 0.0
	if next==ratio: return
	ratio=next
	queue_redraw()

func fill_rect() -> Rect2:
	if source_texture==null or ratio<_f32(MIN_FILL): return Rect2()
	return Rect2(Vector2.ZERO,Vector2(size.x*ratio,size.y))

func source_uv_pixels() -> Rect2:
	if not fill_rect().has_area(): return Rect2()
	return Rect2(Vector2.ZERO,Vector2(float(SIZE.x)*ratio,SIZE.y))

func _draw() -> void:
	var destination := fill_rect()
	if destination.has_area():
		draw_texture_rect_region(source_texture,destination,source_uv_pixels(),source_tint,false,false)

static func _f32(value: float) -> float:
	return PackedFloat32Array([value])[0]
