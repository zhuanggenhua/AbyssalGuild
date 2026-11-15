# Source background mip-chain presence

A bounded correction to `source_world.gd`, not a new background look or a Unity
mip-texel/color-space equivalence claim.

The locked Grass/Water importers enable mipmaps; both are512×512, source Box mode,
sRGB textures with zero mip bias. Source quality levels specify mipmap limit0
and no limit groups. The migrated PNG/imported alpha-from-input path can return
only the base image even though the material requests mip sampling. A sampler
flag cannot manufacture missing levels.

After the existing built-in plane/Unlit-Texture/repeat/bilinear admission, the
background adapter checks the actual image chain. When the source requests mips
and a supported uncompressed RGB8/RGBA8 image lacks them, it duplicates the image,
generates Godot-native mips and binds a separate ImageTexture. Existing chains
retain their exact texture identity; source-disabled mips retain their original
texture and linear filter. Absent textures remain absent; empty/unavailable/unsupported images or generation
errors retain the original real texture unchanged, with missing-chain parity still
unresolved. They do not hide a previously visible plane or fabricate pixels.
The generic asset cache, shared input texture, base pixel bytes, alpha, unshaded
opaque behavior, UV transforms, repeat and filter settings are unchanged. This
path does not affect cards, fonts, particles or UI textures. Alpha-transformed
images already carrying rebuilt chains remain untouched.

Tests cover an asymmetric synthetic RGBA image, real Grass/Water512→1 chains,
base bytes, original cache immutability, already-mipped identity, disabled source
flag and Main/Island/Main/Title lifecycle. They establish missing-chain recovery,
not source-engine mip selection or rendered equivalence.

Remaining separate contracts: Unity import compression, sRGB mip construction
and exact per-level texels, primitive UV orientation, and source PC ForceEnable
anisotropy. No global sampler/aniso change is included. Native mip generation is
performed only when constructing an admitted background with a missing chain,
not each frame. A future validated prebuilt private chain is preferable for exact
Unity texels and would already be preserved by this adapter.
