# Source trading presentation

Reference: locked StackCraft a11a89; original source/media and generated metadata
remain private. This adapter does not launch Unity or claim pixel equivalence.

`TradeZone` supplies its own MeshFilter, renderer and outline material. The importer
now resolves each actual TradeManager buyer/vendor reference, retaining separate
Title/Price/Tracker TMP components, local poses, source defaults and the buyer's
Icon renderer. It does not reuse CardSettings as trading metadata. Both locked
trade prefabs independently reference the same CardOutline ShaderGraph default
material; unsupported graph paths remain unsupported.

The view now binds the referenced one-surface FBX with the same handedness bridge
as source card meshes, its SimpleLit color (metallic 0, smoothness 0), renderer
shadow flags and same-mesh unscaled outline. No colors depend on active/locked
state: source inactive vendors retain `???`, empty Price and empty Tracker.
Activation/restoration updates Title and Price independently. Tracker completion
uses the source gold color; ordinary discovery text retains its source color.

The buyer binds its source built-in unit Quad at the referenced local pose/scale,
and replaces the material's texture with the active scene's currency ArtTexture.
It retains the exact shader reference for audit. Unity built-in shader 10750 is
not included in the source: native unlit alpha mix is explicitly *unverified*,
not an independently proven equivalent shader. Source texture pose/binding and
shader equivalence are separate claims. Likewise SimpleLit surface inputs are
mapped, but Godot and Unity lighting/BRDF output is not identical by assertion.

Each zone now exposes a physical picking collider from its source bounds and a
`trade_zone_index`, plus the source `GetInfo` descriptor. Buyer: Card Buyer / Sell
your cards here. Active vendor: Pack Vendor / You can buy [name] card pack here.
In the pinned source, an inactive vendor publishes an empty request on enter; the
collider can still be hit. A stationary pointer does not republish when activation,
payment or quest progress changes the text. A real exit/re-entry or a replacement
zone enters again and reads current state. Exit and disable release the request.
Board owns hover priority and cleanup via InfoPanel; the view disables its
collider when hidden. Without source provenance the native fallback keeps its
existing refresh behavior. Trade transaction geometry continues
to use the original pure TradeLayout, not rendered geometry.

The source TMP font is absent. Native fallback labels preserve separate fields,
local transforms, wrapping flags, colors, alignment and point-size-derived world
scale; missing font glyph widths/line spacing are not claimed equal. Public
missing-resource runs retain the existing clearly native fallback, not fake source
assets. The private source path binds the actual resources instead.

Focused tests: synthetic Python reference resolution/copy isolation/missing input;
Godot mesh/material/outline/label poses, inactive/active/completed transitions and
hover descriptors. Actual private import metadata validates both Main and Island
references. GPU draw, font parity and the unavailable built-in shader require
separate evidence; headless checks are not visual acceptance.

## Multi-coin drop and actual Godot mixer output

With the pinned private asset import, run:

```sh
GODOT_RENDERING_METHOD=gl_compatibility bash tools/test_godot.sh res://tests/godot/test_trade_mixer_board.gd
```

This starts the real Board with original audio and particle bindings. It picks
up a real two-coin chest through the Board input path and drops it on the
unlocked original vendor. It checks one zone puff and two withdrawal puffs,
then one register request after both balance and price update. All requests
occur in one engine frame: the original 50 ms per-AudioId cooldown suppresses
the two repeated Puff voices, not either corresponding particle. The register
is a different AudioId and plays independently.

The test disables background music only for this fixture and sends the two
original voices through separate capture buses before continuing to Master.
Each must contain real nonzero PCM. The rejected-item case must still travel
through normal drop feedback but neither trade input may produce PCM. The test
checks for nonempty capture buffers and no dropped capture frames. Public
checkout without private media skips the mixer-specific assertions; missing
clips in a present import fail. Headless Dummy output still runs Godot's mixer;
this check does not verify sound at speakers, native hardware, clip playback
against Unity, or rendered puff pixels.
