extends SceneTree
const Layout = preload("res://scripts/model/board_layout.gd")
var checks := 0
var failures := 0
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
func _init() -> void:
	var board := Rect2(-6, -4, 12, 8)
	var size := Layout.card_size(Vector3(1, 0.1, 1.5))
	check(size.is_equal_approx(Vector2(1.1, 1.6)), "Collider size plus margin")
	var stack := Layout.stack_state(1, Vector2.ZERO, size, 4)
	check(is_equal_approx(Layout.full_depth(stack), 2.14), "Stack depth uses abs(step.z)")
	check(Layout.stack_bounds(stack).get_center().is_equal_approx(Vector2(0, -0.27)), "Bounds center follows trailing negative Z")
	check(Layout.card_position(stack, 3).is_equal_approx(Vector3(0, 0.006, -0.54)), "Per-card target includes Y step")
	check(Layout.enforce_placement(Vector2(99, 99), stack, board).is_equal_approx(Vector2(5.45, 1.7)), "Right and header bounds")
	check(Layout.enforce_placement(Vector2(-99, -99), stack, board).is_equal_approx(Vector2(-5.45, -2.66)), "Left and full trailing depth bounds")
	check(Layout.clamp_to_bounds(Vector2(0, 99), stack, board).is_equal_approx(Vector2(0, 3.2)), "ClampToBounds excludes header rule")
	check(Layout.is_point_valid(Vector2(0, -3), stack, board), "Source IsPointValid checks top card only")
	check(not Layout.is_point_valid(Vector2(0, 2), stack, board), "Point validity includes header")
	check(Layout.is_point_valid(Vector2(6, 2.5), {}, board), "Point-only inclusive boundaries")
	check(Layout.enforce_placement(Vector2(99, 99), {}, board) == Vector2(99, 99), "Null stack passthrough")
	check(Layout.clamp_rect(Vector2(99, 99), Vector2(2, 2), board) == Vector2(5, 1.5), "Combat rectangle clamp")
	check(Layout.pack_draw_position(Vector3(2, 0, -1)) == Vector3(2, 0.1, -1), "Pack draw has no XZ offset")
	check(Layout.separation(Rect2(-1, -1, 2, 2), Rect2(-1, -1, 2, 2)) == Vector2(0, 2), "Coincident centers choose +Z, ties choose Z")
	check(Layout.separation(Rect2(0, 0, 1, 1), Rect2(1, 0, 1, 1)) == Vector2.ZERO, "Touching is not overlap")
	check(Layout.separation(Rect2(0, 0, 1, 2), Rect2(0.5, 0, 1, 2)) == Vector2(-0.5, 0), "Smaller penetration chooses X")
	var a := Layout.stack_state(1, Vector2.ZERO, Vector2.ONE, 1)
	var b := Layout.stack_state(2, Vector2.ZERO, Vector2.ONE, 1)
	var solved := Layout.resolve_overlaps([a, b], [], board)
	check(solved.stacks[0].position == Vector2(0, 0.5) and solved.stacks[1].position == Vector2(0, -0.5), "Unlocked split evenly")
	check(a.position == Vector2.ZERO and b.position == Vector2.ZERO, "Solver does not mutate callers")
	check(solved.iterations == 2, "Final non-overlap verification pass")
	a.locked = true
	solved = Layout.resolve_overlaps([a, b], [], board)
	check(solved.stacks[0].position == Vector2.ZERO and solved.stacks[1].position == Vector2(0, -1), "Locked A moves B fully")
	a.locked = false
	b.locked = true
	solved = Layout.resolve_overlaps([a, b], [], board)
	check(solved.stacks[0].position == Vector2(0, 1) and solved.stacks[1].position == Vector2.ZERO, "Locked B moves A fully")
	a.locked = true
	solved = Layout.resolve_overlaps([a, b], [], board)
	check(solved.iterations == 1 and not solved.separated_last_pass, "Both locked overlaps ignored")
	a.locked = false
	b.locked = false
	solved = Layout.resolve_overlaps([a, b], [], board, 1.5, 0)
	check(solved.iterations == 0 and solved.stacks[0].position == Vector2.ZERO, "Zero iteration budget does no work")
	solved = Layout.resolve_overlaps([a], [Rect2(-1, -1, 2, 2)], board)
	check(solved.stacks[0].position == Vector2(0, 1.5), "Combat area moves full stack")
	solved = Layout.resolve_overlaps([a, b], [Rect2(-1, -1, 2, 2)], board, 1.5, 1)
	check(solved.stacks[0].position == Vector2(0, 2) and solved.stacks[1].position == Vector2(0, 1), "Combat pass before ordered pairs")
	a.locked = true
	solved = Layout.resolve_overlaps([a], [Rect2(-1, -1, 2, 2)], board)
	check(solved.stacks[0].position == Vector2.ZERO, "Combat rect skips locked stack")
	a.locked = false
	# Impossible separation is bounded, not claimed to converge.
	solved = Layout.resolve_overlaps([a, b], [], Rect2(-0.5, -0.5, 1, 1), 0, 8)
	check(solved.iterations == 8 and solved.separated_last_pass, "Crowded board respects iteration cap")
	a.position = Vector2(100, 100)
	solved = Layout.enforce_board_limits([a], [], board)
	check(solved.stacks[0].position == Vector2(5.5, 2) and solved.iterations == 1, "Shrink clamps and resolves")
	a.position = Vector2(5.51, 2)
	solved = Layout.enforce_board_limits([a], [], board)
	check(solved.stacks[0].position == a.position and solved.iterations == 0, "Source squared movement threshold 0.001")
	var hit := AABB(Vector3(0.8, -0.1, -0.5), Vector3(1, 0.2, 1))
	check(Layout.sphere_intersects_aabb(Vector3.ZERO, 1, hit), "Sphere hits collider even when center is outside radius")
	check(not Layout.sphere_intersects_aabb(Vector3.ZERO, 0.25, hit), "Drop radius smaller than spawn radius")
	var candidates := [{"id": 2, "eligible": true, "card_positions": [Vector3(3, 0, 0), Vector3(0.2, 0, 0)]}, {"id": 3, "eligible": true, "card_positions": [Vector3(-0.2, 0, 0)]}]
	check(Layout.choose_attach_candidate(Vector3.ZERO, candidates, 1) == 2, "Closest member and hit-order tie")
	check(Layout.choose_attach_candidate(Vector3.ZERO, candidates, 1, 2) == 3, "Ignored stack")
	check(Layout.choose_attach_candidate(Vector3.ZERO, candidates, 2) == 3, "Self stack")
	check(Layout.choose_attach_candidate(Vector3.ZERO, candidates, 1, -1, true) == -1, "RefuseAll")
	candidates[0].eligible = false
	check(Layout.choose_attach_candidate(Vector3.ZERO, candidates, 1) == 3, "Caller crafting and matrix eligibility")
	check(Layout.prefab_card_size({}) == Vector2.ZERO, "Missing collider is explicit")
	var path := "res://data/stackcraft.json"
	if FileAccess.file_exists(path):
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var collider_count := 0
		for prefab in data.get("referenced_prefabs", []):
			if Layout.prefab_card_size(prefab) != Vector2.ZERO:
				collider_count += 1
		check(collider_count >= 12, "Read source prefab collider data")
	print("Board layout: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
