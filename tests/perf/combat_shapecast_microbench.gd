# Story-017 microbench — DEPRECATED standalone runner (2026-05-04).
#
# Le pattern original `extends SceneTree` + `godot --headless --script ...` ne
# charge pas les autoloads Godot (AccessibilityService référencé par
# CombatSystem fail au compile). Converti en GdUnit4 test canonique :
#   tests/perf/combat_shapecast_microbench_test.gd
#
# Run command canonique :
#   godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
#     --add tests/perf/combat_shapecast_microbench_test.gd --ignoreHeadlessMode
#
# Ce fichier reste comme stub redirect pour préserver les liens story et
# l'historique git ; il ne fait rien à l'exécution.
#
# Story : production/epics/combat-system/story-017-shapecast-microbench-p99.md

extends SceneTree


func _initialize() -> void:
	push_warning(
		"tests/perf/combat_shapecast_microbench.gd est DEPRECATED — utiliser " +
		"tests/perf/combat_shapecast_microbench_test.gd via GdUnit4 cmdtool."
	)
	quit(0)
