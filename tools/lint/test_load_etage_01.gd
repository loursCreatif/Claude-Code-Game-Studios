extends SceneTree

func _init() -> void:
	var ps: PackedScene = load("res://scenes/levels/etage_01.tscn")
	if ps == null:
		push_error("LOAD_FAILED — null PackedScene")
		quit(1)
		return
	var inst: Node = ps.instantiate()
	if inst == null:
		push_error("INSTANTIATE_FAILED")
		quit(1)
		return
	root.add_child(inst)
	print("LOAD_OK type=%s top_children=%d" % [inst.get_class(), inst.get_child_count()])
	var expected: PackedStringArray = PackedStringArray([
		"StaticEnvironment", "InteractiveVolumes", "SpawnMarkers",
		"OnboardingAnchors", "EtageExitTrigger"
	])
	for name_str: String in expected:
		var has: bool = inst.has_node(name_str)
		print("  %s: %s" % [name_str, "OK" if has else "MISSING"])
	quit(0)
