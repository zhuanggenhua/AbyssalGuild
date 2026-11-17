# Idle combat slot return

Locked source: CardLoop a11a89b04cea8370476f2559b639bb9b4cbc08d8.
CardController.HandleCombatDrop inside branch calls CombatRect.RepositionCard,
removes the temporary held stack, and leaves Card.Stack null. RepositionCard uses
SetTargetAnimated(targetPosition), with its default forceGround=false. ArrangeRow
previously uses SetTargetInstant(..., forceGround:true), then ArrangeCards caches
the actual observed XYZ.

This bounded native path captures a real idle grounded slot before lifting. On
inside release it retains the actual sampled held pose, not PointerUp coordinates,
and animates using the imported .1-second OutQuad settings. The same CardMotion
owner advances on real delta even while the board is paused. Combat membership and
stacklessness remain unchanged; no gameplay state machine or second card is added.

Admission requires existing locked-source native hold guards and an observed
pose matching its idle slot. It excludes active combat actions, missing provenance,
transformed boards, displaced/unsupported slot captures, and non-native holds.
New press, changed layout/membership/card/view/parent, equipment, cycle or combat
presentation owners revoke the return. Actual native ArrangeCards write also
revokes it even if the numerical slot is unchanged. No-op refresh does not restart.

Validation: test_combat_slot_return_board uses imported data, native Board view,
press/move/frame/release and original audio teardown. It covers held-pose start,
OutQuad progress, pause, completion, refresh, new drag, action and transform
revocation. This is not full visual acceptance or active/ranged release parity;
an action beginning before the return ends retains the conservative existing
adapter. General overlapping/resize behavior and two-engine screenshots remain
unaccepted.
