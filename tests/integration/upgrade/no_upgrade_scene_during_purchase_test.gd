# Integration test Story-011 — AC-UPG-37 (a) (b) : aucun scene/Control instancié pendant apply_upgrade.
#
# Pillar 2 anti-friction : Upgrade ne doit JAMAIS instancier de scène ni de
# Control UI lors d'un apply (R-UPG-6 zéro signal outbound MVP, AC-UPG-37).
# Ce test snapshot l'arbre /root avant/après apply_upgrade et vérifie zéro
# nouveau node owned par `res://src/gameplay/upgrade/` ni Control nommé
# `skill|tree|talent|perk|respec`.
#
# AC : production/epics/upgrade-system/story-011-playtest-pillar2-understanding-evidence.md (AC-UPG-37)
# GDD : design/gdd/upgrade-system.md (R-UPG-6 zéro signal outbound + Pillar 2)
# Framework : GdUnit4 v5

extends GdUnitTestSuite


const FORBIDDEN_SUBSTRINGS: Array[String] = ["skill", "tree", "talent", "perk", "respec"]


func _collect_all_nodes(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		result.append(n)
		for child in n.get_children():
			stack.append(child)
	return result


func _is_owned_by_upgrade_dir(n: Node) -> bool:
	var script: Script = n.get_script() as Script
	if script == null:
		return false
	return str(script.resource_path).begins_with("res://src/gameplay/upgrade/")


func _is_forbidden_control(n: Node) -> bool:
	if not (n is Control):
		return false
	var lower: String = str(n.name).to_lower()
	for substring in FORBIDDEN_SUBSTRINGS:
		if substring in lower:
			return true
	return false


# =============================================================================
# AC-UPG-37 (a) — aucun nouveau node owned par src/gameplay/upgrade/
# =============================================================================

## GIVEN snapshot /root avant apply_upgrade,
## WHEN Upgrade.apply_upgrade(&"double_jump") + 1 process_frame,
## THEN aucun nouveau node dans /root n'a un script owned par res://src/gameplay/upgrade/.
## Source : AC-UPG-37 (a), R-UPG-6 zéro signal outbound MVP.
func test_apply_upgrade_emits_zero_upgrade_owned_nodes() -> void:
	# Arrange
	var root: Node = Engine.get_main_loop().root
	var upgrade: UpgradeSystem = root.get_node("Upgrade") as UpgradeSystem
	assert_object(upgrade).override_failure_message(
		"Upgrade autoload introuvable — bootstrap project.godot incorrect"
	).is_not_null()

	var nodes_before: Array[Node] = _collect_all_nodes(root)

	# Act
	upgrade.apply_upgrade(&"double_jump")
	await get_tree().process_frame

	# Assert
	var nodes_after: Array[Node] = _collect_all_nodes(root)
	var new_nodes: Array[Node] = []
	for n in nodes_after:
		if not (n in nodes_before):
			new_nodes.append(n)

	var upgrade_owned: Array[Node] = []
	for n in new_nodes:
		if _is_owned_by_upgrade_dir(n):
			upgrade_owned.append(n)

	var names: Array[String] = []
	for n in upgrade_owned:
		names.append(str(n.name))
	assert_int(upgrade_owned.size()).override_failure_message(
		"AC-UPG-37 (a) FAIL : %d nouveaux nodes owned par src/gameplay/upgrade/ : %s" \
			% [upgrade_owned.size(), str(names)]
	).is_equal(0)


# =============================================================================
# AC-UPG-37 (b) — aucun Control name skill|tree|talent|perk|respec
# =============================================================================

## GIVEN snapshot /root avant apply_upgrade,
## WHEN Upgrade.apply_upgrade(&"dash_horizontal") + 1 process_frame,
## THEN aucun nouveau Control n'a un name contenant `skill|tree|talent|perk|respec`.
## Source : AC-UPG-37 (b), Pillar 2 anti-skill-tree visual.
func test_apply_upgrade_emits_zero_skill_tree_ui() -> void:
	# Arrange
	var root: Node = Engine.get_main_loop().root
	var upgrade: UpgradeSystem = root.get_node("Upgrade") as UpgradeSystem
	assert_object(upgrade).override_failure_message(
		"Upgrade autoload introuvable — bootstrap project.godot incorrect"
	).is_not_null()

	var nodes_before: Array[Node] = _collect_all_nodes(root)

	# Act
	upgrade.apply_upgrade(&"dash_horizontal")
	await get_tree().process_frame

	# Assert
	var nodes_after: Array[Node] = _collect_all_nodes(root)
	var new_nodes: Array[Node] = []
	for n in nodes_after:
		if not (n in nodes_before):
			new_nodes.append(n)

	var ui_violators: Array[Node] = []
	for n in new_nodes:
		if _is_forbidden_control(n):
			ui_violators.append(n)

	var names: Array[String] = []
	for n in ui_violators:
		names.append(str(n.name))
	assert_int(ui_violators.size()).override_failure_message(
		"AC-UPG-37 (b) FAIL : %d Control nodes avec name forbidden (skill|tree|talent|perk|respec) : %s" \
			% [ui_violators.size(), str(names)]
	).is_equal(0)
