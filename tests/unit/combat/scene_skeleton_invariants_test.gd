# Tests unitaires Story-001 — CombatSystem scene skeleton & structural invariants.
# Couvre AC-CMB-49 Partie B (structural invariants) : AC-1, AC-2, AC-3.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Chaque test crée sa propre instance — aucun état partagé.
#
# Story   : production/epics/combat-system/story-001-scene-skeleton-structural-invariants.md
# ADR     : ADR-0006 D-1 (direct child) + D-2 (process_physics_priority == 0)
# Req     : TR-cmb-001, TR-cmb-002

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Crée un CharacterBody3D et y attache un CombatSystem comme child direct.
## Déclenche _ready() via add_child sur le tree. Retourne le CombatSystem.
func _make_combat_under_player() -> CombatSystem:
	var player: CharacterBody3D = CharacterBody3D.new()
	add_child(player)
	var combat: CombatSystem = CombatSystem.new()
	player.add_child(combat)
	return combat


# ---------------------------------------------------------------------------
# AC-1 — Scene skeleton parent invariant
# ---------------------------------------------------------------------------

## Positif : CombatSystem enfant direct d'un CharacterBody3D → aucun assert panic.
func test_combat_parent_invariant_characterbody3d_parent_no_panic() -> void:
	# Arrange + Act : _ready() déclenché lors du add_child sur le tree
	var player: CharacterBody3D = CharacterBody3D.new()
	add_child(player)
	var combat: CombatSystem = CombatSystem.new()

	# Assert — aucune exception lors de l'ajout (parent est CharacterBody3D)
	assert_error(
		func() -> void: player.add_child(combat)
	).is_not_push_error()

	player.queue_free()


## Négatif : CombatSystem enfant d'un Node3D générique → assert panic "Combat parent must be CharacterBody3D".
func test_combat_parent_invariant_node3d_parent_push_error() -> void:
	if not OS.has_feature("debug"):
		# En release, assert() est no-op — ce test couvre uniquement le path debug.
		assert_bool(true).is_true()
		return

	# Arrange : parent non-CharacterBody3D (Node3D générique)
	var wrong_parent: Node3D = Node3D.new()
	add_child(wrong_parent)
	var combat: CombatSystem = CombatSystem.new()

	# Act + Assert — l'assert dans _ready() doit émettre un push_error en debug
	assert_error(
		func() -> void: wrong_parent.add_child(combat)
	).is_push_error("Combat parent must be CharacterBody3D (Player)")

	wrong_parent.queue_free()


## Négatif : CombatSystem comme grandchild (parent est Node3D, pas CharacterBody3D) → assert panic.
func test_combat_parent_invariant_grandchild_of_player_push_error() -> void:
	if not OS.has_feature("debug"):
		assert_bool(true).is_true()
		return

	# Arrange : Player → Node3D intermédiaire → CombatSystem (grandchild = violation)
	var player: CharacterBody3D = CharacterBody3D.new()
	add_child(player)
	var intermediate: Node3D = Node3D.new()
	player.add_child(intermediate)
	var combat: CombatSystem = CombatSystem.new()

	# Act + Assert — le parent direct est Node3D (pas CharacterBody3D) → assert panic
	assert_error(
		func() -> void: intermediate.add_child(combat)
	).is_push_error("Combat parent must be CharacterBody3D (Player)")

	player.queue_free()


# ---------------------------------------------------------------------------
# AC-2 — Priority invariant
# ---------------------------------------------------------------------------

## Positif : process_physics_priority par défaut (0) → aucun assert panic à _ready().
func test_combat_priority_invariant_default_zero_no_panic() -> void:
	# Arrange + Act
	var player: CharacterBody3D = CharacterBody3D.new()
	add_child(player)
	var combat: CombatSystem = CombatSystem.new()

	# Assert — pas d'erreur lors du add_child (priority = 0 par défaut)
	assert_error(
		func() -> void: player.add_child(combat)
	).is_not_push_error()

	# Vérifier que la valeur est bien 0 après _ready()
	assert_int(combat.process_physics_priority) \
		.override_failure_message("AC-2: process_physics_priority doit être 0 après _ready()") \
		.is_equal(0)

	player.queue_free()


## Négatif : muter process_physics_priority à 1 puis forcer un 2e _ready() → assert panic.
## Note : Godot ne rappelle pas _ready() automatiquement. On simule via call directe
## après mutation, ce qui est l'unique vecteur de test sans re-instancier.
func test_combat_priority_invariant_nonzero_priority_push_error() -> void:
	if not OS.has_feature("debug"):
		assert_bool(true).is_true()
		return

	# Arrange : instancier correctement (parent OK, priority 0)
	var combat: CombatSystem = _make_combat_under_player()
	await get_tree().process_frame

	# Act : muter la priorité à 1 (violation D-2)
	combat.process_physics_priority = 1

	# Assert : appel direct de _ready() après mutation → assert panic sur priority
	assert_error(
		func() -> void: combat._ready()
	).is_push_error("Combat process_physics_priority must be default 0 (DFS preorder Rule 17)")

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-5 — Scene file existe avec root CombatSystem + child ShapeCast3D
# ---------------------------------------------------------------------------

## Charge combat_system.tscn et vérifie : root = CombatSystem (Node3D), child ShapeCast3D présent.
## Couvre AC-5 (story-001) : scaffold scène structurellement valide.
func test_combat_scene_loads_with_combatsystem_root_and_shapecast_child() -> void:
	# Arrange
	const SCENE_PATH: String = "res://src/gameplay/combat/combat_system.tscn"
	var packed: PackedScene = load(SCENE_PATH) as PackedScene

	# Assert load
	assert_object(packed) \
		.override_failure_message("AC-5: combat_system.tscn introuvable ou non chargeable") \
		.is_not_null()

	# Act : instancier dans le tree
	var root: Node = packed.instantiate()
	var player: CharacterBody3D = CharacterBody3D.new()
	add_child(player)
	player.add_child(root)

	# Assert root type
	assert_bool(root is CombatSystem) \
		.override_failure_message("AC-5: root scene doit être CombatSystem (reçu: %s)" % root.get_class()) \
		.is_true()

	# Assert ShapeCast3D child présent
	var shape_cast: Node = root.get_node_or_null("ShapeCast3D")
	assert_object(shape_cast) \
		.override_failure_message("AC-5: child ShapeCast3D manquant dans combat_system.tscn") \
		.is_not_null()
	assert_bool(shape_cast is ShapeCast3D) \
		.override_failure_message("AC-5: child ShapeCast3D doit être de type ShapeCast3D") \
		.is_true()

	player.queue_free()


# ---------------------------------------------------------------------------
# AC-3 — Rule 15 grep : absence de patterns interdits dans combat_system.gd
# ---------------------------------------------------------------------------

## Vérifie qu'aucun symbole interdit (is_invulnerable, invuln_timer, 0b00100)
## n'est présent en dehors des commentaires dans combat_system.gd.
## (AC-CMB-49 Partie A — Rule 15 one-shot symétrie)
func test_combat_rule15_no_invulnerability_symbols_in_source() -> void:
	# Arrange : lire le source GDScript
	const SOURCE_PATH: String = "res://src/gameplay/combat/combat_system.gd"
	var source: String = FileAccess.get_file_as_string(SOURCE_PATH)

	assert_str(source) \
		.override_failure_message("AC-3: impossible de lire " + SOURCE_PATH + " — chemin invalide") \
		.is_not_empty()

	# Act : vérifier ligne par ligne — exclure les lignes commentées (commençant par #)
	var lines: PackedStringArray = source.split("\n")
	var violations: Array[String] = []
	var forbidden_patterns: Array[String] = [
		"is_invulnerable",
		"invuln_timer",
		"0b00100",   # EnemyHitbox layer bitmask littéral (ADR-0008 + Rule 15)
	]

	for i: int in range(lines.size()):
		var line: String = lines[i]
		var trimmed: String = line.strip_edges()
		# Exclure les lignes entièrement commentées
		if trimmed.begins_with("#"):
			continue
		# Inspecter la partie hors-commentaire de la ligne (gère # avec ou sans espace)
		var code_part: String = line
		var comment_pos: int = line.find("#")
		if comment_pos != -1:
			code_part = line.substr(0, comment_pos)

		for pattern: String in forbidden_patterns:
			if code_part.contains(pattern):
				violations.append("Ligne %d : '%s' contient '%s' (Rule 15 / AC-CMB-49 Partie A)" % [
					i + 1, line.strip_edges(), pattern
				])

	# Assert
	assert_array(violations) \
		.override_failure_message(
			"AC-3 Rule 15 violations trouvées dans combat_system.gd :\n" + "\n".join(violations)
		) \
		.is_empty()
