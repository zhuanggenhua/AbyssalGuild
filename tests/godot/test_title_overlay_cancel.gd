extends SceneTree
const Board=preload("res://scripts/ui/board.gd")
var checks=0
var failures=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",label)
func cancel(east=false,pressed=true,echo=false):
 if east:
  var e=InputEventJoypadButton.new();e.button_index=JOY_BUTTON_B;e.pressed=pressed;return e
 var e=InputEventKey.new();e.keycode=KEY_ESCAPE;e.pressed=pressed;e.echo=echo;return e
func admitted(b):return b._source_title_overlay_cancel() if b.has_method("_source_title_overlay_cancel") else false
func _init():call_deferred("run")
func run():
 root.gui_embed_subwindows=true
 var b=Board.new();var path="user://title-overlay-%d"%Time.get_ticks_usec();DirAccess.make_dir_recursive_absolute(path)
 b.slot_root=path+"/slots";b.options_path=path+"/options.json";b.legacy_paths.clear()
 b.options_apply_adapter=func(_plan):return {"ok":true,"capabilities":{},"warnings":[]}
 root.add_child(b);await process_frame;b.set_process(false)
 var sourced=b.source_title!=null
 for dest in ["preferences","saves"]:
  var opener=b.title_new_button if dest=="preferences" else b.title_load_button
  var close=b.title_cancel_button if dest=="preferences" else b.title_back_button
  var overlay=b.title_preferences if dest=="preferences" else b.title_saves
  opener.pressed.emit();await process_frame
  if not sourced:
   root.push_input(cancel());await process_frame
   check(not overlay.visible and b.title_navigation.destination=="home",dest+" source-free Cancel retains shortcut")
   continue
  check(admitted(b) and overlay.visible,dest+" real locked Home opener owns source overlay")
  var focus=root.gui_get_focus_owner();var pending=b.title_navigation.new_game_pending
  for event in [cancel(),cancel(false,false),cancel(false,true,true),cancel(true),cancel(true,false)]:root.push_input(event);await process_frame
  check(overlay.visible and root.gui_get_focus_owner()==focus and b.title_navigation.destination==dest,dest+" raw Escape/East retains overlay and focus")
  check(b.title_navigation.new_game_pending==pending and b.active_slot==0 and not b.running and not FileAccess.file_exists(b.slots.slot_path(1)),dest+" raw Cancel neither commits nor invalidates transaction")
  b.archive_dialog.popup_centered();await process_frame
  check(not admitted(b),dest+" archive modal owns input instead")
  b.archive_dialog.hide();await process_frame
  check(admitted(b),dest+" modal dismissal preserves legitimate opening")
  b._open_options();await process_frame
  check(not admitted(b),dest+" Options overlap excluded")
  b.options_panel.request_close();await process_frame
  check(admitted(b),dest+" explicit Options Close reveals same source owner")
  var other=b.title_saves if dest=="preferences" else b.title_preferences
  other.show();check(not admitted(b),dest+" simultaneous overlays excluded")
  other.hide();check(admitted(b),dest+" original owner returns after unsupported overlap removed")
  close.pressed.emit();b._confirm_title_new_game();await process_frame
  check(not overlay.visible and b.active_slot==0 and not b.scene_transition.active(),dest+" explicit close invalidates stale Confirm and allocates nothing")
  b.title_navigation.open(dest);b._sync_title_destination();await process_frame
  check(not admitted(b),dest+" direct destination visibility cannot manufacture owner")
  b._handle_escape();check(not overlay.visible,dest+" unsupported visibility retains native Cancel")
  opener.pressed.emit();await process_frame
  overlay.hide();overlay.show();check(not admitted(b),dest+" hide/show cannot retain source opening token")
  close.pressed.emit();opener.pressed.emit();await process_frame
  check(admitted(b),dest+" actual opener readmits after explicit cleanup")
  b.scene_transition.begin(func():pass);check(not admitted(b),dest+" transition revokes token")
  b.scene_transition.cancel();check(not admitted(b),dest+" no regeneration after transition")
  close.pressed.emit()
  opener.pressed.emit();await process_frame
  var data=b.catalog.data;b.catalog.data=data.duplicate(true);b.catalog.data.provenance.source_commit="unknown"
  check(not admitted(b),dest+" source replacement revokes token")
  b._handle_escape();check(not overlay.visible,dest+" replacement retains fallback close")
  b.catalog.data=data
 print("Title overlay cancel: %d checks, %d failures"%[checks,failures])
 b.queue_free();await process_frame;await create_timer(.5).timeout;quit(1 if failures else 0)
