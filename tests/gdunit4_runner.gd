# DEPRECATED — broken stub kept for legacy CI references.
#
# The actual safe headless invocation pattern is:
#
#   godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
#     --add tests/ --ignoreHeadlessMode
#
# Prerequisite : .godot/global_script_class_cache.cfg must exist
# (Editor must have opened the project at least once).
#
# See CLAUDE.md §Godot CLI Safety §Authorized exception for full context.
extends SceneTree

func _init() -> void:
	push_error(
		"tests/gdunit4_runner.gd is deprecated. " +
		"Use: godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd " +
		"--add tests/ --ignoreHeadlessMode"
	)
	quit(1)
