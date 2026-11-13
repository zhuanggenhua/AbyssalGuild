# Source-wide audio slot lifecycle

Locked source: CardLoop a11a89b04cea8370476f2559b639bb9b4cbc08d8,
Unity 6000.5.4f1; native Godot 4.6.3. This maps ownership and parameters, not
acoustic or listening equivalence. No original WAV is included in tests.

AudioManager creates pooled AudioSources and uses PlayOneShot. Reusing a source
changes its pitch, spatialBlend and optional world position for already-playing
voices as well as the new one. Null position selects nonspatial mode without
clearing the stored position. The former single callback did not own gain/stop/
shutdown/reconfigure, and its next null request bypassed a retained 3D renderer.

Each native logical slot now has a persistent owner. Every admitted 2D/3D request
passes through it. Same-mode reuse applies source-wide pitch/position; gain, stop,
shutdown and media reconfiguration visit all owned voices regardless of class.
Finished child voices release their streams. Default nonspatial playback retains
overlap rather than replacing the active clip. Scene persistence of BGM waits
and source clock remains independent of media-node lifecycle.

Godot cannot change a player's dimensional class. At a 2D/3D boundary the owner
rebuilds all active voices in the required class, retaining stream, transport
position, gain and pitch, and explicitly stops/clears old nodes. This is not a
claim of sample-continuous playback across the mixer-buffer boundary. Original
stereo streams remain stereo; no hidden mono conversion occurs.

Production has no verified spatial acoustic policy installed, so positional
requests still fail explicitly. A callable test policy only permits real-node
ownership checks; it is not a source attenuation/pan/Doppler implementation.
Default Godot lowpass, distance and panning settings must not be asserted equal
to Unity merely because names appear similar. All current locked project callers
use the ordinary non-positional arguments.

An independent source_listener helper maps a supplied original world pose by
Z reflection and makes an AudioListener3D current. Title's source listener is
(0,1,-10), identity; Main/Island follow their actual camera transform. Native
Title camera framing is different, and native camera projection offsets do not
move its global transform while Unity shake changes the listener-bearing
Transform. Thus this helper is tested but not falsely wired to the wrong camera.
Full animated-listener and acoustic rendering remain open.

Public test_audio_slot_owner uses synthetic stereo silence and real native 2D/3D
players: 26 checks cover overlap, entire-slot position/mode/pitch/gain, repeated
null reuse, stop/shutdown/reconfigure, BGM wait persistence and independent
listener pose validation. Existing default and optional audio suites also run.
Dummy backend tests prove node state, not audibility, source voice virtualization
limits, stereo spatial mixing, Doppler or cross-engine sample equivalence.
