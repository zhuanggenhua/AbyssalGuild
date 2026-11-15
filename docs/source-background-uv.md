# Built-in background plane UV bridge

This adapter is restricted to the existing recognized built-in plane10209 plus
Unlit/Texture10752 contract used by the locked template. Other meshes/shaders
remain unsupported, not assigned this UV mapping. No new import/version dependency
is added. Original resource dumps and mesh/shader data remain private.

The matching official Unity editor resource reader resolves object10209 to a
Plane Mesh. Its local position→UV mapping is u=(5-x)/10,v=(5-z)/10. The coordinate
bridge reflects world Z and converts transforms as S*T*S, so the corresponding
source local position for native(x,y,z) is(x,y,-z). The source UV therefore equals
(1-Ug,Vg), where the native PlaneMesh has Ug=(x+5)/10,Vg=(z+5)/10.

The matching built-in shader10752 resolves to Unlit/Texture. Its vertex stage
uses TEXCOORD0 and the provider's TRANSFORM_TEX macro (uv*scale+offset); its
fragment stage samples that static Texture2D directly. Unity's static texture
UV origin is bottom-left. Godot's copied PNG/ImageTexture rows retain the PNG's
top-first order: neither asset loading nor mip-chain recovery flips base pixels.
This is not the graphics-API-specific render-target orientation path.

Converting the final sampled coordinate gives:

```
u = -Sx * Ug + Sx + Ox
v = -Sy * Vg + 1 - Oy
```

Godot StandardMaterial3D applies UV scale before offset and permits negative
scale. The adapter changes only those two material properties. It does not flip
mesh geometry, indices, image bytes, mip levels, shadow flags or sampler settings.
Do not use positive Sy or1-(Sy*Vg+Oy) before including source reflection without
checking the complete coordinate chain. Non-integer tiling and offsets in tests
prevent wrapping from hiding an extra flip or wrong offset.

Synthetic asymmetric pixels are a CPU coordinate observer, not a Unity image
oracle. Tests include the real plane transform, unrelated mesh/shader rejection,
negative source scale, fractional ST/offset, unchanged base bytes and retained
mip chain. Actual Main/Island/Main/Title tests verify the resulting (-20,-20)
scale,(20,1) offset and existing scene lifecycle. No vendor vertex data is added.

This closes a source-derived UV orientation omission, not whole-frame parity.
Unity-specific mip texels/compression, forced anisotropy, lighting/color pipeline,
render-target orientation and native source screenshot comparison remain separate.
The editor payload was resolved with its own type information; the standalone
player payload could not be decoded by the installed helper because its embedded
version differs. No player-mesh identity claim is inferred from that failure.
