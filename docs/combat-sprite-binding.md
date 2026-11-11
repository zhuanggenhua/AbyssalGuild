# Combat sprite and hurt flash binding

This independently written adapter consumes the optional, ignored private visual manifest. Original scripts, prefab YAML, images, importer metadata and generated records are not redistributed. It neither calls Unity nor changes combat state, card positions, timers or gameplay RNG.

## Static source audit

- `Scripts/Card/CardInstance.cs`, `TakeDamage`: `_renderer.material` receives `_FlashAmount`; the entire card transform receives the hurt rotation. The flash delays 0.05 seconds, rises over 0.1 seconds and yoyo-loops twice. The joined sequence uses unscaled time. The existing `Card.shadergraph` adapter already reproduces its color-to-white/brightness math. This slice exposes the input, not another clock.
- `Scripts/Combat/CombatManager.cs`, `SpawnProjectile` / `SpawnHitUI`: serialized `arrowProjectile`, `magicProjectile` and `hitUIPrefab` component references select resources. HitUI is instantiated at a fixed X=90-degree world rotation, rather than billboarded toward the camera.
- `Scripts/Combat/UI/CombatProjectile.cs`, `Fire`: runtime world position/rotation replace the prefab pose; source scale remains. Direction is flattened to the horizontal plane. Local sprite +Y points toward the target. Motion is linear and unscaled; completion destroys the object. Both referenced prefabs serialize duration 0.5 seconds, overriding the script's 0.6 default.
- `Prefabs/UI/Projectile_Arrow.prefab` and `Projectile_Magic.prefab`: one root SpriteRenderer with the built-in sprite material, Simple draw mode, white tint, no flips and no cast shadows. These are not FBX models. Each referenced PNG is 64 by 64 pixels; its `.png.meta` declares centered single-image sprite import, bilinear filtering and 256 pixels per unit. Therefore its plane is 0.25 by 0.25 world units. Serialized renderer `m_Size` is not used in Simple mode.
- `Prefabs/UI/HitUI.prefab`: explicit `hitImage`, `effectivenessImage` and `damageLabel` component references determine roles. The root Image is 0.4 by 0.4 units with centered pivot. The effectiveness Image has upper-right anchors/pivot, anchored X offset 0.15, and size 0.15 by 0.15. Its local bounds are X=0.2..0.35 and Y=0.05..0.2. The damage rectangle stretches to the root; its nominal font size is 0.2. Both Images are Simple, non-aspect-preserving, with the default UI material.
- `Scripts/Combat/UI/HitUI.cs`, `Initialize`: miss/normal/critical select three separate sprites; miss damage is empty, other damage is the number alone. Critical does not append an exclamation mark. Advantage/disadvantage select their corresponding icon; no advantage disables that image. Source punch scale is local XY, lasts one unscaled second and destroys the object on completion. Motion/lifetime are the separate presentation controller's responsibility.

## Public API and independent metadata

`CardView.set_hurt_flash(amount)` clamps finite inputs to 0..1 and updates `flash_amount` on the per-card source material. Selection uses a separate emission input, so highlight/stat refresh cannot erase an ongoing flash. Nonfinite values are ignored. With generated geometry it flashes the fallback body color and restores the original color at zero; this is a semantic cue, not original textured-art fidelity. No root, collider or child transform is changed by this setter.

`VisualAssets.create_projectile(combat_type, scene_name)` returns an unparented Sprite3D or null. Supported source types are resolved from the scene's references. The result preserves source scale, tint, flip, pivot, pixels/unit and filter. It is initially in the XY plane; the caller supplies runtime position/orientation. Metadata `source_duration`, `source_world_size` and `source_prefab_guid` is descriptive only. In Godot's reflected board coordinates, orient local +Y along flattened target-minus-start and local +Z toward world +Y.

`VisualAssets.create_hit_popup(kind, damage_text, advantage, scene_name)` returns an unparented Node3D or null. It already has reflected X=-90-degree orientation and source root scale. Children `Hit`, optional `Effectiveness`, and `Damage` supply the static display. The caller supplies placement, punch and lifetime. No source-faithful fade is claimed; the source destroys this display after its punch. Rendering priorities retain image/text order without disabling world depth testing.

`tools/combat_visual_metadata.py` resolves component ownership, direct-child RectTransform anchors/stretch/pivots, exact sprite references and PNG importer dimensions. Import provenance includes hashes of the PNG `.meta` files. Missing ownership, malformed dimensions, unsupported nesting, atlases or unsupported automatic pivots do not get a guessed layout. Only centered/custom-pivot single-image sprites and nearest/bilinear filters are currently supported. The runtime rejects unknown projectile materials, non-Simple image modes and incomplete resources. A needed missing icon makes the complete popup unavailable, allowing the caller's existing semantic text fallback; an unused icon does not block a no-advantage popup.

## Limits

The native Sprite3D adapter uses alpha-blended unlit planes, not Unity's renderer implementation or its tight sprite triangulation. HitUI's numeric text uses a native Label3D font, normalized to the imported nominal height and source color/rectangle center. It does not load or imitate the original TMP font atlas, typography or shader. Rendering order, transparency, glyph shapes, depth behavior and colors have not been accepted visually. No screenshot, GPU/pixel comparison, or manual interaction acceptance was possible in the current headless environment. Motion/easing approximations are documented separately by the presentation controller.

## Validation

- `python3 -m unittest discover -s tests -p 'test_*.py' -v`: 85 tests passed, including six new synthetic metadata tests. Fixtures use independent values and contain no original prefab export.
- `tests/godot/test_combat_sprite_binding.gd`: 104 checks in a genuinely source-free project and an explicit private-resource skip. With private PNGs but no FBX cache: 256 checks. With actual cached Card FBX resources: 260 checks. Tests inspect texture identity, material inputs, generated triangle bounds, source rectangles/pivots, visibility, all nine hit/advantage combinations in both scenes, state independence and missing/unsupported-resource fallbacks.
- Actual cached regressions: existing card mesh tests passed 139 bindings; card overlay tests passed 241 checks.
- Private visual regeneration: 173 assets, zero missing. Original source lock: all 1,327 files matched the locked revision.

Use the existing timeout/error-guarded Godot runner. Focused validation here is not a claim that a concurrent full-project snapshot or rendered UI was accepted.
