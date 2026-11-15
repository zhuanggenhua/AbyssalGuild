extends SceneTree
const Board=preload("res://scripts/ui/board.gd")
var checks=0
var failures=0
func check(v,s):
 checks+=1
 if not v:failures+=1;printerr("FAIL ",s)
func _init():call_deferred("run")
func make_board(path):
 var b=Board.new();b.slot_root=path+"/slots";b.options_path=path+"/options";b.legacy_paths.clear();root.add_child(b);return b
func pair(b,name,pos):
 var id=b.session.spawn_card(b.catalog.find_by_name(name),pos,-1,{"refuse_attach":true})
 var worker=b.session.spawn_card(b.catalog.find_by_name("Villager"),pos+Vector2(1,0),-1,{"refuse_attach":true})
 check(b.session.move_to_stack(worker,b.session.cards[id].stack_id),"pair")
 return b.session.stacks[b.session.cards[id].stack_id]
func run():
 for mode in ["plain","tail","failure","stale","mixed","inbound","unverified","paused","restore_failure"]:
  var path="user://close-%s-%d"%[mode,Time.get_ticks_usec()]
  var b=make_board(path);await process_frame;b.start_new();b.set_process(false);b.feedback.assets=null;b.feedback.stream_cache.clear()
  b.vendor_unlock.cancel();b.session.cycle.reset();b.session.phase="playing";b.session.paused=false;b.pause_overlay.hide()
  for id in b.session.cards.keys():b.session._remove_card(id)
  var tail=null
  if mode in ["tail","failure"]:tail=pair(b,"Wood",Vector2(-4,0));b.session.crafting.advance(2)
  if mode=="unverified":b.catalog.data.provenance.source_commit="unknown"
  var portal=pair(b,"Grand Portal",Vector2(4,0));var travelers=portal.card_ids.duplicate()
  b.session.crafting.advance(5)
  check(b.scene_transition.phase=="out" and b.session.travel_pending,"pending ordinary travel")
  var owner=b.session;var destination=b.scene_transition._commit.get_bound_arguments()[1]
  var arrival_before=JSON.stringify(destination.campaign.capture())
  var file=b._active_slot_path();var departure=FileAccess.get_file_as_string(file);var backup=FileAccess.get_file_as_string(file+".bak")
  if tail!=null:check(tail.progress==7,"actual same-frame tail advanced beyond departure2")
  if mode=="paused":b.pause_overlay.show()
  if mode=="stale":b.scene_transition.generation+=1
  if mode=="mixed":pair(b,"Grand Portal",Vector2(8,0))
  if mode=="inbound":b._process(1)
  else:b._process(.25)
  var calls=[0];b.quit_callback=func():calls[0]+=1
  var original_root=b.slot_root
  if mode=="failure":
   var f=FileAccess.open(path+"/blocker",FileAccess.WRITE);f.store_string("test");f.close();b.slot_root=path+"/blocker/slots"
  var day_before=b.session.day
  if mode=="restore_failure":b.session.day=-1
  b._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
  if mode=="restore_failure":
   check(calls[0]==0 and b.session==owner and b.scene_transition.phase=="out", "rejected snapshot remains retryable")
   check(b.notice.text.contains("SAVE FAILED"),"rejected snapshot visible error")
   check(FileAccess.get_file_as_string(file)==departure and FileAccess.get_file_as_string(file+".bak")==backup,"restore rejection no disk write")
   b.session.day=day_before;b._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
  if mode in ["stale","mixed","inbound","unverified","paused"]:
   check(calls[0]==0 and not b.quit_dispatched,"unsupported close unchanged "+mode)
   check(FileAccess.get_file_as_string(file)==departure,"unsupported disk untouched "+mode)
   b.queue_free();await process_frame;continue
  if mode=="failure":
   check(calls[0]==0 and b.session==owner and b.scene_transition.phase=="out" and b.session.travel_pending,"failure remains live/pending")
   check(b.notice.text.contains("SAVE FAILED"),"failure notice")
   check(FileAccess.get_file_as_string(file)==departure and FileAccess.get_file_as_string(file+".bak")==backup,"failure disk/backup preserved")
   b.slot_root=original_root;b._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
  check(calls[0]==1 and b.quit_dispatched and not b.scene_transition.active(),"close saved and dispatched exactly once "+mode)
  check(b.session==owner and JSON.stringify(destination.campaign.capture())==arrival_before,"live owner and staged destination untouched")
  var saved=JSON.parse_string(FileAccess.get_file_as_string(file))
  check(saved.current_scene=="Main","close persists old scene")
  var ids=[]
  for row in saved.scenes.Main.session.cards:ids.append(int(row.id))
  check(travelers[0] not in ids and travelers[1] not in ids,"consumed original travelers absent")
  if tail!=null:
   var progress=-1
   for row in saved.scenes.Main.session.stacks:
    if int(row.id)==tail.id:progress=row.progress
   check(progress==7,"latest tail progress persisted not departure2")
  check(FileAccess.get_file_as_string(file+".bak")==departure,"backup keeps first departure bytes")
  b._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST);check(calls[0]==1,"duplicate close ignored")
  var slot=b.active_slot;b.queue_free();await process_frame
  var c=make_board(path);await process_frame;c.set_process(false);c.selected_slot=slot;c._continue_game()
  check(c.running and c.session.scene_name=="Main","fresh Continue old scene")
  c._process(.1);check(not c.session.travel_pending and not c.scene_transition.active(),"no duplicate travel after Continue")
  c.queue_free();await process_frame
 await create_timer(0.5).timeout
 print("Precommit close: ",checks," checks ",failures," failures")
 quit(1 if failures else 0)
