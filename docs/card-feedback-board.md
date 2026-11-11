# Live board card feedback

`board.gd` now connects the independently tested card-feedback helpers to actual
pointer, model, and presentation lifecycles. Source semantics and renderer limits
remain documented in [card-interaction-feedback.md](card-interaction-feedback.md).
This is a functional native Godot layout, not a Unity visual reproduction.

## Routing and priority

- Mouse motion/button positions are captured without changing selection. After
  each card/equipment view sync, the existing physics picker resolves the current
  visible card or equipment-panel owner. Stationary-pointer information refreshes
  as health, recipe progress, class, or equipment changes.
- The independent hover panel occupies the lower-left portion of the central
  board, outside both collapsible sidebars, the persistent day action, and the
  ordinary notice. It adapts to the logical viewport. Native labels keep a
  clipped two-line heading and a scrollable complete body. Its whole rectangle
  blocks click-through; scrolling does not zoom the camera. While the pointer is
  over that panel, its still-valid source is retained rather than picked through.
- An equipment-panel collider routes `panel_owner` to the source `Equipments`
  name list. It never substitutes that owner as a card hit. Visible expanded
  equipped cards and live combatants themselves retain the source-empty
  stackless-card hover. Hidden or destroyed objects cannot revive information.
- Hover is suppressed during vendor reveals and every end-cycle phase. Existing
  cycle controls, vendor notices, save failures, and ordinary notices are never
  written by the feedback adapter. An unrelated GUI control clears hover.

## Drag targets and crafting

- Only a live captured drag with current action permission produces target
  outlines. Candidates come from the model's pure `can_move_to_stack` predicate
  across current stacks, without a proximity radius. The source's own-stack and
  active-craft exclusions are then applied. Outlines attach to the source
  BottomCard, which is the last array member.
- The target overlay remains separate from selected-card emission and hurt flash.
  Release, death, focus loss, GUI blocking, menus, and action locks clear the full
  target snapshot. Clearing presentation does not revoke the existing held-stack
  grant or change its eventual release behavior.
- Each registered craft gets one generated world bar at its stack target plus
  source offset, with Z reflected once. A partial-tail pickup retains the paused
  original task and its existing bar even while ingredients are temporarily held
  elsewhere. Only the model's cancellation/completion removes it. Manual pause,
  cycle pause, and vendor pause retain frozen bars while the board is available.
- Pause/Options and native confirmation windows clear lower-priority feedback.
  Closing them rebuilds current task bars at the same model ratio. They do not
  restart, resume, validate, or choose a recipe.

## Ownership boundaries

Title, scene change, and session rebind clear both hover identities, outlines,
pointer history, and task nodes before presenting a new owner. Session instance
and scene identity are checked independently of card IDs, which can be reused.
Title cleanup also runs after menu-hide callbacks, preventing those callbacks
from repopulating departure task nodes. View replacement/death invalidates the
cached hover source; hover-panel retention also verifies view instance and card
definition. Window exit/focus loss requires a fresh pointer event before hover
or target feedback resumes.

The adapter does not mutate model state, consume RNG, save game data, or own a
clock. Existing simulation/external-pause behavior is unchanged in this slice.
World bars use the helper's documented native 0.08 Y clearance and generated
geometry; the target outline and fallback font remain explicit approximations.

## Verification

```sh
bash tools/test_godot.sh res://tests/godot/test_card_feedback_board.gd
```

The dedicated source-backed suite covers real card ray picking and native GUI
wheel/click routing, live information updates, class rebuilds, clipping and
scroll retention, panel/card ownership distinctions, pure model-qualified drag
targets, selection/hurt independence, paused partial-tail recipes, menu/modal/
cycle/vendor priority, repeated release, death, title cleanup, same-ID session
replacement, and actual Main-to-Island travel. It uses deterministic hit injection
for isolated routing edge cases in addition to the real physics and GUI probes.

These checks inspect Godot's headless input, control layout, nodes, and state.
They do not establish GPU appearance, occlusion, final typography, or manual
mouse/gamepad acceptance. Both the aggregate source-data runner and isolated private-resource runner
include this suite.

The final three-file integration was projected onto published baseline `845c9c6`
with licensed inputs linked read-only, separately from concurrent model work.
Godot 4.6.3 passed 69 new board checks. Focused regressions passed: navigation UI
56 (plus 16 without source data), navigation input 20, vendor unlock 47, held-stack
board 32, cycle board 29, cycle action visibility 76, Options 42, archive UI 24,
slot UI 50, UI smoke 139, equipment board 19, combat feedback UI 23, card-feedback
helpers 130, and imported-source descriptors 665. The smoke suite explicitly used
its generated-geometry fallback rather than claiming its imported-FBX branch.
This is focused headless verification, not a rerun of the full import or aggregate
validation pipeline.

The integrated suite now has 71 checks. Physical window resize is checked against
Godot's logical visible rectangle under the real project's `canvas_items`
stretch, and a separate content-scale change proves a truly narrower HUD. This
avoids comparing physical window pixels to logical canvas bounds.
