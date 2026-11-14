extends Container
## Bounded source HorizontalLayoutGroup; native whole-group fallback.
var elements:Array[Control]=[]
var source_parent=Control.new()
var native_group=HBoxContainer.new()
var source_enabled=false
var source_contract_valid=false
var syncing=false
func _init():
 source_parent.mouse_filter=Control.MOUSE_FILTER_IGNORE
 add_child(source_parent)
 add_child(native_group)
 native_group.add_theme_constant_override("separation",0)
 clip_contents=false
func add_element(c:Control):
 elements.append(c)
 native_group.add_child(c)
 if c.has_signal("layout_contract_changed"):
  c.layout_contract_changed.connect(resort,CONNECT_DEFERRED)
 resort.call_deferred()
func configure_source(fields:Dictionary):
 var required={"m_ChildAlignment":3,"m_ChildControlWidth":1,"m_ChildControlHeight":0,"m_ChildForceExpandWidth":0,"m_ChildForceExpandHeight":0,"m_ChildScaleWidth":0,"m_ChildScaleHeight":0,"m_Spacing":0,"m_ReverseArrangement":0,"m_HorizontalFit":2,"m_VerticalFit":0}
 source_contract_valid=true
 for key in required:
  if fields.get(key)!=required[key]:source_contract_valid=false
 var padding=fields.get("m_Padding")
 if not padding is Dictionary:source_contract_valid=false
 else:
  for key in ["m_Left","m_Right","m_Top","m_Bottom"]:
   if padding.get(key)!=(34 if key=="m_Right" else 0):source_contract_valid=false
 resort.call_deferred()
func _notification(what):
 if what in [NOTIFICATION_RESIZED,NOTIFICATION_SORT_CHILDREN]:resort()
func _get_minimum_size()->Vector2:
 if source_enabled:
  var width=0.0
  for c in elements:width+=c.get_combined_minimum_size().x
  return Vector2(width,50)
 return native_group.get_combined_minimum_size() if is_instance_valid(native_group) else Vector2.ZERO
func resort():
 if syncing or not is_inside_tree():return
 syncing=true
 var eligible=source_contract_valid and elements.size()==6
 for i in elements.size():
  var c=elements[i]
  if i%2==1:
   if not c.has_method("set_group_mode") or not c.contract.get("ok",false):eligible=false
  elif not c is TextureRect or c.custom_minimum_size!=Vector2(64,30) or c.texture==null or c.texture.get_size()!=Vector2(64,64) or c.stretch_mode!=TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
   eligible=false
 source_enabled=eligible
 for i in elements.size():
  var c=elements[i]
  if i%2==1 and c.has_method("set_group_mode"):c.set_group_mode(eligible)
  var parent=source_parent if eligible else native_group
  if c.get_parent()!=parent:c.reparent(parent,false)
 source_parent.visible=eligible
 native_group.visible=not eligible
 source_parent.size=size
 native_group.size=size
 if eligible:
  var pos=0.0 # Unity's running float position; never an integer HBox offset.
  for c in elements:
   var extent=c.get_combined_minimum_size()
   c.position=Vector2(pos,(50.0-extent.y)*0.5)
   c.size=extent
   pos+=extent.x
 update_minimum_size()
 syncing=false
