extends SceneTree
const Board=preload("res://scripts/ui/board.gd")
var failures=0
var checks=0
func check(ok:bool,label:String):
 checks+=1
 if not ok: failures+=1;printerr("FAIL: ",label)
func key(pressed=true,echo=false):
 var e=InputEventKey.new();e.keycode=KEY_ESCAPE;e.pressed=pressed;e.echo=echo;return e
func owner(b) -> bool:
 return b._source_options_pause_owner() if b.has_method("_source_options_pause_owner") else false
func temporal(b) -> bool:
 return b._temporal_ui_pause_active() if b.has_method("_temporal_ui_pause_active") else b._ui_pause_active()
func _init():call_deferred("run")
func run():
 root.gui_embed_subwindows=true
 var b=Board.new();var path="user://options-owner-%d"%Time.get_ticks_usec()
 DirAccess.make_dir_recursive_absolute(path)
 b.slot_root=path+"/slots";b.options_path=path+"/options.json";b.legacy_paths.clear()
 b.options_apply_adapter=func(_p):return {"ok":true,"capabilities":{},"warnings":[]}
 root.add_child(b);await process_frame;b.set_process(false)
 var licensed=b.options_panel.source_view!=null
 b._open_options();await process_frame
 root.push_input(key());root.push_input(key(false));await process_frame
 check(not b.options_panel.visible,"Title Options retains native explicit cancel/save fallback")
 if not licensed:
  b.catalog.configure({});b.session.configure(b.catalog);b.running=true;b.session.phase="playing";b.hud.show();b.title_panel.hide()
  b._toggle_pause_menu();b._open_options();await process_frame
  check(b._ui_pause_active() and temporal(b),"source-free Options blocks time and input")
  root.push_input(key());root.push_input(key(false));await process_frame
  check(not b.options_panel.visible and b.pause_overlay.visible,"source-free Escape closes Options and retains Pause")
 for scene in (["Main","Island"] if licensed else []):
  b.start_new();b.set_process(false);b.scene_transition.cancel();b.session.scene_name=scene;b._enter_game();b.set_process(false)
  b.session.elapsed=1.0;b._toggle_pause_menu();b._open_options();await process_frame
  var o=b.options_panel;o.dirty=true
  var focus=root.gui_get_focus_owner();var pace=b.session.time_pace();var time=b.session.elapsed
  check(b.source_pause_configured and b.options_panel.source_view!=null,scene+" source panels mounted")
  var existed=FileAccess.file_exists(b.options_path)
  root.push_input(key());root.push_input(key(false));await process_frame
  check(o.visible and o.dirty and not b.pause_overlay.visible,scene+" Escape closes only Pause lock")
  check(FileAccess.file_exists(b.options_path)==existed,scene+" Escape never saves")
  check(root.gui_get_focus_owner()==focus,scene+" Options focus retained")
  check(b._ui_pause_active() and not b._allows_card_actions(),scene+" background input remains blocked")
  b.feedback.requests.request_interrupt(100)
  var wait_index=b.feedback.requests.waits.size()-1
  var wait_before=b.feedback.requests.waits[wait_index].remaining
  b._process(.1)
  check(b.feedback.requests.waits[wait_index].remaining<wait_before,scene+" settled source audio advances")
  check(b.session.elapsed>time and b.session.time_pace()==pace,scene+" settled gameplay advances at selected pace")
  var zones=b.trade_zones.duplicate(true)
  for zone in zones:
   if zone.get("kind","")=="vendor":zone.active=true
  b.vendor_unlock.sequence.on_quest_completed(zones)
  check(b.vendor_unlock.is_active(),scene+" overlapping actual vendor lock admitted")
  time=b.session.elapsed;wait_before=b.feedback.requests.waits[wait_index].remaining;b._process(.1)
  check(b.session.elapsed==time and b.feedback.requests.waits[wait_index].remaining==wait_before,scene+" vendor lock still freezes time and audio")
  b.vendor_unlock.cancel()
  o._request_reset();await process_frame
  check(temporal(b),scene+" Reset modal retains fallback temporal lock")
  o.reset_dialog.hide();await process_frame
  check(not temporal(b),scene+" Reset dismissal readmits ordinary owner")
  b.scene_transition.begin(func():pass)
  check(temporal(b),scene+" transition retains temporal lock")
  b.scene_transition.cancel()
  check(not owner(b),scene+" transition invalidates opening token permanently")
  o.request_close();b._open_options();await process_frame
  root.push_input(key());root.push_input(key(false));await process_frame
  check(o.visible and not b.pause_overlay.visible,scene+" fresh ordinary opening reacquires owner")
  root.push_input(key(true,true));root.push_input(key(false));await process_frame
  check(not b.pause_overlay.visible and o.visible,scene+" echo/release inert")
  root.push_input(key());root.push_input(key(false));await process_frame
  time=b.session.elapsed;b._process(.1)
  check(b.pause_overlay.visible and o.visible and b.session.elapsed==time,scene+" second fresh Escape reacquires pause")
  root.push_input(key());root.push_input(key(false));await process_frame
  var original=o.path;DirAccess.make_dir_recursive_absolute(path)
  var blocker=FileAccess.open(path+"/blocker",FileAccess.WRITE);blocker.store_string("test");blocker.close();o.path=path+"/blocker/options"
  o.close_button.pressed.emit()
  check(o.visible and o.dirty and not b.pause_overlay.visible,scene+" explicit Close failure retains owner+dirty")
  o.path=original
  b.session.elapsed=b.session.day_duration-.05;b._process(.1);b._process(0.0);await process_frame
  check(b.session.phase!="playing" and o.visible and not b.pause_overlay.visible,scene+" ending cycle starts behind Options without Pause")
  var phase=b.session.phase;b._handle_escape()
  check(o.visible and not b.pause_overlay.visible and b.session.phase==phase,scene+" ending Escape ignored")
  check(not b._allows_card_actions() and b._ui_pause_active(),scene+" ending Options blocks background")
  var stage=b.session.cycle.stage
  b.info_action.pressed.emit();b._advance_day()
  check(b.session.cycle.stage==stage and o.visible,scene+" Feed behind Options cannot dispatch")
  o.close_button.pressed.emit()
  check(not o.visible and FileAccess.file_exists(o.path),scene+" explicit Close saves+closes")
  b._show_title()
  check((b.get("_source_options_owner_cache") == null or b.get("_source_options_owner_cache").is_empty()),scene+" title lifecycle drops admission cache")
 if licensed:
  b.start_new();b.set_process(false);b.scene_transition.cancel();b.options_panel.open();await process_frame
  check(not owner(b) and temporal(b),"direct programmatic Options opening never mints ordinary Pause token")
  b.options_panel.request_close();b._show_title()
  b.start_new();b.set_process(false);b.scene_transition.cancel();b._toggle_pause_menu();b._open_options();await process_frame
  check(owner(b),"source opening admitted before replacement")
  var original_data=b.catalog.data
  var replaced=original_data.duplicate(true);replaced.provenance.source_commit="unknown";b.catalog.data=replaced
  check(not owner(b) and temporal(b),"replacement unknown catalog invalidates admission without weakening input")
  root.push_input(key());root.push_input(key(false));await process_frame
  check(not b.options_panel.visible and b.pause_overlay.visible,"unknown catalog retains native Cancel fallback")
  b.catalog.data=original_data;b._show_title()
 print("Options pause owner: ",checks," checks, ",failures," failures")
 b.queue_free();await process_frame;await create_timer(.5).timeout;quit(1 if failures else 0)
