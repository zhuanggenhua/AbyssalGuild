extends SceneTree
const Layout=preload("res://scripts/ui/source_info_action_layout.gd")
const Hover=preload("res://scripts/ui/card_hover_view.gd")
var checks=0
var failures=0
func check(ok,label):
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func _init():call_deferred("run")
func run():
 var data={"provenance":{"source_commit":Layout.SOURCE_COMMIT}}
 var v=Hover.new();root.add_child(v);v.set_bounds(Rect2(30,1050,400,0))
 var desc={"header":"End of Day 1","body":"Your people are hungry!"}
 v.set_descriptor(desc);var base=v.size.y
 for label in ["Feed People","Start Day","Return to Title"]:
  var size=Layout.resolve(data,label)
  check(size.x>160 and size.x<230 and is_equal_approx(size.y,73.5199966430664),label+" measured source extent")
  v.configure_source_action_height(size.y);desc.action=label;v.set_descriptor(desc)
  check(is_equal_approx(v.size.y-base,size.y),label+" reserve height")
  check(v.position.y+v.size.y==1050,label+" invariant bottom")
  desc.erase("action");v.set_descriptor(desc)
  check(is_equal_approx(v.size.y,base),label+" hidden no reserve")
 check(Layout.resolve({},"Feed People")==Vector2.ZERO,"missing provenance fallback")
 check(Layout.resolve({"provenance":false},"Feed People")==Vector2.ZERO,"invalid provenance fallback")
 check(Layout.resolve(data,"Unknown")==Vector2.ZERO,"unknown label fallback")
 check(Layout.resolve(data,"开始新的一天")==Vector2.ZERO,"unproved translated fallback")
 v.configure_source_action_height(-1);desc.action="Unknown";v.set_descriptor(desc)
 check(is_equal_approx(v.size.y-base,40),"legacy reserve unchanged")
 var adapter=preload("res://scripts/ui/source_info_action_appearance.gd").new()
 var button=Button.new();root.add_child(button)
 var old_style=StyleBoxFlat.new();old_style.border_width_left=7;old_style.content_margin_left=-1
 button.add_theme_stylebox_override("normal",old_style)
 button.add_theme_color_override("font_hover_color",Color.RED)
 var focus=button.get_theme_stylebox("focus");var minimum=button.get_minimum_size();var margin=old_style.get_margin(SIDE_LEFT)
 var record={"m_fontColor":{"r":1,"g":.9,"b":.3,"a":1},"m_fontStyle":0,"m_enableVertexGradient":0}
 check(adapter.apply(button,data,"Feed People",record),"source appearance admitted")
 check(button.get_theme_stylebox("normal") is StyleBoxEmpty,"source action has no background")
 check(button.get_theme_stylebox("normal").get_margin(SIDE_LEFT)==margin,"effective inherited margin retained")
 check(button.get_minimum_size()==minimum,"native minimum unchanged")
 check(button.get_theme_stylebox("focus")==focus,"focus decoration unchanged")
 var cached=button.get_theme_stylebox("normal")
 var notifications=[0]
 button.theme_changed.connect(func():notifications[0]+=1)
 adapter.apply(button,data,"Start Day",record)
 check(button.get_theme_stylebox("normal")==cached,"no repeated style allocation")
 check(notifications[0]==0,"unchanged sync emits no theme change")
 var recolored=record.duplicate(true);recolored.m_fontColor.g=.5
 adapter.apply(button,data,"Start Day",recolored)
 check(button.get_theme_color("font_color").g==.5,"changed source tint applied")
 adapter.apply(button,data,"Start Day",record)
 for key in adapter.COLORS:check(button.get_theme_color(key).is_equal_approx(Color(1,.9,.3,1)),"source state tint "+key)
 check(not adapter.apply(button,data,"Unknown",record),"unknown appearance fallback")
 check(button.get_theme_stylebox("normal")==old_style and button.has_theme_stylebox_override("normal"),"prior style identity restored")
 check(button.get_theme_color("font_hover_color")==Color.RED,"prior color override restored")
 check(not button.has_theme_color_override("font_color"),"inherited color restored")
 for bad in [{},{"m_fontColor":false},{"m_fontColor":{"r":1,"g":INF,"b":0,"a":1},"m_fontStyle":0,"m_enableVertexGradient":0}]:
  check(not adapter.apply(button,data,"Feed People",bad),"invalid source appearance rejected")
 for field in ["m_fontStyle","m_enableVertexGradient"]:
  var bad=record.duplicate(true);bad[field]=1
  check(not adapter.apply(button,data,"Feed People",bad),"unproved font state rejected "+field)
 adapter.apply(button,data,"Feed People",record)
 check(not adapter.apply(button,{},"Feed People",record),"missing source restores")
 check(button.get_theme_stylebox("normal")==old_style,"restoration not sticky")
 adapter.apply(button,data,"Feed People",record)
 check(not adapter.apply(button,data,"Feed People",{}),"missing replacement record restores active style")
 adapter.apply(button,data,"Feed People",record)
 var replacement=Theme.new();var replacement_style=StyleBoxFlat.new();replacement_style.border_width_right=9
 replacement.set_stylebox("hover","Button",replacement_style);button.theme=replacement
 adapter.reset(button)
 adapter.apply(button,data,"Feed People",record)
 check(button.get_theme_stylebox("hover").get_margin(SIDE_RIGHT)==9,"replacement inherited effective margin")
 adapter.apply(button,data,"Unknown",record)
 check(button.get_theme_stylebox("hover")==replacement_style,"replacement inherited theme restored")
 button.queue_free()
 v.queue_free();await process_frame
 print("Source Info action: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
