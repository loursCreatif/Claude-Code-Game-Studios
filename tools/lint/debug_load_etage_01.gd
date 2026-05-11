extends SceneTree

# Outil de diagnostic standalone — charge et instancie scenes/levels/etage_01.tscn
# pour vérifier la présence des sous-arbres top-level attendus.
#
# Usage CLI (multi-session safe via --script) :
#   godot --headless --script tools/lint/debug_load_etage_01.gd
#
# Ce n'est PAS un test GdUnit4 — pas couvert par la suite CI automatisée.
# Pour la validation pré-build complète des invariants ADR-0011 D-7, utiliser
# `tools/lint/run_level_lint.gd` (CI job `lint-level-invariants`).
#
# Note : `OnboardingAnchors` est listé obligatoire ICI car ce script est dédié
# à etage_01 (étage 1 only par règle `level-hierarchy-invariants.md`). Pour
# tout autre étage, ce sous-arbre est optionnel.

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
	# Sous-arbres canoniques ADR-0011 D-2 (4 mandatoires + OnboardingAnchors
	# étage-1-only) :
	var expected: PackedStringArray = PackedStringArray([
		"StaticEnvironment", "InteractiveVolumes", "SpawnMarkers",
		"OnboardingAnchors",  # étage 1 only — voir level-hierarchy-invariants.md
		"EtageExitTrigger"
	])
	for name_str: String in expected:
		var has: bool = inst.has_node(name_str)
		print("  %s: %s" % [name_str, "OK" if has else "MISSING"])
	quit(0)
