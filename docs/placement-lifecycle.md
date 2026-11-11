# Growth and equipment placement lifecycle

Static reference: locked StackCraft source, without running Unity.

`GrowthRecipe.Execute` splits the original seed, translates its new stack, then
calls `CardManager.ResolveOverlaps` before creating the grown output. Waiting for
the output's normal post-spawn placement is too late: its attachment query would
see pre-resolution neighbour positions. `special_recipes.gd` now invokes the
existing live placement adapter immediately after a successful seed split. No
extra pass occurs when SplitAt would refuse the seed at index zero.

`CardManager.ReturnCardToBoard` registers each unequipped card and immediately
resolves overlaps. `equipment_system.gd` now invokes the same adapter from unequip,
covering individual unequip, replacement, and sequential death drops. This is
not deferred to the next view refresh. The shared stack-registration helper does
not resolve: combat return and AI also use it but own their placement timing. A
combat remove/finish regression verifies survivors keep their slot until the
combat presenter clamps them, without an early push from a stale combat rectangle. Callers without a placement adapter retain
their engine-independent behavior.

`tests/godot/test_placement_lifecycle.gd` reproduces both omissions: 18 assertions
failed before the corrections. The corrected run passes 61 checks, including all
six imported growth recipes, synthetic growth, and imported/synthetic equipment.
The crowded growth fixture proves a neighbour has moved before output attachment
is queried, and checks the exact resolve/select/resolve sequence. Equipment tests
verify synchronous resolution and separation from its wearer. Private input
checks explicitly skip when the source export is absent.

These are lifecycle and settled-position checks, not rendered, pointer, GPU or
Unity physics-equivalence acceptance. Equipment panel animated origins and the
already documented cross-engine placement approximations remain separate.
