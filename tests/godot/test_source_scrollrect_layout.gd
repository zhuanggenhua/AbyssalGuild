extends SceneTree
const Host = preload("res://scripts/ui/source_saved_slot_host.gd")
func _init() -> void: call_deferred("run")
func run() -> void:
	# No frame/resize callbacks have had a chance to repair the initial layout.
	var host = Host.new()
	host.source = {"synthetic":true}
	host.size = Vector2(800,660)
	host.padding = Vector4(10,10,10,10)
	host.bar.custom_minimum_size.x = 20
	host.add_child(host.clip)
	host.add_child(host.bar)
	host.clip.add_child(host.content)
	var row := Control.new()
	row.custom_minimum_size.y = 100
	host.content.add_child(row)
	host.rows.append(row)
	print("Initial bar width: ",host.bar.size.x)
	host.relayout()
	print("Initial row width: ",row.size.x,"; clip: ",host.clip.size.x)
	assert(host.clip.size.x==780 and host.content.size.x==780)
	assert(row.position.x==10 and row.size.x==760)
	assert(row.position.x+row.size.x+host.padding.z==host.clip.size.x)
	host.free()
	print("Source ScrollRect first layout: PASS")
	quit()
