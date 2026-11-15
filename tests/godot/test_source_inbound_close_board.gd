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
 for mode in ["normal","failure","stale","mixed","unverified","out","loading","title","owner","mixed_out","expiry","cancel"]:
  var path="user://incoming-%s-%d"%[mode,Time.get_ticks_usec()]
  var b=make_board(path);await process_frame;b.start_new();b.set_process(false);b.feedback.assets=null;b.feedback.stream_cache.clear()
  b.vendor_unlock.cancel();b.session.cycle.reset();b.session.phase="playing";b.session.paused=false;b.pause_overlay.hide()
  for id in b.session.cards.keys():b.session._remove_card(id)
  if mode=="unverified":b.catalog.data.provenance.source_commit="unknown"
  pair(b,"Grand Portal",Vector2(4,0));b.session.crafting.advance(5)
  if mode=="normal":
   var receipt=b._source_close_receipt
   var before=JSON.stringify(b.session.campaign.capture())
   var admission=preload("res://scripts/ui/source_departure_checkpoint.gd")
   check(admission.admitted(b.session,receipt.stack.id,receipt.recipe,receipt.accepted),"pure admission accepts same original receipt")
   var bad=receipt.accepted.duplicate(true);bad.scene="Unknown"
   check(not admission.admitted(b.session,receipt.stack.id,receipt.recipe,bad),"pure admission rejects destination mismatch")
   check(JSON.stringify(b.session.campaign.capture())==before,"admission does not mutate source state")
  var origin=b.session;var file=b._active_slot_path();var departure=FileAccess.get_file_as_string(file);var backup=FileAccess.get_file_as_string(file+".bak")
  var calls=[0];b.quit_callback=func():calls[0]+=1
  if mode=="out":
   check(not preload("res://scripts/ui/source_inbound_close.gd").allowed(b,b._source_inbound_close_receipt),"incoming receipt never grants outward close")
   b.queue_free();await process_frame;continue
  if mode=="loading":
   b.scene_transition.phase="commit"
   b._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
   check(calls[0]==0 and FileAccess.get_file_as_string(file)==departure,"loading boundary unchanged")
   b.queue_free();await process_frame;continue
  if mode=="mixed_out":pair(b,"Grand Portal",Vector2(8,0))
  b._process(1)
  check(b.scene_transition.phase=="in" and b.running and b.session!=origin and b.session.scene_name=="Island" and not b.session.travel_pending,"actual fully swapped incoming destination")
  if mode!="unverified":check(FileAccess.get_file_as_string(file)==departure,"before close still departed scene on disk")
  var baseline=FileAccess.get_file_as_string(file);var baseline_backup=FileAccess.get_file_as_string(file+".bak")
  if mode=="owner":b._source_inbound_close_receipt.owner=origin
  if mode=="expiry":
   check(not b._source_inbound_close_receipt.is_empty(),"receipt present only during incoming")
   b._process(1)
   check(not b.scene_transition.active() and b._source_inbound_close_receipt.is_empty(),"receipt released on natural fade completion")
   b.queue_free();await process_frame;continue
  if mode=="cancel":
   b.scene_transition.cancel();b._sync_scene_fader()
   check(b._source_inbound_close_receipt.is_empty(),"receipt released on explicit cancel sync")
   b._request_scene_change(func():pass)
   check(b._source_inbound_close_receipt.is_empty(),"unrelated new transition no receipt")
   b.queue_free();await process_frame;continue
  if mode=="stale":
   b.scene_transition.generation+=1;b._sync_scene_fader()
   check(b._source_inbound_close_receipt.is_empty(),"stale receipt released")
  if mode=="mixed":pair(b,"Grand Portal",Vector2(8,0))
  if mode=="title":b.running=false
  var original_root=b.slot_root
  if mode=="failure":
   var f=FileAccess.open(path+"/blocker",FileAccess.WRITE);f.store_string("test");f.close();b.slot_root=path+"/blocker/slots"
  var destination=b.session
  b._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
  if mode in ["stale","mixed","unverified","title","owner","mixed_out"]:
   check(calls[0]==0 and not b.quit_dispatched,"rejected incoming close "+mode)
   check(FileAccess.get_file_as_string(file)==baseline and FileAccess.get_file_as_string(file+".bak")==baseline_backup,"rejected disk/backup unchanged")
   b.queue_free();await process_frame;continue
  if mode=="failure":
   check(calls[0]==0 and b.session==destination and b.scene_transition.phase=="in" and b.notice.text.contains("SAVE FAILED"),"failure remains incoming and visibly retryable")
   check(FileAccess.get_file_as_string(file)==departure and FileAccess.get_file_as_string(file+".bak")==backup,"failure preserves departure/backup")
   b.slot_root=original_root;b._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
  check(calls[0]==1 and b.quit_dispatched and b.session==destination and not b.scene_transition.active(),"actual close saved/dispatches once")
  var saved=FileAccess.get_file_as_string(file)
  check(JSON.parse_string(saved).current_scene=="Island","destination save not old owner")
  check(FileAccess.get_file_as_string(file+".bak")==departure,"backup exact departure")
  b._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST);check(calls[0]==1,"duplicate no second close")
  var slot=b.active_slot;b.queue_free();await process_frame
  var c=make_board(path);await process_frame;c.set_process(false);c.selected_slot=slot;c._continue_game()
  check(c.running and c.session.scene_name=="Island" and not c.session.travel_pending,"fresh Continue destination")
  check(FileAccess.get_file_as_string(file)==saved,"Continue no rewrite")
  c.queue_free();await process_frame
 await create_timer(.5).timeout
 print("Incoming close: ",checks," checks ",failures," failures")
 quit(1 if failures else 0)
