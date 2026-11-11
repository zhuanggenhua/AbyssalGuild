# Options panel and Escape pause adapter

`OptionsPanel` is an original generated interface over `UserOptions`. It is
available from the title and the Escape pause menu. Global preferences use
`user://options.json`, independently of campaign slots, day duration and Friendly
Mode. No PlayerPrefs or Unity save import is implied.

## Persistence and failure handling

- Startup configures verified modes supplied by the application, loads primary
  then backup, and sends a detached plan to an injected adapter. Loading does not
  create or rewrite a preferences file.
- Each slider/button change applies through that adapter and saves through the
  existing validated temporary/backup writer. An unsupported application mapping
  is reported separately from successful preference persistence.
- A failed write keeps the changed preference in the running session, visibly
  reports that it is not saved, and keeps Save & close open until a retry succeeds.
  The disk checkpoint remains intact. Window close also refuses to discard dirty
  preferences when their save fails.
- Close flushes preferences. If both existing files were invalid and the user made
  no change, Close leaves their evidence untouched instead of saving defaults
  over them. Recovery/default fallback is shown in the panel; startup invalid
  fallback is also noted on the title.
- Reset first asks for confirmation, then resets only application options and
  applies/saves them. Campaign saves, discovery, day length and Friendly Mode are
  not deleted or reset.

## Supported native application and honest limits

The default adapter changes only this application's window/players/engine cap.
It never changes the host system volume or a hardware screen mode.

- SFX uses user dB on the feedback players. BGM uses the source per-clip linear gain
  multiplied once by the user gain. The source fallback remains 0.3, and imported
  overrides remain respected. Repeated application does not compound gains.
- Borderless maps to Godot's nonexclusive fullscreen; Windowed maps to its normal
  window mode. On/Off VSync is requested and read back. A rejected driver request
  is reported and the FPS application stays unchanged.
- With verified On VSync, Engine.max_fps is unlimited and the display pacing wins.
  With Off, the selected source cap is used (Unlimited becomes zero in Godot).
- Half-refresh VSync has no verified portable mapping. The source cycle value can
  be retained, but is labelled unsupported and does not change current VSync/FPS
  application. Adaptive or mailbox is not silently substituted.
- Godot exposes no portable full hardware resolution list equivalent to the source.
  The native adapter supplies no invented modes, disables resolution cycling and
  explicitly reports that it did not change screen resolution. Injected adapters
  may supply a verified list; tests use only synthetic mode lists.
- Unity URP shadow presets have no verified Godot mapping. That control is visibly
  disabled, the saved value is retained, and source-configured lighting stays as it
  was. Map sizes/cascades are not falsely advertised as applied.
- Headless application is a preview/no-op: no display, Engine FPS or audio setting
  is changed. UI tests use an injected fake adapter and assert this boundary.

Actual native window/VSync/volume behavior still needs desktop/rendered/manual
acceptance. Headless tests validate plans, UI state and data flow, not sound or
hardware timing. This is not the original GameOptionsUI's art/layout.

## Escape and pause

Escape opens a full-screen input-blocking pause overlay only during normal play.
The overlay is an external UI pause lock, not a change to `session.paused` or the
selected speed. Opening options from it retains the lock. Closing options returns
to the pause menu; Continue/another Escape resumes the original pace, including a
pre-existing manual pause. Menu opening cancels an active card drag safely.

Feeding, selling, ready and game-over are ending-cycle phases: Escape cannot toggle
the pause menu or open options during them. Their gameplay locks are not bypassed.
Title options do not start or pause a game. Save & return to title remains subject
to slot-save failure handling. Source animation/unscaled combat phase timing is
separate integration work and is not established by this panel's headless tests.

## Verification

`bash tools/test_godot.sh res://tests/godot/test_options_ui.gd`

The suite uses a unique test-owned options/slot directory, fake apply adapter,
synthetic verified modes and a detached, nonplaying audio-gain object. It covers
volume math, per-change persistence, unsupported controls, pending-write failure,
Close/Reset, backup/default evidence preservation, Escape/cycle locks, prior pace
preservation, no campaign reset, no master-gain/Engine mutation, and single source
music-gain composition. Existing `test_user_options.gd` and
`test_audio_feedback.gd` remain separate regression targets.
