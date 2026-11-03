extends Node
## Throwaway layout probe: prints the rect of each wrapper so the zero-width
## collapse in the ported menu can be located instead of guessed at.


func _ready() -> void:
	await get_tree().process_frame
	var main := load("res://scenes/MainMenu.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_dump(main, 0)
	get_tree().quit(0)


func _dump(node: Node, depth: int) -> void:
	if not node is Control:
		return
	var c := node as Control
	var line := "%s%s %s rect=%s anchors=(%.2f,%.2f,%.2f,%.2f) size_flags=%d" % [
		String("  ").repeat(depth), c.name, c.get_class(), c.get_rect(),
		c.anchor_right, c.anchor_bottom, c.anchor_left, c.anchor_top,
		c.size_flags_horizontal]
	print(line)
	for child in c.get_children():
		_dump(child, depth + 1)
