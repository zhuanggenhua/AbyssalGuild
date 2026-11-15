extends RefCounted
## Fully swapped ordinary source destination only. Never the loading boundary.
static func admit_commit(board, receipt: Dictionary, owner, candidate, provenance: Dictionary) -> Dictionary:
 if receipt.is_empty() or not provenance.get("source_arrival_no_save",false):return {}
 if not board.running or board.quit_dispatched or board.session!=owner or receipt.get("owner")!=owner or receipt.get("candidate")!=candidate or receipt.get("generation")!=board.scene_transition.generation:return {}
 if board.scene_transition.phase!="commit" or not owner.travel_pending or owner.crafting._active_serial!=0:return {}
 var stack=receipt.get("stack")
 if stack==null or owner.stacks.get(stack.id)!=stack or stack.craft_generation!=receipt.get("craft_generation") or stack.recipe_guid!=receipt.get("recipe"):return {}
 var members:Array=receipt.get("members",[])
 if stack.card_ids.size()!=members.size():return {}
 for i in members.size():
  if owner.cards.get(stack.card_ids[i])!=members[i]:return {}
 if not preload("res://scripts/ui/source_departure_checkpoint.gd").admitted(owner,stack.id,receipt.recipe,receipt.accepted) or candidate.scene_name!=receipt.accepted.get("scene"):return {}
 # No simultaneous other travel, unresolved completion or changed cycle.
 for row in owner.stacks.values():
  if row==stack or row.recipe_guid.is_empty():continue
  var entry=owner.catalog.get_definition(row.recipe_guid)
  if entry.get("script_class")!="RecipeDefinition":return {}
  var f=PackedFloat32Array([row.progress,float(entry.fields.get("craftingDuration",0))])
  if not is_finite(f[0]) or not is_finite(f[1]) or f[0]<0 or f[1]<=0 or f[0]>=f[1]:return {}
 return {"owner":candidate,"scene":candidate.scene_name,"generation":board.scene_transition.generation}
static func allowed(board, receipt: Dictionary) -> bool:
 var s=board.session
 if receipt.is_empty() or receipt.get("owner")!=s or receipt.get("scene")!=s.scene_name or receipt.get("generation")!=board.scene_transition.generation:return false
 if board.scene_transition.phase!="in" or not board.running or board.quit_dispatched or s.travel_pending:return false
 if s.catalog.data.get("provenance",{}).get("source_commit","")!=preload("res://scripts/ui/source_restore_admission.gd").SOURCE_COMMIT:return false
 if s.phase!="playing" or s.cycle.stage!="idle" or s.crafting._active_serial!=0 or s.drag.active() or not s.combat.tasks.is_empty() or not s.combat.membership.is_empty() or not s.ai.agents.is_empty():return false
 if board.pause_overlay.visible or board.options_panel.visible or board._navigation_modal_active() or board.vendor_unlock.is_active() or not board.camera_motion.focus.is_empty() or board.panning or board.dragging>=0:return false
 for row in s.stacks.values():
  if s.catalog.get_definition(row.recipe_guid).get("script_class")=="TravelRecipe":return false
 return true
