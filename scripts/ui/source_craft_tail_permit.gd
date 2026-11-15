extends RefCounted
## A deliberately narrow source frame tail, not general concurrent crafting.
const StackModel=preload("res://scripts/model/stack.gd")
const Quest=preload("res://scripts/model/quest_tracker.gd")
const Source=preload("res://scripts/ui/source_restore_admission.gd")

static func _connections(signal_value: Signal, expected: Array) -> bool:
	var connections: Array = signal_value.get_connections()
	if connections.size()!=expected.size():return false
	for row in connections:
		if row.callable not in expected or int(row.flags)!=0:return false
	return true

static func execute(board, task:Dictionary, members:Array, step:float, serial:int, receipt:Dictionary)->bool:
	var session=board.session
	for pair in [[session.ai,"mob_ai"],[session.cycle,"cycle_controller"],[session.quest_tracker,"quest_tracker"],[session.collection,"collection"]]:
		if pair[0].get_script().resource_path!="res://scripts/model/"+pair[1]+".gd":return false
	if board.feedback.get_script().resource_path!="res://scripts/ui/audio_feedback.gd" or board.feedback.spatial_policy.is_valid() or board.visual_assets.get_script().resource_path!="res://scripts/ui/visual_assets.gd":return false
	if board.get_script().resource_path!="res://scripts/ui/board.gd" or session.get_script().resource_path!="res://scripts/model/game_session.gd":return false
	if receipt.get("owner")!=session.get_instance_id() or receipt.get("generation")!=board.scene_transition.generation or receipt.get("serial")!=serial or serial<=0 or session.crafting._active_serial!=serial:return false
	if not session.travel_pending or board.scene_transition.phase!="out" or board.scene_transition.elapsed!=0.0 or not board.running or board.quit_dispatched:return false
	var commit:Callable=board.scene_transition._commit
	var bound:Array=commit.get_bound_arguments()
	if commit.get_object()!=board or commit.get_method()!="_commit_travel" or bound.size()!=3 or bound[0]!=session:return false
	if session.catalog.data.get("provenance",{}).get("source_commit","")!=Source.SOURCE_COMMIT or session.scene_name not in ["Main","Island"]:return false
	if session.phase!="playing" or session.cycle.stage!="idle" or session.drag.active() or not session.combat.tasks.is_empty() or not session.combat.membership.is_empty() or not session.ai.agents.is_empty():return false
	if board.vendor_unlock.is_active() or not board.camera_motion.focus.is_empty() or board.panning or board.dragging>=0 or board.pause_overlay.visible or board.options_panel.visible or board._navigation_modal_active() or board.puff_factory.is_valid():return false
	if session.cards.size()>16 or session.stacks.size()>8:return false
	if not is_finite(step) or step<0 or not session.crafting._current(task) or task.stack.card_ids!=members:return false
	var stack=task.stack
	var recipe:Dictionary=session.catalog.get_definition(task.recipe)
	if recipe.get("script_class")!="RecipeDefinition" or bool(recipe.fields.get("isContinuous",false)):return false
	var duration:float=float(recipe.fields.get("craftingDuration",0))
	if not is_finite(duration) or duration<=0:return false
	var progressed:float=stack.progress+(step if not stack.paused and stack.progress<duration else 0.0)
	if progressed < duration:
		# The original UpdateProgress occurs before the source completion check.
		# This one-frame branch cannot dispatch recipe/quest/effect callbacks.
		if progressed <= stack.progress or not _source_still_incomplete(stack.progress, step, duration): return false
		stack.progress = progressed
		return true
	var output:String=session.catalog.ref_guid(recipe.fields.get("resultingCard",{}))
	if session.catalog.get_definition(output).get("script_class") != "CardDefinition" or int(session.catalog.fields(output).get("category", -1)) != 4 or not session.collection.is_card_discovered(output): return false
	if session._selecting_spawn or bool(session.catalog.fields(output).get("isAggressive", false)): return false
	for rule in recipe.fields.get("requiredIngredients",[]):
		if int(rule.get("consumptionMode",0))!=1 and int(session.catalog.fields(session.catalog.ref_guid(rule.card)).get("category",-1))!=4:return false
	if session.spawn_target_selector!=Callable(board,"_select_spawn_target") or session.spawn_layout_resolver!=Callable(board,"_resolve_layout"):return false
	if not _connections(session.changed,[]):return false
	if not _connections(session.event_occurred,[Callable(session,"_track_quest_event"),Callable(session,"_track_cycle_event"),Callable(session.ai,"_on_event"),Callable(board,"_on_session_event")]):return false
	if not _connections(session.collection.changed,[Callable(board,"_collection_changed")]):return false
	if not _connections(session.quest_tracker.quest_activated,[Callable(board.quest_journal,"_created")]):return false
	if not _connections(session.quest_tracker.quest_completed,[Callable(board.quest_journal,"_completed"),Callable(board.vendor_unlock,"_on_quest_completed")]):return false
	if not _connections(board.quest_journal.changed,[Callable(board,"_on_quest_journal_changed")]):return false
	var count:int=0
	for current in session.stacks.values():
		if session.catalog.get_definition(current.recipe_guid).get("script_class")=="TravelRecipe":count+=1
	if count!=1:return false
	if not _plain_unattached(session,stack,recipe.fields,output):return false
	# No callbacks, RNG, cloning, or yielding occurred during admission.
	# The consumed receipt cannot authorize another frame or owner.
	if not session.crafting._current(task) or task.stack.card_ids!=members or board.scene_transition.generation!=receipt.generation:return false
	stack.progress=progressed
	session._complete_recipe(stack)
	session.crafting._prune()
	return true


## Sufficient proof only: eligible receivers are rejected even when far away.
## We reuse the actual stacking matrix and recipe matcher, not geometry guesses.
static func _plain_unattached(session,stack,fields:Dictionary,output:String)->bool:
	if bool(fields.get("allowExcessIngredients",false)) or not session.matches_recipe(stack,fields):return false
	if not session.equipment.owners.is_empty() or not session.equipment.equipped.is_empty() or session.ai._definition_has_ai(output):return false
	var destructive:String=""
	var seen:Dictionary={}
	for rule in fields.get("requiredIngredients",[]):
		var guid:String=session.catalog.ref_guid(rule.card)
		var mode:int=int(rule.get("consumptionMode",0))
		if guid.is_empty() or seen.has(guid) or int(rule.get("count",0))<=0 or mode not in [0,1,2]:return false
		seen[guid]=true
		if mode!=1:
			# Exactly one single-use material removal; all other rules retain.
			if not destructive.is_empty() or int(rule.count)!=1 or session.catalog.get_definition(guid).get("script_class")!="CardDefinition":return false
			destructive=guid
	if destructive.is_empty():return false
	var removed:int=-1
	var survivors=StackModel.new(stack.id)
	for id in stack.card_ids:
		var card=session.cards[id]
		if card.base_definition_guid==destructive:
			if removed>=0 or card.definition_guid!=destructive or card.uses_left!=1:return false
			removed=id
		else:survivors.card_ids.append(id)
	if removed<0:return false
	# The production factory ignores the processing stack. No other receiver
	# can pass can_move_to_stack's mandatory can_stack test, at any distance.
	for target in session.stacks.values():
		if target.id==stack.id or target.card_ids.is_empty():continue
		if session.can_stack(output,session.cards[target.card_ids.back()].definition_guid):return false
	# Existing _check_recipe draws RNG iff it finds matches. Reject any match,
	# even an unsupported recipe, so neither repeat nor discovery can occur.
	if not survivors.card_ids.is_empty():
		for recipe in session.catalog.data.get("recipes",[]):
			if session.matches_recipe(survivors,recipe.fields):return false
	# Only stats_changed, card_created and crafted can reach quests here.
	# Reject all state-based objectives, and any matching obtain/craft target.
	for instance in session.quest_tracker.active_quests:
		if int(instance.status)!=Quest.QuestStatus.ACTIVE or not session.quest_tracker.definitions.has(instance.id):return false
		var quest:Dictionary=session.quest_tracker.definitions[instance.id]
		var type:int=int(quest.type)
		if type<0 or type>Quest.QuestType.CAPACITY:return false
		if type in [Quest.QuestType.HAVE,Quest.QuestType.FOOD,Quest.QuestType.COINS,Quest.QuestType.CAPACITY]:return false
		if type in [Quest.QuestType.OBTAIN,Quest.QuestType.CRAFT] and session.catalog.ref_guid(quest.targetCard)==output:return false
	return true

## Unity task fields and Time.deltaTime are single precision. Do not grant a
## timer-only update when source rounding would already take its completion path.
static func _source_still_incomplete(progress: float, step: float, duration: float) -> bool:
	var source: PackedFloat32Array = PackedFloat32Array([progress, step, duration])
	if not is_finite(source[0]) or not is_finite(source[1]) or not is_finite(source[2]): return false
	if source[0] >= source[2]: return false
	var advanced: PackedFloat32Array = PackedFloat32Array([source[0] + source[1]])
	return is_finite(advanced[0]) and advanced[0] < source[2]
