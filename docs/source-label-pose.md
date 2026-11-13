# Authored card-label pose, no extra source-path lift

Locked CardLoop a11a89b04cea8370476f2559b639bb9b4cbc08d8:
`Assets/StackCraft/Prefabs/Cards/Card_Resource.prefab`, `Card_Character.prefab`, and `Card_Consumable.prefab` explicitly set label RectTransform m_LocalPosition.y=0.001 (title and applicable price/health/nutrition), with root y=0. Title x/z=(0,0.4); price=(-0.25,-0.355); health=(0.254,-0.345); nutrition=(0.258,-0.363). Label quaternion x/w=0.7071068. The importer already retains the authored root+RectTransform chain. Native handedness reflection preserves the y coordinate.

The source geometry is imported separately with its source transform. No supplied source field or runtime CardInstance assignment applies a further +0.01 to these label positions. The previous source path changed authored y=0.001 into y=0.011 under a coplanarity comment, rather than transferring source pose. This change removes that additional source-only caption offset and source stat lift. It does not alter source transforms, mesh geometry, depth testing, font sizing, materials, or numeric native fit*0.8 behavior. Generated fallback boxes keep their explicitly native lift.

`test_card_overlays.gd` adds full-transform equality for source caption and stat labels using a synthetic imported mesh, verifies source stat ignores a caller lift, checks depth testing stays enabled, and retains native fallback-lift assertion. Existing private branches check full transforms when actual FBX caches exist. Initial isolated tool-run test passed 170 checks; it had no FBX cache, so actual cached mesh paths were not claimed tested. Authored offset removal is not a claim of visual/framebuffer equivalence.

The aggregate regression found two older `test_card_mesh_binding.gd` assertions
that still required +0.01 on synthetic and cached source titles. Both now compare
the authored reflected position directly. Native bounded QA visibly rendered the
Starter and Villager titles and Villager health without the invented lift; see
`gui-smoke.md` for exact scope and remaining framing/rendering limits.
