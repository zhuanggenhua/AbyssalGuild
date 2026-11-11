# Nonblocking feeding and encounter UI

The board consumes CycleController's authoritative realtime state. Natural day expiry shows an enabled Feed action only at await_feed. Starting Feed disables repeat activation while focus/lift/travel/chew/settle/character waits run. Encounter stages keep the day action disabled; Start Day appears only at ready. Start Day still immediately checkpoints after the model advances/reset pace. Return-to-title preserves the live game if saving fails. Quit during an ending cycle retains the existing warning and does not overwrite the last checkpoint.

`cycle_focus_requested` starts the real-time camera helper with full source Vector3 position (Y preserved, Z reflected). `cycle_sound` plays the requested source sound. Stage notifications defer label refresh rather than mutating the cycle reentrantly. No animation-complete callback advances the model. The cycle owns all nutrition, healing, death, encounter spawn and wait timing.

CyclePresentation reads presentation_state (source endpoints, duration, elapsed) after normal/combat view positioning. Food uses explicit OutQuad interpolation from model elapsed; there is no independent food clock. The pose sampler returns a current rendered source-coordinate pose for non-food cards, with derived model fallback if a view is absent. Active food uses its stage snapshot. The model independently owns selected-food pose sampling to avoid visual feedback. The layout callback only resolves stack positions. Equipment updates after food/combat view offsets.

Continue rebuilds an active food pose without replaying consumption or sounds. focus_state resumes only the remaining focus time from the newly imported camera pose; it does not restart the model's original wait. Camera path continuity across loading is approximate because camera transforms are not saved. This is native active-cycle recovery support rather than a claim that source saves arbitrary coroutine state.

## Carried input across day boundaries

A valid pointer-down grants one exact card permission to finish its existing gesture. The grant survives the phase boundary, then is consumed on release. Only that existing card may complete drop/trade/equip/pack opening in a locked phase. A new locked-phase press receives no grant. GUI cancellation, menus, session replacement and title clear it. The model open_pack carried_press argument is passed only after this board check; ordinary calls retain their default phase guard. No broad phase unlock is introduced. Existing combat actor drag restrictions remain in force when the press begins.

Selling is interactive: source DayCycleManager removes its input lock, so camera and cards work there. Escape remains disabled by the separate ending-cycle flag. Feeding, encounter, ready and game-over reject new camera/card gestures. Existing card movement/release does not depend on obtaining a new grant.

## Verification and limits

The pure presentation suite checks snapshot immutability, reflected poses, interpolation and absent-card safety. The board suite uses original imported data, isolated save/options paths and silent audio recording; it covers asynchronous Feed, delayed effects, active-phase save/restore, camera continuation, encounter locks, checkpoint and carried-input rejection/acceptance. Older final-state smoke tests now drain the actual controller through tick calls, never a synchronous replacement implementation.

Visual easing is an explicit approximation, and target-vs-current pose/floating-point differences remain. No Unity runtime, manual pointer acceptance, GPU visual parity or published private assets are claimed.
