extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String):
 checks += 1
 if not ok: failures += 1; printerr("FAIL: ",label)
func key(pressed=true, echo=false):
 var e=InputEventKey.new();e.keycode=KEY_ESCAPE;e.pressed=pressed;e.echo=echo;return e
func east(pressed=true):
 var e=InputEventJoypadButton.new();e.button_index=JOY_BUTTON_B;e.pressed=pressed;return e
func admitted(b):
 return b._source_title_options_cancel() if b.has_method("_source_title_options_cancel") else false
func _init(): call_deferred("run")
func run():
 root.gui_embed_subwindows=true
 var b=Board.new();var path="user://title-options-%d"%Time.get_ticks_usec()
 DirAccess.make_dir_recursive_absolute(path)
 b.slot_root=path+"/slots";b.options_path=path+"/options.json";b.legacy_paths.clear()
 b.options_apply_adapter=func(_plan):return {"ok":true,"capabilities":{},"warnings":[]}
 root.add_child(b);await process_frame;b.set_process(false)
 var o=b.options_panel
 var sourced=b.source_title!=null and o.source_view!=null
 b.title_options_button.pressed.emit();await process_frame
 check(o.visible and not b.running,"real Title Home Options button opens")
 if not sourced:
  root.push_input(key());root.push_input(key(false));await process_frame
  check(not o.visible and FileAccess.file_exists(o.path),"native fallback Escape still saves and closes")
 else:
  check(admitted(b),"locked source opening admitted")
  o._volume_changed(.37,"sfx")
  check(FileAccess.file_exists(o.path) and not o.dirty,"ordinary adjustment still saves immediately")
  var bytes=FileAccess.get_file_as_string(o.path);var focus=root.gui_get_focus_owner()
  for event in [key(),key(false),key(true,true),east(),east(false),key()]:
   root.push_input(event);await process_frame
  check(o.visible and root.gui_get_focus_owner()==focus,"fresh/repeat/release Escape and East retain Options focus")
  check(FileAccess.get_file_as_string(o.path)==bytes and not o.dirty,"raw Cancel does not save or change options")
  check(not b.running and not b.pause_overlay.visible,"raw Title Cancel cannot manufacture gameplay Pause")
  DirAccess.make_dir_absolute(o.path+".tmp")
  o._volume_changed(.43,"sfx")
  var status=o.status_label.text
  check(o.dirty and "NOT saved" in status,"actual adjustment write failure retains dirty state")
  root.push_input(east());root.push_input(east(false));await process_frame
  check(o.visible and o.dirty and o.status_label.text==status and FileAccess.get_file_as_string(o.path)==bytes,"Cancel never retries failed save")
  o.close_button.pressed.emit()
  check(o.visible and o.dirty and "Could not save" in o.status_label.text,"explicit mounted Close preserves failure safety")
  DirAccess.remove_absolute(o.path+".tmp");o.close_button.pressed.emit();await process_frame
  check(not o.visible and not o.dirty and FileAccess.get_file_as_string(o.path)!=bytes,"explicit Close retry saves and closes")
  b.title_options_button.pressed.emit();await process_frame
  o._request_reset();await process_frame
  check(not admitted(b),"Reset modal owns its own Cancel")
  o.reset_dialog.hide();await process_frame
  check(admitted(b),"Reset dismissal retains same original Title opening")
  b.scene_transition.begin(func():pass)
  check(not admitted(b),"transition invalidates Title owner")
  b.scene_transition.cancel()
  check(not admitted(b),"visibility cannot regenerate revoked owner")
  o.request_close();o.open();await process_frame
  check(not admitted(b),"direct Options.open is not original Home button ownership")
  b._handle_escape();check(not o.visible,"direct unsupported open retains fallback cancel")
  b.title_options_button.pressed.emit();await process_frame
  var data=b.catalog.data;b.catalog.data=data.duplicate(true);b.catalog.data.provenance.source_commit="unknown"
  check(not admitted(b),"catalog replacement invalidates owner")
  b._handle_escape();check(not o.visible,"unknown source retains native Cancel close")
  b.catalog.data=data
  b._open_title_preferences();b._open_options();await process_frame
  check(not admitted(b),"Preferences not broadened into Home ownership")
  b._handle_escape();check(not o.visible,"Preferences overlay Options retains existing fallback")
 print("Title Options cancel: %d checks, %d failures"%[checks,failures])
 b.queue_free();await process_frame;await create_timer(.5).timeout;quit(1 if failures else 0)
