# Audio transport loop and per-frame cooldown clock

Evidence is the same Unity template repository, examined at snapshot `a11a89`.
That inspection hash is not an owner-selected version or proof that screenshot
runtime state matches the inspected scene. No Unity execution or listening was used.

## Music loop ownership

AudioManager.Awake sets AudioSource.loop=true before Play (lines 86–93).
The native previous finished-signal callback restarted a completed non-looping
clip on the main thread. That represents successive playback requests, not the
source transport loop, and can leave a gap while that thread is busy.

The native BGM binding now duplicates the resolved AudioStreamWAV, sets forward
looping over the whole decoded frame interval (zero to rounded length × sample
rate), and starts it once. No finished callback is installed. The original cached
stream and its stereo channels, format, data and sample rate remain unchanged;
a one-shot using the same resource still ends. This covers the template's WAV
BGM and rejects empty/unsupported streams explicitly, rather than inventing music.
Godot's imported compressed WAV and raw-buffer WAV decoder paths are tested
separately. Gain/interrupt waits do not replace the transport, and shutdown and
explicit media reconfigure still stop and clear it.

This removes the main-thread restart mechanism. It does not certify cross-engine
sample identity, compression quality, a seamless musical composition, hardware
mixer timing or perceived audio quality.

## Cooldown frame sampling

AudioManager.PlaySFX reads Time.unscaledTime before resolving the clip (lines
147–159). Unity's value is shared by calls in a frame. Reading wall time anew on
every request could admit a repeated event during one slow frame.

AudioFrameClock caches one sample per Engine.get_process_frames token. The production AudioFeedback connects SceneTree.process_frame to sample before
Node._process callbacks, including frames with no sounds. If an input callback
precedes that hook, its first audio request samples the token instead; the later
hook does not overwrite it. The monotonic provider is called only **once per
process-frame token**. Subsequent calls retain that timestamp even if the thread stalls past
the cooldown; the next token gets a fresh unscaled sample.
The production provider is independent of Engine.time_scale and gameplay pace.
Missing clips still consume cooldown; rejected repeats do not refresh it.
Configuration clears per-event admission history but does not reset this shared
frame sample. Providers are injectable for deterministic frame-boundary tests.

This is an explicit same-frame admission mapping, not a claim that Godot pre-process/early-input
sampling is Unity's exact beginning-of-frame instant, that engine frame phases
match, or that double-precision host timestamps reproduce Unity float rounding.
No source call site uses FixedUpdate; FixedUpdate's distinct fixed-unscaled-time
semantics are not added. SourceAudioClock separately owns scaled interrupt waits;
it is not replaced or conflated with this cooldown clock.

## Validation

`test_audio_transport` covers injected frame IDs/timestamps and actual engine
frame tokens, a real long same-frame stall, later-frame admission, timeScale=0,
missing-clip admission, mono/stereo 8/16-bit stream duplication, multiple natural
loop periods without a finished callback, shared one-shot completion, mixer mute
and restore, shutdown, and actual licensed WAV decode/binding when available.
Public CI skips only the private-resource section. Strict private import requires
its PASS marker. Existing audio, Options audio lifecycle/intent, source clock and
native-quit regressions remain separate checks. Dummy-backend tests do not imply
listening or spatial acceptance. No 3D call sites, listener behavior or attenuation
policy changed.
