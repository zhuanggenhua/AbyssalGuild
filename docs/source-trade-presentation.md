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
Inactive vendor: no request. Board owns hover priority and cleanup via InfoPanel;
the view disables its collider when hidden. Trade transaction geometry continues
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
