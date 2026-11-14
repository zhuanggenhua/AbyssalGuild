extends SceneTree
const Group=preload("res://scripts/ui/source_stats_group.gd")
class TextStub extends Control:
 signal layout_contract_changed
 var contract={"ok":true}
 var group_source_enabled=true
 var source_width=17.25
 func _get_minimum_size()->Vector2:
  return Vector2(source_width,30) if group_source_enabled else Vector2(20,35)
 func set_group_mode(enabled:bool):
  if group_source_enabled==enabled:return
  group_source_enabled=enabled
  update_minimum_size()
var checks=0
func check(ok:bool):
 checks+=1
 assert(ok)
func icon()->TextureRect:
 var c=TextureRect.new()
 var image=Image.create(64,64,false,Image.FORMAT_RGBA8)
 image.fill(Color.WHITE)
 c.texture=ImageTexture.create_from_image(image)
 c.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
 c.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 c.custom_minimum_size=Vector2(64,30)
 c.size_flags_vertical=Control.SIZE_SHRINK_CENTER
 return c
func _init():call_deferred("run")
func run():
 var text_type=preload("res://scripts/ui/source_stats_text.gd")
 for invalid in [null,[],"30",{}, {"y":null},{"y":"30"}]:
  check(text_type.source_height_from(invalid)==0.0)
 check(text_type.source_height_from({"y":30})==30.0)
 check(text_type.source_height_from({"y":30.0})==30.0)
 var group=Group.new()
 root.add_child(group)
 check(group.source_parent.mouse_filter==Control.MOUSE_FILTER_IGNORE)
 var text_shell=preload("res://scripts/ui/source_stats_text.gd").new()
 check(text_shell.mouse_filter==Control.MOUSE_FILTER_IGNORE)
 check(text_shell.native_label.mouse_filter==Control.MOUSE_FILTER_IGNORE)
 text_shell.free()
 group.position=Vector2(0,30)
 group.size=Vector2(400,50)
 var fields={"m_ChildAlignment":3,"m_ChildControlWidth":1,"m_ChildControlHeight":0,"m_ChildForceExpandWidth":0,"m_ChildForceExpandHeight":0,"m_ChildScaleWidth":0,"m_ChildScaleHeight":0,"m_Spacing":0,"m_Padding":{"m_Left":0,"m_Right":34,"m_Top":0,"m_Bottom":0},"m_ReverseArrangement":0,"m_HorizontalFit":2,"m_VerticalFit":0}
 group.configure_source(fields)
 var labels=[]
 for width in [17.25,22.5,24.75]:
  group.add_element(icon())
  var c=TextStub.new()
  c.source_width=width
  c.size_flags_vertical=Control.SIZE_SHRINK_CENTER
  group.add_element(c)
  labels.append(c)
 for i in 6:await process_frame
 check(group.source_enabled)
 var pos=64.0
 for c in labels:
  check(is_equal_approx(c.position.x,pos))
  check(c.size.y==30 and c.get_global_rect().get_center().y==55)
  pos+=c.source_width+64
 # Reproduce old integer HBox positioning with the same synthetic widths.
 var old=HBoxContainer.new()
 root.add_child(old)
 old.size=Vector2(400,50)
 old.add_theme_constant_override("separation",0)
 var old_labels=[]
 for width in [17.25,22.5,24.75]:
  old.add_child(icon())
  var c=TextStub.new()
  c.source_width=width
  old.add_child(c)
  old_labels.append(c)
 for i in 4:await process_frame
 check(not is_equal_approx(old_labels[1].position.x,labels[1].position.x))
 labels[1].contract.ok=false
 labels[1].layout_contract_changed.emit()
 for i in 6:await process_frame
 check(not group.source_enabled)
 for c in labels:check(not c.group_source_enabled and c.size.y==35)
 labels[1].contract.ok=true
 labels[1].layout_contract_changed.emit()
 for i in 6:await process_frame
 check(group.source_enabled)
 check(is_equal_approx(labels[1].position.x,145.25))
 fields.m_ReverseArrangement=1
 group.configure_source(fields)
 for i in 4:await process_frame
 check(not group.source_enabled)
 fields.m_Padding=null
 group.configure_source(fields)
 for i in 4:await process_frame
 check(not group.source_enabled)
 group.free()
 old.free()
 print("Source Stats float group: PASS (%d checks; synthetic; no pixel claim)"%checks)
 quit()
