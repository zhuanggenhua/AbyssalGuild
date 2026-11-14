extends SceneTree
const Adapter=preload("res://scripts/ui/options_adapter.gd")
const Options=preload("res://scripts/model/user_options.gd")
const PanelUI=preload("res://scripts/ui/options_panel.gd")
class TraceDisplay extends RefCounted:
 var display_name:="trace_fake"
 var clock:=1000
 var mode:=DisplayServer.WINDOW_MODE_FULLSCREEN
 var size:=Vector2i(1364,1024)
 var screen:=Vector2i(1364,1024)
 var refuse:=false
 var sets:Array=[]
 var vsync:=DisplayServer.VSYNC_ENABLED
 func name()->String:return display_name
 func ticks_msec()->int:return clock
 func set_window_mode(value:int)->void:
  sets.append(value)
  if refuse:return
  mode=DisplayServer.WINDOW_MODE_MAXIMIZED if value==DisplayServer.WINDOW_MODE_WINDOWED else value
 func get_window_mode()->int:return mode
 func get_window_size()->Vector2i:return size
 func get_screen_size()->Vector2i:return screen
 func set_vsync(value:int)->void:vsync=value
 func get_vsync()->int:return vsync
 func set_frame_cap(_value:int)->void:pass
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",label)
func status(result:Dictionary)->String:return str(result.get("window_mode",{}).get("status","missing"))
func poll(adapter,result:Dictionary)->Dictionary:
 return adapter.poll_window_application(result) if adapter.has_method("poll_window_application") else result
func tick(panel)->void:
 if panel.has_method("_process"):panel._process(0)
func _init():call_deferred("run")
func run()->void:
 var options=Options.new();options.configure();options.values.fullscreen="windowed"
 var display=TraceDisplay.new();var adapter=Adapter.new();adapter.configure(null,display)
 var result:Dictionary=adapter.apply(options.application_plan())
 check(status(result)=="pending","recorded MAXIMIZED transition begins Pending, not final rejection")
 check(not "\n".join(result.warnings).contains("did not apply"),"old false rejection is absent while pending")
 display.clock=1100;display.mode=DisplayServer.WINDOW_MODE_WINDOWED;display.size=Vector2i(1280,800)
 result=poll(adapter,result)
 check(status(result)=="pending","one matching observation alone is not stable success")
 display.clock=1250;result=poll(adapter,result)
 check(status(result)=="succeeded" and result.applied.has("window_mode"),"delayed actual Windowed converges to Succeeded")
 check(not "\n".join(result.warnings).contains("did not apply"),"success removes window warning without retrying request")
 check(display.sets.size()==1,"observation never issues a second window command")
 var already:Dictionary=adapter.apply(options.application_plan())
 check(status(already)=="succeeded" and display.sets.size()==1,"stable same-target refresh does not reissue")
 # Same request cannot be kept pending forever by volume/refresh calls.
 options.values.fullscreen="borderless";display.refuse=true
 result=adapter.apply(options.application_plan());var request=result.get("window_mode",{}).get("id",-1)
 display.clock+=1800
 var duplicate:Dictionary=adapter.apply(options.application_plan())
 check(duplicate.get("window_mode",{}).get("id",-2)==request,"same-target refresh keeps generation")
 check(display.sets.size()==2,"same-target pending refresh is not resubmitted")
 display.clock+=250;result=poll(adapter,duplicate)
 check(status(result)=="failed" and result.get("window_mode",{}).get("reason")=="timeout","genuine persistent refusal has bounded timeout failure")
 check("\n".join(result.warnings).contains("embedded preview") and not result.applied.has("window_mode"),"timeout retains real refusal and embedded explanation")
 check(options.values.fullscreen=="borderless","failed application does not rewrite desired preference")
 var sets_after_failure:int=display.sets.size()
 var failed_refresh:Dictionary=adapter.apply(options.application_plan("sfx"))
 check(status(failed_refresh)=="failed" and display.sets.size()==sets_after_failure,"unrelated preference apply preserves terminal refusal without retry")
 # Cached fullscreen enum before resize is not full physical success.
 display.refuse=false;display.mode=DisplayServer.WINDOW_MODE_WINDOWED;display.size=Vector2i(1280,800)
 display.clock+=1;result=adapter.apply(options.application_plan("fullscreen"))
 display.clock+=200;result=poll(adapter,result)
 check(status(result)=="pending","fullscreen enum with old client dimensions stays pending")
 display.size=display.screen;display.clock+=1;result=poll(adapter,result)
 display.clock+=150;result=poll(adapter,result)
 check(status(result)=="succeeded","fullscreen requires observed screen-sized client stability")
 # New requests invalidate stale completion objects, including rapid A -> B -> A.
 options.values.fullscreen="windowed";display.clock+=1
 var old_a:Dictionary=adapter.apply(options.application_plan())
 options.values.fullscreen="borderless";display.clock+=1
 var old_b:Dictionary=adapter.apply(options.application_plan())
 options.values.fullscreen="windowed";display.clock+=1
 var newest:Dictionary=adapter.apply(options.application_plan())
 check(poll(adapter,old_a).is_empty() and poll(adapter,old_b).is_empty(),"stale A/B completions cannot publish into newest A")
 if adapter.has_method("cancel_window_observation"):adapter.cancel_window_observation(int(old_a.window_mode.id))
 check(not poll(adapter,newest).is_empty(),"stale cancellation cannot cancel newer request")
 display.mode=DisplayServer.WINDOW_MODE_WINDOWED;display.size=Vector2i(1280,800);display.clock+=1;newest=poll(adapter,newest)
 display.clock+=150;newest=poll(adapter,newest)
 check(status(newest)=="succeeded","latest rapid-switch request alone can succeed")
 # Missing the observation deadline cannot be relabelled success by a late poll.
 var slow_display=TraceDisplay.new();var slow_adapter=Adapter.new();slow_adapter.configure(null,slow_display)
 options.values.fullscreen="borderless"
 var late:Dictionary=slow_adapter.apply(options.application_plan())
 slow_display.clock+=2500;late=poll(slow_adapter,late)
 check(status(late)=="failed" and late.get("window_mode",{}).get("reason")=="timeout","late first observation cannot claim within-deadline success")
 # Unsupported/no-display remains side-effect free.
 var no_display=TraceDisplay.new();no_display.display_name="headless"
 var no_adapter=Adapter.new();no_adapter.configure(null,no_display)
 var unsupported:Dictionary=no_adapter.apply(options.application_plan())
 check(status(unsupported)=="unsupported" and no_display.sets.is_empty(),"headless Unsupported causes no window request")
 await panel_checks()
 print("Window mode observation: %d/%d passed"%[checks-failures,checks]);quit(0 if failures==0 else 1)
func panel_checks()->void:
 var p=PanelUI.new();root.add_child(p)
 var d=TraceDisplay.new();var a=Adapter.new();a.configure(null,d)
 var path="user://mode-observation/options.json"
 DirAccess.make_dir_recursive_absolute(path.get_base_dir())
 p.configure(a.apply,[],path)
 d.clock+=150;tick(p)
 p.open();p._cycle("fullscreen")
 check(p.status_label.text.contains("Preferences saved"),"pending apply remains distinct from successful preference save")
 check(p.model.values.fullscreen=="windowed","normal panel cycle selects Windowed")
 var reload=Options.new();reload.configure();var loaded:Dictionary=reload.load_file(path)
 check(loaded.ok and reload.values.fullscreen=="windowed","pending preference persists for process restart")
 p.request_close();check(not p.visible,"Close can save while native observation remains pending")
 d.mode=DisplayServer.WINDOW_MODE_WINDOWED;d.size=Vector2i(1280,800);d.clock+=1;tick(p)
 d.clock+=150;tick(p)
 check(status(p.last_application)=="succeeded","hidden live panel observes success")
 check(not p.status_label.text.contains("did not apply") and p.status_label.text.contains("Preferences saved"),"later completion preserves save result and updates only application summary")
 # Save failure must not be erased by a later native success.
 p.open();DirAccess.make_dir_recursive_absolute(path+".tmp")
 p._cycle("fullscreen")
 check(p.dirty and p.status_label.text.contains("NOT saved"),"write failure remains explicit during pending apply")
 d.size=d.screen;d.clock+=1;tick(p);d.clock+=150;tick(p)
 check(p.dirty and p.status_label.text.contains("NOT saved"),"window success cannot overwrite preference save failure")
 DirAccess.remove_absolute(path+".tmp")
 p._cycle("fullscreen")
 var stale:Dictionary=p.last_application.duplicate(true)
 p.queue_free();await process_frame
 check(poll(a,stale).is_empty(),"panel disposal cancels observation generation without callbacks")
 check(d.sets.size()>=3,"disposal test really had native-like requests")
