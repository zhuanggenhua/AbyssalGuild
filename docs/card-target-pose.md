# Derived per-card settled target poses

Original `CardStack.SetTargetPosition` assigns each card
`TargetPosition + card.Settings.StackStep * index`. The current model historically
stores the root in every stacked `card.position`, while its view already offsets
individual cards. Reading those stored fields for distance/individual placement
therefore differs from the visible settled layout.

## API and save compatibility

Session now exposes:

- `card_target_position_3d(card_id) -> Vector3`: for valid stack membership, root
  plus source step times ordered member index. Scene CardManager's cardSettings
  reference takes precedence over the catalog's generic CardSettings lookup.
  All step components are retained. With no step data, a synthetic fixture uses
  zero offset rather than invented source geometry.
- `card_target_position(card_id) -> Vector2`: X/Z projection of the same target.
- `capture_card_targets(ids) -> Dictionary`: IDs to planar targets, captured before
  batch mutation changes indices. Missing IDs are omitted; individual accessors
  return zero for a missing ID. Callers needing existence validation must check IDs.

Detached cards fall back to their stored independent XZ position, at Y=0 in the
3D adapter. The source stack root Y is not represented in the current model.
These are settled targets, not Unity's animated transforms or the view's aesthetic
Y lift. They introduce no persistent state, save schema changes, load rewrites,
new RNG draws, or source save compatibility claims. Stored per-card and stack
positions remain untouched merely by reading poses. Old root-valued saves load
and re-save identically while deriving corrected member targets.

## Integrated consumers

- `Session.end_day`: nearest-food distance uses per-card 3D targets; feeding
  destination uses the character's planar target. Source evidence:
  `CardManager.FeedCharacters` compares individual `transform.position` values,
  then `CardInstance.Consume` moves food to the character.
- `world_rules.aggressive_intent`: nearest-player and attack/range tests use
  settled per-card 3D distances. Returned chase targets are planar member targets.
  Combat rectangles remain their supplied planar centers. Source evidence:
  `CardAI.FindClosestPlayerCard`, `TryJoinExistingCombat`, `TryHuntPlayer`, and
  `MoveTowards`. Model movement remains planar; transient Y/animation is not ported.
- `MobAI._detach`: capture individual target before membership changes, then return
  its new singleton to that position. Source `CardAI.DetachFromStack` constructs
  the singleton at its individual current transform and reflows the old stack.
- Both world and MobAI production paths pass the producer's settled member pose
  to the factory/placement adapter. Source `CardAI.SpawnProduce` uses its transform.
- Equipment individual detach and unequip paths preserve/use settled positions.
  This does not recreate the source's visual equipment slot transform.

`Equipment.detach(session,id,target_position=null)` accepts an optional PRE-CAPTURED
planar target. Existing default calls retain stored-position behavior. This is
intentional: combat batches must capture all members before the first removal,
then pass the captured value for each. Automatically deriving inside each detach
would shift later indices and collapse participant positions.

## Remaining integrations and deliberate root consumers

Combat batch capture/initial geometry, death loot, growth seed splitting, and
board per-card interaction queries are follow-up integration points. Rendering
and nearby-stack queries already add index offsets themselves: replace the entire
pose calculation if adopting the accessor, never add the index twice. Generic
combat detach remains unchanged until batch capture is wired safely.

Do NOT replace intentional stack-root positions: original pack drawing uses
`Stack.TargetPosition + up*0.1`; normal/exploration/research/growth result spawning
uses crafting stack target. Board collision footprints likewise operate on the
root and aggregate depth. The accessor does not alter any of those paths.

## Verification

Godot 4.6.3 `test_card_target_pose.gd`: 30/30 with private source data (28 synthetic
checks always run, two imported-source checks skip explicitly without data).
Covers scene settings precedence, all step components, no serialized mutations,
legacy root-valued save roundtrip, individual and captured batch detachment,
feeding order reversal, AI nearest/range behavior, producer placement, equipment
return, and actual source settings/save restore.

One old world-rule fixture moved only a card field and left its singleton stack
root elsewhere. It now updates both, matching the existing AI fixtures and the
model's authoritative stack target; production behavior was not weakened to
prefer stale card fields. World 76, AI 55, combat/equipment 60, save-codec 381 and
the full `tools/test_all.sh` runner pass with no script errors (including current
UI 139, slot UI 48 and trade UI 43). Dedicated pose tests ran separately until
added to the aggregate runner. No Unity runtime was launched.
