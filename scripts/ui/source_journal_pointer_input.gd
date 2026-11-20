extends RefCounted
## Host adapter for the pinned Input System mouse frame. Touch emulation
## remains separate; this observer does not consume the board's GUI events.
const Frame := preload("res://scripts/ui/source_journal_pointer_frame.gd")
var _frame := Frame.new()
var _edges := {}
var _held := {}
var _position := Vector2.INF
var _previous := Vector2.INF
var _dirty := false

static func physical_mouse(event: InputEvent) -> bool:
	return (event is InputEventMouseMotion or event is InputEventMouseButton) and event.device>=0

func observe(event: InputEvent, final_transform: Transform2D) -> void:
	if not physical_mouse(event): return
	if not event.position.is_finite(): return
	_position = final_transform*event.position
	_dirty = true
	if not event is InputEventMouseButton or event.button_index not in Frame.BUTTONS: return
	var index: int = event.button_index
	var held: bool = _held.get(index,false)
	if held==event.pressed: return
	if event.pressed: _held[index]=true
	else: _held.erase(index)
	var edge: Vector2i = _edges.get(index,Vector2i.ZERO)
	# A Released-first frame stays Released even if a later raw event
	# re-presses it; only Pressed can advance to PressedAndReleased.
	if edge==Vector2i.ZERO: edge = Vector2i(1,0) if event.pressed else Vector2i(0,1)
	elif edge==Vector2i(1,0) and not event.pressed: edge.y=1
	_edges[index]=edge

func flush(final_transform: Transform2D, raycast: Callable, threshold: float, dispatch: Callable) -> void:
	if not _dirty: return
	var position_snapshot := _position
	var viewport_position := final_transform.affine_inverse()*position_snapshot
	var edge_snapshot := _edges
	var moved := _previous.is_finite() and _previous!=position_snapshot
	_previous = position_snapshot
	_edges = {}
	_dirty = false
	# A Single event-position raycast for all three buttons, before any
	# synchronous click can rebuild rows or move the clip.
	var hit: Dictionary = raycast.call(viewport_position)
	var result := _frame.advance(position_snapshot,moved,edge_snapshot,hit.get("click",0),
			hit.get("down",0),hit.get("drag",0),threshold)
	for receipt in result: dispatch.call(receipt,viewport_position)

func reset() -> void:
	_frame.reset()
	_edges.clear()
	_held.clear()
	_position = Vector2.INF
	_previous = Vector2.INF
	_dirty = false
