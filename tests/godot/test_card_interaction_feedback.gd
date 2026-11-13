extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Card = preload("res://scripts/model/card.gd")
const Stack = preload("res://scripts/model/stack.gd")
const SaveCodec = preload("res://scripts/model/save_codec.gd")
const Descriptors = preload("res://scripts/ui/card_interaction_descriptors.gd")
const HoverView = preload("res://scripts/ui/card_hover_view.gd")
const ProgressView = preload("res://scripts/ui/craft_progress_view.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
var checks: int = 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func fixture():
	var catalog = Catalog.new()
	var rules: Array = []
	rules.resize(144)
	rules.fill(0)
	rules[4 * 12 + 2] = 1
	rules[4 * 12 + 4] = 2
	catalog.configure({"cards": [
		{"guid": "hero", "fields": {"displayName": "Hero", "description": "A character.", "category": 2, "combatType": 2, "maxHealth": 15}},
		{"guid": "civilian", "fields": {"displayName": "Civilian", "description": "A worker.", "category": 2, "combatType": 0}},
		{"guid": "wood", "fields": {"displayName": "Wood", "description": "A material.", "category": 4}},
		{"guid": "wood_other", "fields": {"displayName": "Wood", "description": "Another material.", "category": 4}},
		{"guid": "mob", "fields": {"displayName": "Creature", "description": "A creature.", "category": 9, "combatType": 1}},
		{"guid": "gear", "fields": {"displayName": "Gear", "category": 5, "statModifiers": [{"Stat": 0, "value": 4}, {"Stat": 1, "value": 3}]}}
	], "recipes": [{"guid": "recipe", "script_class": "RecipeDefinition", "fields": {"id": "recipe", "displayName": "Make a thing", "craftingDuration": 8, "requiredIngredients": [{"card": {"guid": "wood"}, "count": 1}], "allowExcessIngredients": true}}],
	"settings": [{"guid": "rules", "script_class": "StackingRulesMatrix", "fields": {"rules": rules}}]})
	var session = Session.new()
	session.configure(catalog, 414)
	# Direct synthetic records avoid any spawning/matching/randomness in the fixture.
	for id in 10:
		var guid: String = ["hero", "wood", "wood", "wood_other", "civilian", "mob", "gear", "wood", "wood", "hero"][id]
		session.cards[id] = Card.new(id, guid, catalog.fields(guid))
	for id in 7:
		var stack = Stack.new(100 + id)
		stack.position = Vector2(id, id * -2)
		session.stacks[stack.id] = stack
	for pair in [[100, [0]], [101, [1, 2, 3]], [102, [4]], [103, [5]], [104, [7]], [105, [8, 9]]]:
		session.stacks[pair[0]].card_ids = pair[1]
		for id in pair[1]: session.cards[id].stack_id = pair[0]
	session.equipment.equipped[0] = {0: 6}
	session.equipment.owners[6] = 0
	return session

func run() -> void:
	var session = fixture()
	var before: String = JSON.stringify(SaveCodec.capture(session))
	var rng_before: int = session.rng.state
	var hero: Dictionary = Descriptors.hover_info(session, 0)
	check(hero.header == "Hero" and hero.kind == "card", "singleton name")
	check(hero.body.begins_with("A character.\nHealth (15/19)\nRanged\n"), "live effective health and combat type")
	check(hero.body.contains("Attack (5)") and hero.body.contains("Defense (1)"), "equipped combat statistics")
	check(hero.body.ends_with("Crit. Multiplier (150)") and hero.body.split("\n").size() == 11, "all eight source stat fields")
	check(Descriptors.hover_info(session, 4).body == "A worker.\nHealth (15/15)", "noncombat character has health without combat stats")
	check(Descriptors.hover_info(session, 5).body == "A creature.", "mob does not get invented Character-only stats")
	check(Descriptors.hover_info(session, 6).is_empty(), "unstacked equipment matches source empty hover")
	check(Descriptors.hover_info(session, -1).is_empty() and Descriptors.hover_info(session, 0, false).is_empty(), "missing and suppressed hover clear")
	var grouped: Dictionary = Descriptors.hover_info(session, 2)
	check(grouped.header == "Stack of Cards" and grouped.body == "Wood x2, Wood x1.", "groups by definition not by identical display names; first order retained")
	session.cards[2].definition_guid = "hero"
	check(Descriptors.hover_info(session, 1).body == "Wood x1, Hero x1, Wood x1.", "groups use live effective definitions")
	session.cards[2].definition_guid = "wood"
	session.cards[0].health = 7
	check(Descriptors.hover_info(session, 0).body.contains("Health (7/19)"), "fresh hover sees health changes")
	session.cards[0].health = 15
	check(JSON.stringify(SaveCodec.capture(session)) == before and session.rng.state == rng_before, "hover reads do not mutate snapshot or RNG")

	var craft = session.stacks[101]
	craft.recipe_guid = "recipe"
	session.crafting.activate(craft) # Explicit presentation-only task fixture.
	craft.progress = 2.25
	var craft_hover: Dictionary = Descriptors.hover_info(session, 3)
	check(craft_hover.kind == "craft" and craft_hover.header == "Make a thing" and craft_hover.body == "Time left: 5.8s", "craft takes precedence on every member")
	var progress: Dictionary = Descriptors.crafting_progress(session)
	check(progress.size() == 1 and progress[101].top_card_id == 1, "one bar per task; source TopCard is first")
	check(progress[101].anchor.is_equal_approx(Vector3(1, 0, -1.45)), "progress follows stack target plus source offset, no stack-top index lift")
	check(is_equal_approx(progress[101].ratio, 2.25 / 8) and not progress[101].paused, "task normalized ratio")
	craft.paused = true
	session.paused = true
	var paused: Dictionary = Descriptors.crafting_progress(session)
	check(paused[101].paused and paused[101].ratio == progress[101].ratio, "paused task still displays exact progress")
	check(Descriptors.hover_info(session, 1).body == craft_hover.body, "paused hover countdown frozen")
	craft.paused = false
	session.paused = false
	session.phase = "feeding"
	check(Descriptors.crafting_progress(session)[101].paused, "day sequence pauses task but does not invent a timer")
	session.phase = "playing"
	session.speed = 0
	check(Descriptors.crafting_progress(session)[101].paused, "zero speed is reported paused")
	session.speed = 1
	craft.progress = 100
	check(Descriptors.crafting_progress(session)[101].ratio == 1 and Descriptors.hover_info(session, 1).body == "Time left: 0.0s", "pending completion stays bounded")
	craft.progress = -2
	check(Descriptors.crafting_progress(session)[101].ratio == 0, "negative presentation progress cannot invert fill")
	craft.progress = NAN
	check(Descriptors.crafting_progress(session).is_empty() and Descriptors.hover_info(session, 1).kind == "stack", "invalid progress cannot leak NaN to UI")
	craft.progress = 2.25
	for duration in [0.0, -1.0, INF, NAN]:
		session.catalog.definitions.recipe.fields.craftingDuration = duration
		check(Descriptors.crafting_progress(session).is_empty(), "invalid recipe duration omitted")
	session.catalog.definitions.recipe.fields.craftingDuration = 8
	craft.recipe_guid = "missing"
	check(Descriptors.crafting_progress(session).is_empty(), "missing recipe omitted without starting another")
	craft.recipe_guid = "recipe"
	session.crafting.activate(craft) # Explicit presentation-only task fixture.
	session.catalog.definitions.recipe.fields.requiredIngredients[0].count = 99
	check(Descriptors.crafting_progress(session).has(101), "presentation trusts registered task instead of rematching ingredients")
	session.catalog.definitions.recipe.fields.requiredIngredients[0].count = 1

	var qualified: Array = [100, 101, 102, 103, 104, 105, 106, -1, 100, "100"]
	var targets: Dictionary = Descriptors.drag_targets(session, 7, qualified)
	check(targets.keys() == [0, 4, 9], "only authoritative eligible targets; source BottomCard is final array member")
	check(not targets.has(3), "craft target excluded even if active excess join is valid")
	check(Descriptors.drag_targets(session, 7, []).is_empty(), "no qualified candidates invents no target")
	check(Descriptors.drag_targets(session, 7, qualified, false).is_empty(), "suppressed drag clears all")
	check(Descriptors.drag_targets(session, 999, qualified).is_empty(), "dead lifted card clears all")
	check(Descriptors.drag_targets(session, 6, qualified).is_empty(), "unstacked equipment does not invent stack drag")
	var saved_card = session.cards[9]
	session.cards.erase(9)
	check(not Descriptors.drag_targets(session, 7, qualified).has(9), "dead target removed")
	check(Descriptors.hover_info(session, 8).is_empty(), "stale stack member clears hover rather than dereferencing dead card")
	session.cards[9] = saved_card
	session.cards[9].stack_id = 100
	check(not Descriptors.drag_targets(session, 7, qualified).has(9), "reparented stale target rejected")
	session.cards[9].stack_id = 105
	before = JSON.stringify(SaveCodec.capture(session))
	for iteration in 15:
		Descriptors.hover_info(session, 1)
		Descriptors.drag_targets(session, 7, qualified)
		Descriptors.crafting_progress(session)
	check(JSON.stringify(SaveCodec.capture(session)) == before and session.rng.state == rng_before, "all repeated descriptors preserve model/save/RNG state")

	check_paused_partial_tail()
	check_stackless_ownership()
	check_equipment_panel_info()
	await check_renderers(session)
	print("Card interaction feedback synthetic checks: %d passed; no GPU/manual visual acceptance" % checks)
	quit()

func check_paused_partial_tail() -> void:
	# Drive the actual source-correct held-tail model, not a generic mismatch fixture.
	var session = Session.new()
	session.configure(fixture().catalog, 414)
	var recipe: Dictionary = session.catalog.definitions.recipe.fields
	recipe.requiredIngredients = [{"card": {"guid": "wood"}, "count": 2}, {"card": {"guid": "wood_other"}, "count": 1}]
	recipe.allowExcessIngredients = false
	var base_id: int = session.spawn_card("wood", Vector2(1, -2))
	var original = session.stacks[session.cards[base_id].stack_id]
	var lifted_id: int = session.spawn_card("wood", Vector2.ZERO, original.id)
	session.spawn_card("wood_other", Vector2.ZERO, original.id)
	check(session.matches_recipe(original, recipe), "partial-tail fixture initially matches strict recipe")
	session._check_recipe(original)
	check(original.recipe_guid == "recipe", "model registers actual selected task before pickup")
	original.progress = 2.25
	var view = ProgressView.new()
	root.add_child(view)
	view.sync(Descriptors.crafting_progress(session))
	var meter: Node3D = view.bars[original.id].root
	var original_anchor: Vector3 = meter.position
	for return_to_original in [true, false]:
		var picked: Dictionary = session.drag.begin(lifted_id)
		check(picked.ok and picked.split and session.drag.original_stack_id(lifted_id) == original.id, "actual pickup retains original registered crafting task")
		check(not session.matches_recipe(original, recipe) and original.card_ids == [base_id], "lifted required tail leaves paused singleton base temporarily incomplete")
		# capture() settles a held checkpoint clone; compare raw LIVE state here instead.
		var before: String = JSON.stringify(SaveCodec._capture_unsettled(session))
		var rng_before: int = session.rng.state
		var info: Dictionary = Descriptors.hover_info(session, base_id)
		check(info.kind == "craft" and info.header == "Make a thing" and info.body == "Time left: 5.8s", "paused incomplete base retains registered recipe hover")
		check(Descriptors.hover_info(session, lifted_id).kind == "stack", "held tail has no invented craft task")
		var progress: Dictionary = Descriptors.crafting_progress(session)
		check(progress.size() == 1 and progress.has(original.id) and progress[original.id].paused and is_equal_approx(progress[original.id].ratio, 2.25 / 8), "paused incomplete original keeps exactly one frozen meter")
		view.sync(progress)
		check(view.bars[original.id].root == meter and meter.position == original_anchor and meter.visible, "partial-tail pickup does not remove or relocate original meter")
		for iteration in 3:
			Descriptors.hover_info(session, base_id)
			Descriptors.crafting_progress(session)
		check(JSON.stringify(SaveCodec._capture_unsettled(session)) == before and session.rng.state == rng_before and original.paused and original.progress == 2.25, "partial-tail display cannot validate/cancel/resume task or mutate state/RNG")
		session.tick(0.5)
		check(Descriptors.hover_info(session, base_id).body == info.body and original.progress == 2.25, "real game tick leaves held incomplete task countdown frozen")
		if return_to_original:
			check(session.move_to_stack(lifted_id, original.id, session.drag.original_stack_id(lifted_id)), "actual return attaches lifted ingredients to original")
			session.drag.finish_standard(original.id)
			progress = Descriptors.crafting_progress(session)
			view.sync(progress)
			check(progress[original.id].ratio == 2.25 / 8 and not progress[original.id].paused and view.bars[original.id].root == meter, "return resumes same original task and meter without restarting progress")
		else:
			session.drag.finish_standard()
			view.sync(Descriptors.crafting_progress(session))
			check(original.recipe_guid.is_empty() and view.bars.is_empty(), "meter disappears only after model release validation cancels task")
			check(Descriptors.hover_info(session, base_id).kind == "card", "canceled original returns to singleton information")
	view.free()

func check_stackless_ownership() -> void:
	# Source CardInstance.GetInfo returns empty immediately for Stack == null.
	# EquipmentPanel's separate inventory hover is not the equipped card tooltip.
	var session = Session.new()
	var catalog = fixture().catalog
	catalog.definitions.hero.fields.faction = 1
	catalog.definitions.mob.fields.faction = 2
	session.configure(catalog, 414)
	var hero: int = session.spawn_card("hero")
	var mob: int = session.spawn_card("mob")
	var gear: int = session.spawn_card("gear")
	check(not Descriptors.hover_info(session, gear).is_empty(), "loose equipment has ordinary singleton information")
	check(session.equipment.equip(hero, gear), "real equipment ownership established")
	check(session.cards[gear].stack_id == -1 and session.equipment.owners[gear] == hero, "equipped card is live and owned but stackless")
	check(Descriptors.hover_info(session, gear).is_empty(), "expanded equipped-card hover follows source null-Stack early return")
	check(Descriptors.hover_info(session, hero).body.contains("Health (15/19)"), "equipped wearer on board retains effective-stat hover")
	check(session.combat.start_combat([hero], [mob]) > 0, "real combat ownership established")
	check(session.combat.membership.has(hero) and session.cards[hero].stack_id == -1, "live combatant belongs to combat rather than stack")
	check(Descriptors.hover_info(session, hero).is_empty() and Descriptors.hover_info(session, mob).is_empty(), "live stackless combat members match source empty hover")
	check(Descriptors.equipment_panel_info(session, hero).body == "• Gear", "combat owner's distinct equipment panel still reports attached names")
	check(Descriptors.drag_targets(session, hero, session.stacks.keys()).is_empty() and Descriptors.crafting_progress(session).is_empty(), "stackless ownership invents neither stacking targets nor crafting task")
	session.combat.remove_combatant(hero)
	check(Descriptors.hover_info(session, hero).body.contains("Health (15/19)"), "return to world stack restores character tooltip")
	check(session.equipment.unequip(hero, 0) == gear and not Descriptors.hover_info(session, gear).is_empty(), "unequip restores ordinary equipment tooltip")
	var actual_stack: int = session.cards[gear].stack_id
	session.cards[gear].stack_id = 99999
	check(Descriptors.hover_info(session, gear).is_empty(), "missing positive stack reference never becomes fallback per-card information")
	session.cards[gear].stack_id = actual_stack
	session.stacks[actual_stack].card_ids.erase(gear)
	check(Descriptors.hover_info(session, gear).is_empty(), "inconsistent registered stack membership clears hover")
	session.stacks[actual_stack].card_ids.append(gear)
	session._remove_card(gear)
	check(Descriptors.hover_info(session, gear).is_empty(), "destroyed formerly owned gear clears hover")

func check_equipment_panel_info() -> void:
	var session = Session.new()
	var catalog = fixture().catalog
	var armor_definition: Dictionary = catalog.definitions.gear.duplicate(true)
	armor_definition.guid = "armor"
	armor_definition.fields.displayName = "Armor"
	armor_definition.fields.equipmentSlot = 1
	catalog.data.cards.append(armor_definition)
	catalog.definitions.armor = armor_definition
	session.configure(catalog, 414)
	var owner: int = session.spawn_card("hero")
	var other_owner: int = session.spawn_card("hero")
	var gear: int = session.spawn_card("gear")
	var armor: int = session.spawn_card("armor")
	check(Descriptors.equipment_panel_info(session, owner).is_empty(), "empty panel does not invent hover")
	check(session.equipment.equip(owner, armor) and session.equipment.equip(owner, gear), "real panel has two attached items in non-slot order")
	var info: Dictionary = Descriptors.equipment_panel_info(session, owner)
	check(info.kind == "equipment_panel" and info.owner_id == owner and info.header == "Equipments", "panel descriptor is routed by distinct owner metadata")
	check(info.body == "• Armor\n• Gear", "source panel lists names in attachment order without extra card stats")
	check(Descriptors.hover_info(session, gear).is_empty(), "panel hover does not invent equipped-card tooltip")
	check(Descriptors.equipment_panel_info(session, owner, false).is_empty() and Descriptors.equipment_panel_info(session, -1).is_empty(), "blocked and stale panel routes clear")
	var before: String = JSON.stringify(SaveCodec._capture_unsettled(session))
	var rng_before: int = session.rng.state
	for iteration in 5: Descriptors.equipment_panel_info(session, owner)
	check(JSON.stringify(SaveCodec._capture_unsettled(session)) == before and session.rng.state == rng_before, "panel hover is read-only and consumes no RNG")
	session.equipment.owners[gear] = other_owner
	check(Descriptors.equipment_panel_info(session, owner).body == "• Armor", "stale ownership entry cannot expose another wearer's gear")
	session.equipment.owners[gear] = owner
	var saved = session.cards[armor]
	session.cards.erase(armor)
	check(Descriptors.equipment_panel_info(session, owner).body == "• Gear", "dead item is excluded from panel hover")
	session.cards[armor] = saved
	session.equipment.unequip(owner, 1)
	check(Descriptors.equipment_panel_info(session, owner).body == "• Gear", "unequip removes panel row immediately")
	session.equipment.unequip(owner, 0)
	check(Descriptors.equipment_panel_info(session, owner).is_empty(), "last unequip clears panel descriptor")
	session.equipment.equip(owner, gear)
	session.cards.erase(owner)
	check(Descriptors.equipment_panel_info(session, owner).is_empty(), "dead panel owner clears lingering ownership rows")

func check_renderers(session) -> void:
	var hover = HoverView.new()
	root.add_child(hover)
	check(not hover.visible, "new hover view starts empty and hidden")
	hover.set_bounds(Rect2(20, 30, 340, 400))
	hover.set_descriptor(Descriptors.hover_info(session, 0))
	await process_frame
	check(hover.visible and hover.header.text == "[Hero]" and hover.body.text.contains("Health (15/19)"), "native hover renders complete descriptor")
	var malicious := {"header": "[b]Literal[/b]", "body": "[url]Literal text[/url]"}
	hover.set_descriptor(malicious)
	check(not hover.body.bbcode_enabled and hover.body.text == malicious.body, "source descriptions stay literal text")
	malicious.body = "changed"
	check(hover.descriptor.body != malicious.body, "view snapshots do not alias descriptors")
	for factor in [0.5, 1.0, 2.0, 3.0]:
		hover.set_bounds(Rect2(0, 0, 180, 180), factor)
		hover.set_descriptor({"header": "VeryLongUnbrokenTitle".repeat(20), "body": "A long description. ".repeat(200)})
		await process_frame
		check(hover.clip_contents and hover.header.clip_text and hover.body.scroll_active, "long text bounded with scroll at every scale")
		check(hover.header.position.x + hover.header.size.x <= hover.size.x + 0.01, "header width clipped at requested size")
		check(hover.body.position.x + hover.body.size.x <= hover.size.x + 0.01, "body width does not force panel outside HUD")
		check(hover.body.text.length() > 1000 and hover.body.get_theme_font_size("normal_font_size") == 30, "source logical font size retained independently of CanvasScaler")
	hover.body.get_v_scroll_bar().value = 80
	var scroll: float = hover.body.get_v_scroll_bar().value
	hover.set_descriptor(hover.descriptor)
	check(hover.body.get_v_scroll_bar().value == scroll, "unchanged frame snapshot preserves user scroll")
	hover.set_bounds(Rect2(0, 0, 2, 2))
	await process_frame
	check(not hover.body.visible, "tiny available region hides body without negative bounds")
	hover.set_descriptor({})
	check(not hover.visible and hover.header.text.is_empty() and hover.body.text.is_empty(), "pointer exit/menu/travel reset clears full hover content")
	hover.free()

	var progress = ProgressView.new()
	root.add_child(progress)
	progress.sync(Descriptors.crafting_progress(session))
	check(progress.bars.size() == 1, "native progress creates one task view")
	var record: Dictionary = progress.bars[101]
	var first: Node3D = record.root
	check(first.position.is_equal_approx(Vector3(1, 0.0, 1.45)), "rendered anchor reflects Z exactly once")
	check(first.material_override.get_shader_parameter("ratio") == 2.25 / 8.0, "normalized horizontal fill")
	check(first.mesh.size.is_equal_approx(Vector2(.8,.05)), "fill grows from fixed left edge")
	for iteration in 6: progress.sync(Descriptors.crafting_progress(session))
	check(progress.get_child_count() == 1 and progress.bars[101].root == first, "repeat snapshots reuse bar")
	session.stacks[101].paused = true
	progress.sync(Descriptors.crafting_progress(session))
	check(first.get_meta("paused") and first.visible, "paused bar stays visible")
	session.stacks[101].position = Vector2(12, 4)
	progress.sync(Descriptors.crafting_progress(session))
	check(first.position.is_equal_approx(Vector3(12, 0.0, -4.55)), "moving stack retargets bar using root, not stack-top")
	session.stacks[101].progress = 0
	progress.sync(Descriptors.crafting_progress(session))
	check(first.material_override.get_shader_parameter("ratio") == 0 and first.visible, "zero progress has empty fill with visible background")
	progress.sync({101: {"anchor": Vector3.ZERO, "ratio": NAN}})
	check(progress.bars.is_empty() and progress.get_child_count() == 0, "invalid descriptor clears old progress immediately")
	progress.sync({101: "malformed"})
	check(progress.bars.is_empty(), "malformed progress snapshot fails closed")
	progress.sync(Descriptors.crafting_progress(session))
	progress.reset()
	progress.reset()
	check(progress.bars.is_empty() and progress.get_child_count() == 0, "cancel/completion/travel/menu reset idempotent")
	progress.free()

	var card = CardView.new()
	root.add_child(card)
	card.configure(0, "Target", 2, false, null, {}, "Main", Vector3(2, 0.06, 3))
	card.highlight(true)
	card.set_hurt_flash(0.8)
	var color: Color = card.material.albedo_color
	var emission: Color = card.material.emission
	var before: int = card.get_child_count()
	card.set_drag_target(false)
	check(card.get_child_count() == before, "false snapshot creates no idle target nodes")
	Descriptors.apply_target_highlights({0: card}, {0: {"stack_id": 100}})
	check(card.drag_target.visible and card.drag_target.edges.size() == 4, "independent generated outline visible")
	check(card.material.albedo_color == color and card.material.emission == emission and card.hurt_flash == 0.8, "target never changes selection or hurt-flash surface")
	var outline = card.drag_target
	card.scale = Vector3.ONE * 0.7
	for iteration in 6: card.set_drag_target(true)
	check(card.drag_target == outline and card.get_child_count() == before + 1, "repeated highlight reuses overlay without accumulating scale")
	check(outline.scale == Vector3.ONE and outline.get_global_transform().basis.get_scale().is_equal_approx(card.scale), "outline inherits card scale once")
	Descriptors.apply_target_highlights({0: card}, {})
	check(not outline.visible and card.material.emission_enabled and card.hurt_flash == 0.8, "release/menu clear preserves selected and hurt state")
	card.source_material = ShaderMaterial.new()
	card.source_material.shader = preload("res://scripts/ui/shaders/card_surface.gdshader")
	card.highlight(true)
	card.set_hurt_flash(0.7)
	var source_emission: Vector3 = card.source_material.get_shader_parameter("selection_emission")
	card.set_drag_target(true)
	card.set_drag_target(false)
	check(card.source_material.get_shader_parameter("selection_emission") == source_emission and is_equal_approx(card.source_material.get_shader_parameter("flash_amount"), 0.7), "source shader selection and hit flash also independent")
	card.free()
	Descriptors.apply_target_highlights({0: card}, {0: {}})
	check(true, "freed view is safely ignored")
	await process_frame
