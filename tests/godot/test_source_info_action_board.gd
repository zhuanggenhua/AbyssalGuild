extends SceneTree
const Board=preload("res://scripts/ui/board.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
 func play_event(_kind:String)->bool:return false
 func play_music()->bool:return false
var checks=0
var failures=0
var rows=[]
func check(x,s):
 checks+=1
 if not x:failures+=1;printerr("FAIL ",s)
func capture(b,label,expected):
 b._refresh()
 if label=="ordinary hover":b.info_requests.submit("card",0,{"header":"Wood","body":"A sturdy piece of wood."})
 b._sync_source_info()
 check(b.info_action.visible==(expected!=""),label+" visibility")
 check(b.info_action.text==expected,label+" label")
 if expected!="":
  var widths={"Feed People":210.58999633789062,"Start Day":164.5399932861328,"Return to Title":227.07000732421875}
  check(b.info_action.size.is_equal_approx(Vector2(widths[expected],73.5199966430664)),label+" exact outer extent")
  check(b.info_action.position.is_equal_approx(b.card_hover.bottom_anchor-Vector2(0,73.5199966430664)),label+" fixed bottom and left")
  var hit=b.info_action.get_global_rect()
  check(hit.has_point(hit.position+Vector2(.1,.1)) and hit.has_point(hit.end-Vector2(.1,.1)),label+" first/last interior hit bounds")
  check(not hit.has_point(hit.position-Vector2(.1,0)) and not hit.has_point(hit.end+Vector2(.1,0)),label+" exterior not in hit rect")
 rows.append({"case":label,"phase":b.session.phase,"stage":b.session.cycle.stage,"descriptor":b.card_hover.descriptor,"visible":b.info_action.visible,"action_position":[b.info_action.position.x,b.info_action.position.y],"action_size":[b.info_action.size.x,b.info_action.size.y],"parent_bottom":[b.card_hover.bottom_anchor.x,b.card_hover.bottom_anchor.y],"panel_height":b.card_hover.size.y,"mouse_filter":b.info_action.mouse_filter})
func _init():call_deferred("run")
func run():
 var b=Board.new();b.feedback.free();b.feedback=SilentFeedback.new();b.slot_root="user://action-%d/slots"%Time.get_ticks_usec();b.options_path=b.slot_root+"/options";b.legacy_paths.clear();root.add_child(b);await process_frame;b.start_new();b.set_process(false)
 b.info_requests.submit("card",0,{"header":"Wood","body":"A sturdy piece of wood."})
 capture(b,"ordinary hover","")
 check(b.card_hover.descriptor.get("header","")=="Wood","ordinary actual descriptor remains")
 check(b.session.cycle.request_end_day(),"real end day request")
 capture(b,"end day", "Feed People")
 # Feed actual session with test-spawned Villager+Berry; no phase fabrication.
 b.session.spawn_card(b.catalog.find_by_name("Villager"),Vector2(-3,0))
 for i in 3:b.session.spawn_card(b.catalog.find_by_name("Berry"),Vector2(3+i,0))
 b.info_action.pressed.emit()
 capture(b,"feeding action consumed","")
 for i in 100:
  if b.session.phase=="ready":break
  b.session.cycle.advance(2.0)
 capture(b,"completed real cycle", "Start Day")
 b.info_action.pressed.emit()
 capture(b,"start action consumed","")
 # Independent fresh session's starter pack has no people. Its actual feeding path ends game.
 b.start_new();b.set_process(false);check(b.session.cycle.request_end_day(),"second actual end")
 b.session.cycle.begin_feeding()
 capture(b,"no people actual game over", "Return to Title")
 # Observe existing resize mapping, not source framebuffer/ownership acceptance.
 for extent in [Vector2(960,540),Vector2(480,1080)]:
  b.hud.size=extent;b._configure_source_hud();capture(b,"resize "+str(extent),"Return to Title")
  check(is_equal_approx(b.source_hud.scale.x,extent.y/1080),"height-scale mapping")
 # Never press Return to Title (archive is outside this geometry test).
 if OS.get_environment("ACTION_NEGATIVE")=="1":
  b.queue_free();await process_frame;print("NEGATIVE ",checks," checks ",failures," failures");quit(1 if failures else 0);return
 # Explicit unknown label and missing-lock fallbacks remain legacy, reset not sticky.
 b.session.phase="playing";b.info_requests.submit("day_cycle",2,{})
 b.info_requests.submit("probe",3,{"header":"Probe","body":"Body","action":"Unknown"});b._sync_source_info()
 check(is_equal_approx(b.card_hover.source_action_height,-1),"unknown action resets reservation")
 check(b.info_action.position.x==b.card_hover.bottom_anchor.x+20,"unknown retains legacy left")
 b.info_requests.submit("probe",3,{"header":"Probe","body":"Body","action":"Feed People"})
 var provenance=b.catalog.data.provenance.duplicate(true);b.catalog.data.provenance={};b._sync_source_info()
 check(b.card_hover.source_action_height==-1,"missing source lock fallback")
 b.catalog.data.provenance=provenance;b._sync_source_info()
 check(is_equal_approx(b.card_hover.source_action_height,73.5199966430664),"source restored without descriptor text change")
 if not OS.get_environment("ACTION_OUTPUT").is_empty():
  var f=FileAccess.open(OS.get_environment("ACTION_OUTPUT"),FileAccess.WRITE);f.store_string(JSON.stringify(rows,"  "))
 b.queue_free();await process_frame;print("Action geometry: ",checks," checks, ",failures," failures");quit(1 if failures else 0)
