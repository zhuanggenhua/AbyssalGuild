# AI placement and nearest-player order

This slice follows the locked StackCraft baseline by static inspection only. Unity was not launched and no source files or extracted licensed content are included.

## Runtime contract

- `CardAI.MoveTowards` resolves board overlaps immediately after an accepted move; a rejected approach does not resolve or fall through to patrol.
- `CardAI.MoveRandomly` resolves once after the patrol, including exhausted or zero candidate attempts. Each agent's resolution finishes before another agent moves.
- The model receives an explicit placement callback. Board entry binds it to the existing layout resolver, not the pickup-guarded frame fallback. The adapter survives AI reconfiguration and is rebound on scene entry/travel.
- The existing pickup-only frame guard remains. The existing native extra lock on the held stack also remains an intentional interaction policy: the source physics solver checks `CardStack.IsLocked`, not `IsBeingDragged`. Explicit pack locks and combat rectangles still use the existing resolver.
- `CardAI.FindClosestPlayerCard` takes stable equal-distance ties from `CardManager.AllCards`: registered stacks, their current member order, then combat attackers and defenders. AI and feeding now share an audited accessor; unrelated consumers are unchanged. Equipped/unregistered players and combat participants remain ineligible hunt targets.
- Native checkpoints preserve stack registration/member order, so this target-selection order continues across reloads. This does not claim Unity/Godot RNG or interpolation equivalence.

## Checks

`test_ai_placement_order.gd` is synthetic and needs no private import. It tests callback frequency/sequencing, accepted/rejected player and combat approaches, exhausted patrols, configure retention, tie changes after re-registration and splitting, checkpoint continuation, and exclusions.

`test_ai_placement_board.gd` requires imported licensed data. It drives a due real Cow patrol into a neutral resource while an unrelated real pointer pickup remains active. Production and spawn placement are disabled for the repro. It also tests failed-patrol resolution against an explicit lock, the retained pickup frame guard, and actual Main-to-Island travel rebinding. This is headless board/geometry integration, not visual, pointer-device, audio, or full-game acceptance.

## AI detachment and newly exposed recipes

Static inspection of `CardAI.DetachFromStack` also showed that a previously idle surviving stack must be checked for a newly valid recipe. The native equipment-detach helper already cancels an existing craft; AI now remembers that prior state and checks for recipes only when the old stack was idle. Recipe activation goes through the existing `_check_recipe` and authoritative activation-order controller.

`test_ai_detach_craft.gd` covers accepted/rejected patrols, recipe activation/completion and the defensive previously-crafting cancellation branch with synthetic definitions. `test_ai_detach_craft_source.gd` uses legal imported rules: place Cow onto Apple, then carry Apple and Cow onto Berry. The extra Cow blocks strict Fruit Salad; its due movement detaches it and starts Fruit Salad even if all patrol candidates are rejected. Normal elapsed crafting ticks produce one salad. No recipe, craft timer, task order or quest state is injected in this real-catalog probe.
