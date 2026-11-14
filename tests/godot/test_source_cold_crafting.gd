extends SceneTree
## Public source-shaped fixtures. The reference loop below transcribes the locked
## task cursor only, not Unity execution or any rendering/physics behavior.
const Cold = preload("res://scripts/ui/source_cold_crafting.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
const Order = preload("res://scripts/model/crafting_order.gd")
const Stack = preload("res://scripts/model/stack.gd")
var checks := 0
var failures := 0
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures+=1;printerr("FAIL: ",label)
func recipe(id: String) -> Dictionary:
	return {"guid":id,"file_id":"11400000","source_path":"Resources/Recipes/"+id+".asset","source_sha256":"a".repeat(64),"unity_fields":{"m_Enabled":1,"m_Script":{"guid":Cold.RECIPE_SCRIPT,"fileID":"11500000"}},"script_class":"RecipeDefinition","fields":{"id":id,"craftingDuration":10.0,"isContinuous":0,"requiredIngredients":[],"resultingCard":{"fileID":"0"}}}
func make():
	var c=Catalog.new()
	c.configure({"provenance":{"source_commit":Cold.SOURCE_COMMIT},"cards":[{"guid":"input","script_class":"CardDefinition","fields":{"id":"input","category":0,"uses":1}}],"recipes":[recipe("first"),recipe("second"),recipe("third")]})
	var s=Session.new();s.configure(c,71)
	for id in ["first","second","third"]:
		var card: int=s.spawn_card("input")
		var stack=s.stacks[s.cards[card].stack_id]
		stack.recipe_guid=id;stack.progress=2.3456789012345
		s.discovered_recipes[id]=true
	# Intentional source-shaped ordered-state fixture, not natural game assembly.
	for i in range(2,-1,-1): s.crafting.activate(s.stacks.values()[i])
	return s
func normalized(s):
	var d=Codec.capture(s);d.session.erase("crafting");return d
func reject(mutator: Callable,label: String):
	var s=make();mutator.call(s)
	var before=Codec.capture(s);var notes: Array=[]
	s.changed.connect(func():notes.append("changed"))
	s.event_occurred.connect(func(k,_p):notes.append(k))
	var result=Cold.apply(s)
	check(not result.ok and Codec.capture(s)==before and notes.is_empty(),label+" atomically retains existing path")
func tests():
	var s=make();var old=s.crafting.save_state();var before=normalized(s)
	var notes: Array=[];s.changed.connect(func():notes.append("changed"));s.event_occurred.connect(func(k,_p):notes.append(k))
	var result=Cold.apply(s)
	check(result.ok and result.changed and s.crafting.save_state().activation_order==s.stacks.keys(),"ordinary class, not example GUID whitelist")
	check(normalized(s)==before and notes.is_empty(),"only activation order changes, exact timer/position/pause/gear/IDs/quests/RNG unchanged")
	check(Cold.apply(s).ok and not Cold.apply(s).changed,"already canonical order stable")
	var raw=make();var loaded=make();var loaded_result=Codec.restore(loaded,Codec.capture(raw))
	check(loaded_result.ok and loaded.crafting.save_state()==raw.crafting.save_state(),"generic Codec clones retain old history")
	var legacy=Codec.capture(raw);legacy.session.erase("crafting")
	check(Codec.restore(loaded,legacy).ok and loaded.crafting.save_state().activation_order==loaded.stacks.keys(),"legacy native fields absent remain supported")
	reject(func(x):x.catalog.data.provenance.source_commit="other","source mismatch")
	reject(func(x):x.scene_name="Other","scene mismatch")
	reject(func(x):x.phase="feeding","day phase")
	reject(func(x):x.phase="selling","selling phase remains separate")
	reject(func(x):x.cycle._state.stage="character_focus","in-flight cycle")
	reject(func(x):x.elapsed=x.day_duration,"day deadline")
	reject(func(x):x.elapsed=x.day_duration-0.00000001,"source float32 day deadline")
	reject(func(x):x.travel_pending=true,"pending travel")
	reject(func(x):x.combat.tasks[1]={"attackers":[],"defenders":[],"player_is_attacker":true,"timer":0.0,"progress":{},"combatants":{}},"combat task")
	reject(func(x):x.combat.membership[1]=1,"combat membership")
	reject(func(x):x.drag.begin(x.cards.keys()[0]),"held card")
	reject(func(x):x.stacks.values()[1].paused=true,"task paused")
	reject(func(x):x.stacks.values()[1].progress=10.0,"already complete")
	reject(func(x):x.stacks.values()[1].progress=9.99999999,"float32 complete but native double incomplete")
	reject(func(x):x.catalog.definitions.first.fields.craftingDuration=0,"zero duration")
	reject(func(x):x.catalog.definitions.first.fields.craftingDuration=1.0e40,"source float32 infinite duration")
	reject(func(x):x.discovered_recipes.erase("first"),"discovery callback")
	reject(func(x):x.catalog.definitions.first.script_class="TravelRecipe","mixed travel class")
	reject(func(x):x.catalog.definitions.first.script_class="ExplorationRecipe","mixed special class")
	reject(func(x):x.catalog.definitions.first.unity_fields.m_Script.guid="custom","script identity")
	reject(func(x):x.catalog.definitions.first.erase("source_sha256"),"missing source metadata")
	reject(func(x):x.catalog.definitions.first.source_path="custom/file.asset","custom source location")
	reject(func(x):
		for st in x.stacks.values():st.cancel_craft(),"no active work")
	# Exact representable near-threshold progress remains admitted, not quantized.
	var edge=make();edge.stacks.values()[0].progress=9.999998
	var exact: float=edge.stacks.values()[0].progress
	check(Cold.apply(edge).ok and edge.stacks.values()[0].progress==exact,"safe float32 incomplete boundary keeps original double value")
	check(old.activation_order!=s.crafting.save_state().activation_order,"counterexample original order was actually different")
class Model:
	extends RefCounted
	var stacks: Dictionary={}
	var catalog=Catalog.new()
	var scene_name="Main"
	var crafting=Order.new()
	var completed: Array=[]
	var mode: String
	func _init(kind: String):
		mode=kind;catalog.configure({"recipes":[{"guid":"job","fields":{"craftingDuration":1}}]});crafting.configure(self)
		for id in [1,2,3]:stacks[id]=Stack.new(id)
		start(1);start(2)
		if mode=="complete_cancel":stacks[1].progress=1.0
	func start(id: int):stacks[id].recipe_guid="job";stacks[id].progress=0;crafting.activate(stacks[id])
	func _complete_recipe(st):
		completed.append(st.id);st.cancel_craft()
		if st.id==2:
			if mode in ["cancel","replace","complete_cancel"]:stacks[1].cancel_craft()
			if mode=="replace":start(1)
			if mode=="append":start(3)
# A separate literal source-list/canceled-flag cursor, without native generations.
func source_frames(mode: String) -> Array:
	var tasks: Array=[{"id":1,"progress":0.0,"canceled":false},{"id":2,"progress":0.0,"canceled":false}]
	if mode=="complete_cancel":tasks[0].progress=1.0
	var events: Array=[];var frames: Array=[]
	for frame in 2:
		for i in range(tasks.size()-1,-1,-1):
			var task: Dictionary=tasks[i]
			if not task.canceled and task.progress<1.0:task.progress+=1.0
			if task.canceled or task.progress>=1.0:
				if task.progress>=1.0:
					events.append(task.id)
					if task.id==2:
						if mode in ["cancel","replace","complete_cancel"]:tasks[0].canceled=true
						if mode=="replace":tasks.append({"id":1,"progress":0.0,"canceled":false})
						if mode=="append":tasks.append({"id":3,"progress":0.0,"canceled":false})
				tasks.remove_at(i)
		frames.append(events.duplicate())
	return frames
func _init():
	tests()
	for mode in ["plain","cancel","replace","append"]:
		var reference: Array=source_frames(mode);var m=Model.new(mode)
		for frame in 2:
			m.crafting.advance(1.0)
			check(m.completed==reference[frame],"source old cursor "+mode+" frame "+str(frame))
	var unsupported=Model.new("complete_cancel");unsupported.crafting.advance(1.0)
	check(source_frames("complete_cancel")[0]==[2,1] and unsupported.completed==[2],"known canceled+complete source mismatch remains outside admission")
	print("Source cold crafting: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
