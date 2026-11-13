# Optional AudioManager branches and persistent clock

Reference: locked StackCraft source a11a89b04cea8370476f2559b639bb9b4cbc08d8.
This is logical playback-state verification, not listening/spatial acceptance.

## Source trace

AudioManager.Awake creates SFX AudioSources dynamically, sets spatialBlend=0,
creates a looping BGM source with source gain .3, and calls DontDestroyOnLoad.
It has no SceneManager.sceneLoaded handler; loading Title/Main/Island does not
recreate the surviving singleton or cancel its coroutines. Duplicate singleton
objects destroy themselves before initializing a second pool.

PlaySFX first records unscaled cooldown admission, resolves the clip, chooses the
next logical pool source, applies pitch and changes its spatial blend. Null position
sets blend0 without clearing the transform; supplied position sets transform+blend1.
The source-wide parameters also affect earlier overlapping one-shots on that source.

When interruptBGM is requested, only a current mixer value >=0 starts PauseBGM.
PauseBGM captures that value, sets -80 dB, waits clip.length **scaled** seconds and
restores the captured value. It does not pause the music transport or use a
pitch-adjusted wait. A volume edit during the wait can be overwritten by completion;
resetting gain to zero can permit another independent coroutine. No new duck-count
policy is substituted. Same-frame ordering among concurrent Unity coroutine resumes
is not claimed to have been engine-verified; native resumes eligible waits in their
admission order. Staggered concurrent completions have explicit tests.

## Why title does not always mean real-time audio waits

The only source assignments to Time.timeScale are TimeManager.UpdateTimeScale:
external lock count >0 gives0, otherwise CurrentPace (0/1/2). TimeManager is scene-local.
GameDirector.TravelSequence pauses the old manager, fades out unscaled, loads the
scene, then releases a lock only if a new TimeManager exists. Main/Island contain
TimeManager; Title does not. Loading scene time restores day/currentTime, not pace.

Thus cold Title starts with default global scale1. Returning from gameplay leaves
scale0 in Title even though AudioManager and its pending wait survive. New gameplay
creates a Normal manager and releases the wait again. This surprising source
behavior is preserved, not silently fixed. The native persistent source_audio_clock
retains global scale when no gameplay TimeManager is represented.

## Native integration

board._process samples the clock once at frame entry. Neither its departing-world
branch nor its regular frame branch samples again. Sampling precedes model events
and scene commits, so an oversized fade-out frame cannot charge the pending wait
with time after its scene commit. The audio clock receives source pace and external
pause (scene departure, pause/options and vendor reveal); non-playing day phases
represent the source's Paused pace. During ordinary arrival fade, gameplay resumes.

Native campaign/save pace restoration is owned by the existing session lifecycle.
This patch does not change that gameplay/save behavior or claim all saved native
pace cases match Unity (source restores only day/elapsed into a new Normal manager).
The clock tests use the source-compatible Normal arrival path explicitly.

AudioFeedback.configure is called once by the production board's startup, not on
travel/title. If tooling explicitly refreshes media, pending waits and live mixer
gain survive; media replacement itself is a native tool operation, not a Unity
scene lifecycle. shutdown/actual tree destruction cancels waits and closes admission.

## Mixer versus stored preference

user_bgm_db remains the saved/app preference. requests.mixer_bgm_db is the live mixer
value. Coroutine restore changes only the latter, not saved preferences. Source
GetSavedBGMVolumeSlider actually reads the live mixer despite its name;
live_bgm_slider_value now reaches Options through OptionsAdapter.live_volume_slider.
Source .3 clip gain is multiplied by live mixer gain once. Source audio volume remains
app-local; no host master mixer is changed.

Options plans carry explicit action intent. Initial application and confirmed Reset
write both audio channels. A SFX callback writes only SFX; BGM writes only BGM,
even if its desired value equals the saved value. Graphics operations and ordinary
whole-plan refresh do not write either mixer channel and cannot accidentally end a
BGM mute. Persistence records desired preferences, not transient coroutine gain.

GameOptionsUI.InitVolumeSliders executes only in Start and after Reset, not every
Open (there is no OnEnable refresh). Listeners are already connected when source
Slider.value is assigned, so a changed first-live value really invokes its channel
callback and saves it. In particular, first activation during a mute can persist
-80 dB; that surprising source side effect is retained. Same-instance reopen keeps
its existing slider display and does not sample the mixer again.

Native OptionsPanel is reused, so successful gameplay scene binding and a genuine
running-game return to Title reset only its scene-local Start state. New prefabs
start inactive; sampling waits for first activation. Title preferences/save-page
navigation, repeated same-Title presentation and failed load do not reset it.
Tests cover the real scene-binding callbacks with synthetic scene notification,
not a substitute claim that travel recipe mechanics were exercised here.

## Spatial branch remains incomplete

play_source_event accepts world_position and now uses a persistent source-wide
slot owner; see [slot lifecycle](audio-slot-lifecycle.md). No Unity-equivalent spatial renderer is installed; positional requests
explicitly return false rather than secretly becoming 2D. The existing single-argument play_event API remains a wrapper, preserving native
callers and subclass overrides. Current source callers all use the default
nonspatial arguments. Do not mark the whole PlaySFX method done.

Full-tree source evidence confirms Unity6000.5.4f1 and AudioSettings master1,
rolloff scale1, doppler1, speaker mode2, DSP1024, real voices32/virtual512 and no
spatializer plugin. Per-source dynamically created defaults and Unity/Godot spatial
mixing/attenuation still require a verified renderer, not guessed Godot defaults.
Ownership changes do not mark this acoustic branch complete.

## Tests

- test_audio_optional: 22 synthetic checks (gain thresholds, concurrency, source slot
  parameters, unavailable renderer isolation, default path, source gain).
- test_audio_clock_board: 16 checks using the actual board._process branching with
  synthetic lifecycle hosts: Normal/Fast/pause/day-end, Title/travel persistence,
  one advancement per frame, reconfigure and preference/live-mixer separation.
- test_options_audio_intent: 17 integration checks, including live first Start,
  original callback persistence, channel isolation, explicit same-value BGM edit,
  same-instance reopen and confirmed Reset.
- test_options_audio_lifecycle: 9 checks for Title subpages/failed load and
  Main-to-Island-to-Title lifecycle ownership.
- Existing options_application: 12 outcome checks; user_options: 90; options_ui: 42;
  source_options_pause source-layout regression also passed.
- Existing audio_feedback: 124 checks including private WAV decode/start.
- Existing native_quit: 56 checks, including actual engine exit.
- Existing scene_transition_board: 24 checks.

All executed headless with Dummy audio. No audible quality, localization or exact
Unity coroutine frame-phase/engine scheduling equivalence is claimed.
