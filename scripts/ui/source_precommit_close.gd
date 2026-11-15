extends RefCounted
## Private constrained prototype: source ordinary pre-blackout close only.
static func capture(board, receipt: Dictionary) -> Dictionary:
 var s=board.session
 if receipt.is_empty() or receipt.get("owner")!=s or receipt.get("generation")!=board.scene_transition.generation:return {}
 if board.scene_transition.phase!="out" or board.scene_transition.alpha>=1 or board.quit_dispatched or not board._source_fade_progress_allowed():return {}
 if s.crafting._active_serial!=0 or not s.ai.agents.is_empty() or board.vendor_unlock.is_active() or not board.camera_motion.focus.is_empty() or board.panning or board.dragging>=0:return {}
 if board.puff_factory.is_valid() or s.cards.size()>16 or s.stacks.size()>8 or not s.equipment.owners.is_empty() or not s.equipment.equipped.is_empty():return {}
 var commit: Callable=board.scene_transition._commit
 var bound=commit.get_bound_arguments()
 if commit.get_object()!=board or commit.get_method()!="_commit_travel" or bound.size()!=3 or bound[0]!=s or bound[1]!=receipt.get("candidate") or not bound[2].get("source_arrival_no_save",false):return {}
 var stack=receipt.get("stack")
 if stack==null or s.stacks.get(stack.id)!=stack or stack.craft_generation!=receipt.get("craft_generation") or stack.recipe_guid!=receipt.get("recipe"):return {}
 var members: Array=receipt.get("members",[])
 if stack.card_ids.size()!=members.size():return {}
 for i in members.size():
  if s.cards.get(stack.card_ids[i])!=members[i]:return {}
 var others=0
 for row in s.stacks.values():
  if row==stack or row.recipe_guid.is_empty():continue
  others+=1
  var entry=s.catalog.get_definition(row.recipe_guid)
  if entry.get("script_class")!="RecipeDefinition" or entry.fields.get("isContinuous",true) or not s.matches_recipe(row,entry.fields):return {}
  var f=PackedFloat32Array([row.progress,float(entry.fields.get("craftingDuration",0))])
  if not is_finite(f[0]) or not is_finite(f[1]) or f[0]<0 or f[1]<=0 or f[0]>=f[1]:return {}
 if others>1:return {}
 return preload("res://scripts/ui/source_departure_checkpoint.gd").capture(s,stack.id,receipt.recipe,receipt.accepted)
