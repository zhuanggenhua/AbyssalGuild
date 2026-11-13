extends SceneTree
## Independently authored synthetic fixtures. No licensed source/assets needed.
const Catalog = preload("res://scripts/model/catalog.gd")
const Tracker = preload("res://scripts/model/quest_tracker.gd")
const Journal = preload("res://scripts/ui/quest_journal_state.gd")

class FakeSession:
	var cards: Dictionary = {}
	var discovered_recipes: Dictionary = {}
	var snapshot: Dictionary = {"currency":0, "nutrition":0, "card_limit":24}
	func stats() -> Dictionary:
		return snapshot

var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func definition(id: String, kind: int = Tracker.QuestType.OBTAIN) -> Dictionary:
	return {"guid":id, "fields":{"id":id,"title":"Title " + id,"description":"Body " + id,
		"type":kind,"targetAmount":2,"targetCard":{"guid":"wood"}}}

func fixture(entries: Array) -> Dictionary:
	var catalog = Catalog.new()
	catalog.configure({"quests":entries,"cards":[{"guid":"wood","fields":{"category":0}}]})
	var references: Array = []
	for entry in entries: references.append({"guid":entry.guid})
	var tracker = Tracker.new()
	check(tracker.configure(catalog, "Main", [{"GroupName":"Synthetic", "Quests":references}]), "fixture configuration")
	return {"tracker":tracker,"session":FakeSession.new()}

func restore(tracker, active: Array, completed: Array = []) -> void:
	tracker.restore_state({"CompletedQuests":completed,"ActiveQuests":active})

func instance(tracker, id: String) -> Dictionary:
	for item in tracker.all_quests():
		if item.id == id: return item
	return {}

func caption_retains_creation_state() -> void:
	for kind in [Tracker.QuestType.FOOD, Tracker.QuestType.HAVE]:
		var f := fixture([definition("q", kind)])
		restore(f.tracker, [{"QuestId":"q","CurrentAmount":3}])
		var view = Journal.new()
		view.bind(f.tracker)
		check(view.caption("q") == "• Title q √", "restored at/above target seeds completed-looking caption")
		var initial_info: Dictionary = view.info("q")
		check(initial_info == {"header":"Title q","body":"Body q"}, "creation info uses numeric completion")
		var signals := {"activated":0,"completed":0}
		f.tracker.quest_activated.connect(func(_item): signals.activated += 1)
		f.tracker.quest_completed.connect(func(_item): signals.completed += 1)
		# Real tracker stats replacement decreases both Food and Have progress.
		f.session.snapshot.nutrition = 1
		f.session.cards = {1:{"base_definition_guid":"wood"}}
		f.tracker.sync_stats(f.session)
		check(instance(f.tracker, "q").current_amount == 1, "actual stats update lowered active amount")
		check(instance(f.tracker, "q").status == Tracker.QuestStatus.ACTIVE, "stats decrease retained Active status")
		check(signals == {"activated":0,"completed":0}, "stats decrease emitted no progression event")
		check(view.caption("q") == "• Title q √", "progress decrease does not remove creation suffix")
		check(view.info("q").body == "Body q\n\nProgress: 1 / 2", "new hover info samples decreased live amount")
		check(initial_info.body == "Body q", "previous hover request remains its own snapshot")
		var saved: Dictionary = f.tracker.save_state().duplicate(true)
		var captions: Dictionary = view.captions()
		for repeat in range(3):
			check(view.captions() == captions and view.info("q").body.ends_with("1 / 2"), "repeat query does not reinterpret caption")
		check(f.tracker.save_state() == saved and signals == {"activated":0,"completed":0}, "queries do not mutate save or emit events")
		var external_info: Dictionary = view.info("q")
		external_info.body = "caller-owned override"
		var external_captions: Dictionary = view.captions()
		external_captions.q = "caller-owned override"
		check(view.info("q").body.ends_with("1 / 2") and view.caption("q") == "• Title q √", "returned dictionaries cannot mutate journal state")
		view.bind(f.tracker)
		check(view.caption("q") == "• Title q", "explicit rebuild reevaluates lowered numeric state")
		view.clear()

func completion_is_event_driven() -> void:
	var f := fixture([definition("q"), definition("later")])
	restore(f.tracker, [{"QuestId":"q","CurrentAmount":0}])
	var view = Journal.new()
	view.bind(f.tracker)
	var q: Dictionary = instance(f.tracker, "q")
	check(view.caption("q") == "• Title q", "incomplete initial caption")
	var prior_info: Dictionary = view.info("q")
	q.current_amount = 2 # Isolate numerical state from the completion event.
	check(view.caption("q") == "• Title q", "amount alone does not update existing caption")
	check(view.info("q").body == "Body q", "info reevaluates numeric completion on request")
	check(prior_info.body.ends_with("0 / 2"), "old request does not become a live progress binding")
	var copied: Dictionary = q.duplicate(true)
	check(not is_same(copied, q) and copied == q, "identity fixture equals by value but differs by instance")
	f.tracker.quest_completed.emit(copied)
	check(view.caption("q") == "• Title q", "equal-valued foreign instance cannot complete existing button")
	f.tracker._check(q, f.session)
	check(view.caption("q") == "• Title q √", "actual completion event appends suffix")
	var order_before: Array = view.order.duplicate()
	f.tracker.quest_completed.emit(q)
	f.tracker.quest_completed.emit(q)
	check(view.caption("q") == "• Title q √" and view.caption("q").count("√") == 1, "repeat completion is idempotent")
	check(view.order == order_before, "completion never reorders existing row")
	f.tracker.quest_activated.emit(q)
	check(view.order == order_before, "same-instance duplicate activation ignored")
	var unseen := {"id":"later","status":Tracker.QuestStatus.COMPLETED,"current_amount":2}
	f.tracker.quest_completed.emit(unseen)
	check(not view.captions().has("later"), "completion cannot manufacture uncreated row")
	f.tracker._activate("later", f.session)
	check(view.order == ["later", "q"], "new event activation inserts newest row first")
	check(view.caption("later") == "• Title later", "late activation captures its own numeric state")
	view.clear()

func binding_and_identity_lifetime() -> void:
	var first := fixture([definition("a"), definition("b"), definition("done"), definition("late")])
	restore(first.tracker, [{"QuestId":"a","CurrentAmount":0},{"QuestId":"b","CurrentAmount":1}], ["done"])
	var view = Journal.new()
	var base_activation: int = first.tracker.quest_activated.get_connections().size()
	var base_completion: int = first.tracker.quest_completed.get_connections().size()
	view.bind(first.tracker)
	check(view.order == ["b", "a", "done"], "bind inserts completed then active source enumeration newest-first")
	check(first.tracker.quest_activated.get_connections().size() == base_activation + 1 and first.tracker.quest_completed.get_connections().size() == base_completion + 1, "bind installs exactly one listener per event")
	view.bind(first.tracker)
	check(first.tracker.quest_activated.get_connections().size() == base_activation + 1 and first.tracker.quest_completed.get_connections().size() == base_completion + 1, "same-tracker rebind does not accumulate listeners")
	var old_a: Dictionary = instance(first.tracker, "a")
	restore(first.tracker, [{"QuestId":"a","CurrentAmount":0}])
	view.bind(first.tracker)
	var new_a: Dictionary = instance(first.tracker, "a")
	check(not is_same(old_a, new_a), "restore replaced runtime quest instance")
	old_a.current_amount = 2
	first.tracker.quest_completed.emit(old_a)
	check(view.caption("a") == "• Title a", "stale completion after rebuild cannot modify new same-ID row")
	var second := fixture([definition("other")])
	restore(second.tracker, [{"QuestId":"other","CurrentAmount":0}])
	view.bind(second.tracker)
	check(view.order == ["other"] and not view.captions().has("a"), "different tracker bind clears previous rows")
	check(first.tracker.quest_activated.get_connections().size() == base_activation and first.tracker.quest_completed.get_connections().size() == base_completion, "old tracker listeners disconnected")
	first.tracker._activate("late", first.session)
	first.tracker.quest_completed.emit(new_a)
	check(view.order == ["other"] and view.caption("other") == "• Title other", "old tracker events isolated")
	view.clear()
	check(view.order.is_empty() and view.captions().is_empty(), "clear removes every row")
	check(second.tracker.quest_activated.get_connections().is_empty() and second.tracker.quest_completed.get_connections().is_empty(), "clear disconnects both event listeners")
	second.tracker.quest_activated.emit(instance(second.tracker, "other"))
	second.tracker.quest_completed.emit(instance(second.tracker, "other"))
	check(view.order.is_empty() and view.captions().is_empty(), "events after clear cannot resurrect rows")
	view.clear()
	check(view.order.is_empty(), "clear is idempotent")

func _init() -> void:
	caption_retains_creation_state()
	completion_is_event_driven()
	binding_and_identity_lifetime()
	print("Quest journal lifecycle: %d/%d checks passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
