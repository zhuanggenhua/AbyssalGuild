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
func click_at(index:int, down:bool, position:Vector2):
 var motion=InputEventMouseMotion.new();motion.position=position;motion.global_position=position;root.push_input(motion,true)
 var event=InputEventMouseButton.new();event.button_index=index;event.pressed=down;event.position=position;event.global_position=position;root.push_input(event,true)
func _init():call_deferred("run")
func run():
 root.gui_embed_subwindows=true
 var b=Board.new();var path="user://title-overlay-%d"%Time.get_ticks_usec();DirAccess.make_dir_recursive_absolute(path)
 b.slot_root=path+"/slots";b.options_path=path+"/options.json";b.legacy_paths.clear()
 b.options_apply_adapter=func(_plan):return {"ok":true,"capabilities":{},"warnings":[]}
 root.add_child(b);await process_frame;b.set_process(false)
 var sourced=b.source_title!=null
 for role in ["new","load","options","cancel","saves_close"]:
  var controls={"new":b.title_new_button,"load":b.title_load_button,"options":b.title_options_button,"cancel":b.title_cancel_button,"saves_close":b.title_back_button}
  check(controls[role].button_mask==(7 if sourced else MOUSE_BUTTON_MASK_LEFT),role+" pointer admission is source only")
 for button in [b.title_quit_button,b.title_confirm_button,b.archive_all_button,b.continue_button]:
  check(button.button_mask==MOUSE_BUTTON_MASK_LEFT,"transaction scope unchanged")
 if sourced:
  for role in ["new","load"]:
   var opener=b.title_new_button if role=="new" else b.title_load_button
   var close=b.title_cancel_button if role=="new" else b.title_back_button
   var overlay=b.title_preferences if role=="new" else b.title_saves
   for index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
    var pos=opener.get_global_rect().get_center()
    click_at(index,true,pos);check(not overlay.visible,role+" no opening on press")
    click_at(index,false,pos);await process_frame
    check(overlay.visible,role+" opens on matching release")
    pos=close.get_global_rect().get_center()
    click_at(index,true,pos);check(overlay.visible,role+" no close on press")
    click_at(index,false,pos);await process_frame
    check(not overlay.visible and not b.running and b.active_slot==0,role+" safe close on release")
  for index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
   var pos=b.title_options_button.get_global_rect().get_center()
   click_at(index,true,pos);check(not b.options_panel.visible,"options no opening on press")
   click_at(index,false,pos);await process_frame
   check(b.options_panel.visible,"options opens on release")
   b.options_panel.request_close();await process_frame
  var release_pos=b.title_new_button.get_global_rect().get_center()
  click_at(MOUSE_BUTTON_RIGHT,true,release_pos);click_at(MOUSE_BUTTON_RIGHT,false,Vector2(-100,-100));await process_frame
  check(not b.title_preferences.visible,"release outside cannot open title overlay")
  b.archive_dialog.popup_centered();await process_frame
  click_at(MOUSE_BUTTON_RIGHT,true,release_pos);click_at(MOUSE_BUTTON_RIGHT,false,release_pos);await process_frame
  check(not b.title_preferences.visible,"modal continues to own pointer input")
  b.archive_dialog.hide();await process_frame
  var original=b.catalog.data
  var bad=original.duplicate(true);bad.provenance.source_commit="wrong"
  var mask=b.title_new_button.button_mask;b.title_new_button.button_mask=MOUSE_BUTTON_MASK_LEFT
  check(not b.source_title.admit_navigation_pointer(bad,"new",b.title_new_button),"wrong source rejected")
  check(b.title_new_button.button_mask==MOUSE_BUTTON_MASK_LEFT,"rejection does not widen input")
  bad=original.duplicate(true)
  for scene in bad.scenes:
   if scene.name=="Title":
    for doc in scene.documents:
     if str(doc.file_id)=="2057193291":doc.fields.m_Enabled=0
  check(not b.source_title.admit_navigation_pointer(bad,"new",b.title_new_button),"disabled TextButton rejected")
  b.title_new_button.button_mask=mask
  check(not b.source_title.admit_navigation_pointer(original,"quit",b.title_quit_button),"quit cannot be admitted")
  check(not b.source_title.admit_navigation_pointer(original,"new",b.title_load_button),"wrong mounted node rejected")
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
