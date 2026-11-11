# User options model (UI/application not yet integrated)

`user_options.gd` stores native, global application preferences independently of campaign saves. It contains no AudioServer, DisplayServer, Engine, host-volume, or window calls. Configure/load/change/reset/save never applies settings. An explicitly injected adapter is the only application route.

## Static source audit

Reference: CardLoop `a11a89b04cea8370476f2559b639bb9b4cbc08d8`, `Assets/StackCraft/Scripts/UI/GameOptionsUI.cs`, `UI/PauseMenu.cs`, `Core/AudioManager.cs`, and `Core/GraphicsManager.cs`. Unity was not launched and no source/assets were copied.

Source PlayerPrefs keys and native fields:

| Source key | Native field | Default and supported controls |
|---|---|---|
| VolumeSFX | sfx_db | 0 dB; normalized 0–1 slider |
| VolumeBGM | bgm_db | 0 dB; normalized 0–1 slider |
| ScreenWidth, ScreenHeight | resolution | Actual hardware mode nearest 1920×1080 by squared pixel distance |
| FullscreenMode | fullscreen | borderless; cycles borderless/windowed |
| VSyncMode | vsync | 1 (On); cycles 0 Off / 1 On / 2 Half |
| FrameRateCap | fps_cap | −1 (Unlimited); cycle −1, 30, 60, 120, 144, 240 |
| ShadowPreset | shadow_preset | 3 (High); cycle 0 Off / 1 Low / 2 Medium / 3 High / 4 Ultra |

The audio sliders convert values ≤0.0001 to −80 dB, otherwise `20*log10(value)`. Slider inverse is clamped `10^(dB/20)`: −80 dB returns 0.0001, not exactly zero. Mixer user gain is separate from the music player's per-clip/source gain (`_defaultMusicVolume` has a 0.3 code initializer and can be overridden by imported prefab data). Do not replace that source gain with the user's mixer preference or apply it twice. The source has no master-volume slider, mute checkbox, or persisted pitch option.

GraphicsManager deduplicates hardware resolutions ignoring refresh rate, sorts width then height, and picks the mode nearest 1920×1080 on first run; equal distances keep the first sorted mode. There is no hard-coded available-resolution menu. VSync overrides the cap in source performance semantics. Source URP shadow presets use Off distance 0; Low 512/10/1, Medium 1024/20/2, High 2048/30/3, Ultra 4096/40/4 (map resolution / distance / cascades). These are **Unity-specific renderer settings**, not a verified Godot mapping.

GameOptionsUI applies and saves each change; Close also flushes preferences. Reset prompts then clears PlayerPrefs and reinitializes graphics/audio. PauseMenu opens the same options panel, toggles external pause, and disallows cancel toggles during day-ending flow. This model does not implement those UI/pause behaviors.

## Helper API

- `configure(hardware_modes = [])`: supply verified `[width, height]` pairs obtained by an application adapter. Deduplicates/sorts, then initializes defaults. Invalid input leaves existing data unchanged. An empty list leaves resolution unresolved (`[]`), never inventing a list or changing the host. Call before load.
- `values`, `snapshot()`, `restore(snapshot)`: current data, detached native envelope and validated transactional replacement. Unknown/missing fields, wrong types, nonfinite values and out-of-domain settings are rejected. A bad direct restore preserves existing preferences.
- `set_volume("sfx" or "bgm", linear)`, `volume_slider(channel)`: validated finite 0–1 values and source conversion.
- `cycle("resolution" / "fullscreen" / "vsync" / "fps_cap" / "shadow_preset")`: source ordering; empty hardware resolutions return a blocker. These methods change data only. The caller must save and explicitly apply afterward.
- `reset_defaults()`: resets only this options object. It does not delete slots or unrelated data and does not write or apply automatically. UI confirmation is still required before wiring a user-facing reset.
- `application_plan()`: detached options plus `unsupported` capability labels and `fps_overridden_by_vsync`. Half-VSync is explicitly unsupported by the default mapping; Unity shadow presets always require a renderer-specific adapter. Resolution is flagged when unresolved or not in the caller-verified hardware list.
- `apply_with(callable)`: validates the snapshot and sends that detached plan to the injected adapter. Adapter returns `{ok: bool, ...}` and owns capability checks, supported mappings and truthful error reporting. The model does not imply that unsupported settings applied successfully.
- `save_file(path = "user://options.json")`: validates, writes same-directory `.tmp`, flushes/closes, rereads, preserves a validated primary in `.bak`, then renames over the primary. A corrupt primary never displaces a healthy backup. One writer per path; no portable directory fsync/power-loss guarantee. Failures return `ok: false` without deleting the primary.
- `load_file(path)`: tries primary then backup without rewriting either. A healthy backup returns `recovered: true` and prior diagnostics. No files means defaults with `ok: true, used_defaults: true`. Existing but invalid primary/backup means defaults with `ok: false, used_defaults: true, errors: [...]`. The caller must surface that fallback and must not claim the corrupt files were repaired. No automatic host application occurs.

## Native differences and boundaries

Format is `abyssal-guild-user-options`, version 1, JSON, bounded to 16 KiB; this is not a PlayerPrefs importer. Source keys are mapped to descriptive native fields rather than Unity numeric fullscreen enums. Native resolution safety bounds are positive integers up to 16384 per axis; these bounds are not presented as a Unity source restriction. The source can read unusual saved FPS/VSync values, but this native format accepts the supported UI domain only. Fullscreen mode and all enumerated options are strictly checked.

A saved resolution absent from the verified hardware list is retained as preference data but marked unsupported for application. Unlike source's potentially mismatched display/label fallback, the model does not blindly apply it. An adapter should ask/select a verified mode deliberately. Godot does not provide a portable equivalent of Unity's entire hardware mode list, half-refresh VSync, or URP shadow presets; do not substitute an invented list, adaptive/mailbox VSync, or unverified shadow mapping and label it source parity. Unsupported choices need a visible explanation or disabled UI until implemented.

Day duration and Friendly Mode belong to each campaign's gameplay preferences and are not global user options. Neither campaign state nor transient pause, temporary music ducking, active combat or scene progress is persisted here. This task does not modify board controls or AudioFeedback; integration should preserve existing per-source gains and playback behavior.

## Verification

`tests/godot/test_user_options.gd` runs synthetic mode lists and a fake application adapter, using a unique temporary `user://test-user-options-…` path. It checks defaults, conversions/floor, bounds/type rejection, source cycle sequences, detached adapter data, JSON restoration, atomic replacement/backup recovery, invalid fallback and no automatic application. It never changes actual display, refresh rate, global engine cap or host/app audio volume. Tests remove only their own temporary files. Runtime renderer/audio mapping and UI interaction remain unverified until separately integrated and tested.
