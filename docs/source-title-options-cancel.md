# Title Home Options has no raw Cancel action

Locked source `a11a89b04cea8370476f2559b639bb9b4cbc08d8` has
TitleScreen.Start wiring the Home GameOptions TextButton to GameOptionsUI.Open.
Neither script handles raw Cancel. The Title scene has no gameplay PauseMenu.
GameOptionsUI.Close explicitly saves preferences and deactivates the panel;
ordinary option changes retain their existing immediate persistence behavior.

Only an actual admitted Title Home-to-Options opening suppresses fresh Escape
and gamepad East. The linked source Options stays visible and focused, with no
save attempt, dirty-state change, gameplay pause, or title navigation. Explicit
Close retains its existing save/retry safeguards. Native/fallback and unsupported
openings retain their previous Cancel behavior. Gameplay timing is unchanged.

The opening token requires locked TitleScreen/button/Options record linkage,
source-mounted Home button, the original source Options root and actual active
Title source adapter. It belongs to that title adapter, options view and catalog
data identity. Direct Options.open cannot mint it. Closure, title/game lifecycle,
transition and source/view replacement invalidate it. Reset, quit and recovery
modal handling keeps precedence. Preferences and Saves destinations are excluded;
this is not a generic Title navigation change.

Tests cover actual keyboard and gamepad routing, echo/releases, unchanged disk
and focus, failed adjustment writes without Cancel retry, explicit Close failure
and recovery, normal immediate writes, reset/transition, unsupported direct opens,
source replacement and Preferences exclusion. The prior Title fallback test also
opens a genuinely unadmitted Options instance and checks its old close/save path.
This is an event-ownership correction, not Unity framebuffer or full-migration
acceptance.
