extends SceneTree
const Board=preload("res://scripts/ui/board.gd")
const Session=preload("res://scripts/model/game_session.gd")
const Codec=preload("res://scripts/model/save_codec.gd")
const Admission=preload("res://scripts/ui/source_restore_admission.gd")
const Planner=preload("res://scripts/model/source_restore_layout.gd")
var checks=0
var failures=0
var results=[]
func check(v:bool,label:String):
 checks+=1
 if not v:failures+=1;printerr("FAIL: ",label)
func _init():call_deferred("run")
func run():
 var assets=preload("res://scripts/ui/visual_assets.gd").new()
 if assets.load_manifest()!=OK or not assets.board_local_rect("Main").has_area() or not assets.board_local_rect("Island").has_area():
  print("Source board expansion: SKIP (licensed FBX cache missing)");quit();return
 var board=Board.new();root.add_child(board);await process_frame;board.set_process(false)
 check(not board.catalog.data.is_empty(),"catalog");check(not board.visual_assets.manifest.is_empty(),"visual manifest")

 for scene in ["Main","Island"]:
  for boost in [4,36,100,104]:
   var s=Session.new();s.configure(board.catalog,51,scene);s.paused=true;board.session=s
   # Collision near base edge, plus an isolated extreme saved anchor.
   s.spawn_card(board.catalog.find_by_name("Wood"),Vector2(7,0),-1,{"refuse_attach":true})
   s.spawn_card(board.catalog.find_by_name("Stone"),Vector2(7.2,0.1),-1,{"refuse_attach":true})
   s.spawn_card(board.catalog.find_by_name("Flint"),Vector2(25,25),-1,{"refuse_attach":true})
   var tens=int(boost/10);var fours=int((boost-tens*10)/4)
   if boost==36:tens=2;fours=4
   for i in tens:s.spawn_card(board.catalog.find_by_name("Warehouse"),Vector2(-20-i*3,0),-1,{"refuse_attach":true})
   for i in fours:s.spawn_card(board.catalog.find_by_name("Yard"),Vector2(-20-(tens+i)*3,0),-1,{"refuse_attach":true})
   s.board_top_margin=1.5;s.board_bounds=board.visual_assets.board_local_rect(scene,minf(boost,100)/100.0)
   var before=s.campaign.capture();var desc=Admission.describe(board)
   check(desc.ok,scene+str(boost)+" source expansion admission")
   check(not Admission.describe(board,false).ok,"travel expansion opt-out remains whole-group fallback")
   if not desc.ok:results.append({"scene":scene,"boost":boost,"failure":desc});continue
   check(desc.config.bounds.is_equal_approx(Rect2(-6,-4,12,8)),"initial base bounds")
   var plan=Planner.plan(desc.rows,[],desc.config);check(plan.ok,"expanded phase planner")
   check(is_equal_approx(plan.states[0].position.x,6.0-board._card_footprint(1).x*0.5),"source ApplyTranslation clamps overlapping first stack to base edge")
   check(plan.states[1].position==Vector2(7.2,0.1),"source final saved anchor reset")
   check(s.campaign.capture()==before,"planning immutable")
   check(Planner.apply(s,plan).ok,"apply admitted targets")
   check(s.board_bounds==desc.config.expansion.final_bounds,"final board stays expanded")
   check(s.cards[5].position==Vector2(25,25),"extreme saved anchor not blanket clamped")
   results.append({"scene":scene,"boost":boost,"states":plan.states,"initial":str(desc.config.bounds),"final":str(s.board_bounds)})
 # A real Continue path: two-phase plan must survive the first ordinary refresh.
 var directory="user://expansion-cold"
 DirAccess.make_dir_recursive_absolute(directory)
 var path=directory.path_join("SaveSlot001.json")
 check(board.session.campaign.save_file(path).ok,"save controlled expansion fixture")
 board.slot_root=directory;board.selected_slot=1;board._continue_game()
 check(board.source_restore_report.get("ok",false),"actual cold Continue applies expansion plan")
 var positions=[]
 for stack in board.session.stacks.values():positions.append(stack.position)
 board._refresh()
 var refreshed=[]
 for stack in board.session.stacks.values():refreshed.append(stack.position)
 check(positions==refreshed,"no extra positive expansion overlap pass")
 var clean=board.catalog.data.duplicate(true)
 var manifest=board.visual_assets.manifest.duplicate(true)
 var expected_scene=board.session.scene_name
 for mode in ["missing_scene","nonzero_weight","missing_weight","scaled_prefab","missing_mesh","negative","selling","clock","combat","craft"]:
  var phase=board.session.phase;var elapsed=board.session.elapsed
  var first_stack=board.session.stacks.values()[0];var recipe=first_stack.recipe_guid
  match mode:
   "missing_scene": board.visual_assets.manifest.scenes[expected_scene].erase("boards")
   "missing_mesh": board.visual_assets.root_path="res://absent-private-mesh/"
   "nonzero_weight","missing_weight","scaled_prefab":
    for prefab in board.catalog.data.referenced_prefabs:
     if prefab.guid in ["520b1b5bfc70f3046b560ac3246705d7","2d5c9720d0a21304a8cb9b8bf644f267"]:
      for document in prefab.documents:
       if int(document.class_id)==137:
        if mode=="nonzero_weight":document.fields.m_BlendShapeWeights=[1.0]
        elif mode=="missing_weight":document.fields.erase("m_BlendShapeWeights")
       if int(document.class_id)==4 and mode=="scaled_prefab":document.fields.m_LocalScale.x=2.0
   "negative":
    for definition in board.catalog.data.cards:
     if definition.script_class=="LimitBoosterDefinition":definition.fields.boostAmount=-4
   "selling":board.session.phase="selling"
   "clock":board.session.elapsed=board.session.day_duration
   "combat":board.session.combat.membership[1]=99
   "craft":first_stack.recipe_guid="unverified-active-recipe"
  var before_guard=board.session.campaign.capture()
  var denied=Admission.describe(board)
  check(not denied.ok,mode+" rejects entire expanded entry")
  check(board.session.campaign.capture()==before_guard,mode+" rejection immutable")
  board.catalog.configure(clean.duplicate(true));board.visual_assets.manifest=manifest.duplicate(true);board.visual_assets.root_path="res://assets/imported/"
  board.session.phase=phase;board.session.elapsed=elapsed;board.session.combat.membership.clear();first_stack.recipe_guid=recipe

 board.queue_free();await process_frame;await process_frame
 print("Source board expansion: ",checks," checks, ",failures," failures");quit(0 if failures==0 else 1)
