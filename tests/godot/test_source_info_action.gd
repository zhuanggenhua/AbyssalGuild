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
 v.queue_free();await process_frame
 print("Source Info action: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
