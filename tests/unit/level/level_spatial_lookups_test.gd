# Tests unitaires Story-009 — Spatial Lookups API (checkpoint / enemy / hazard / tutorial).
# Couvre AC-LVL-30, AC-LVL-30b, AC-LVL-30c, AC-LVL-44.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Chaque test crée sa propre instance de LevelSystemScript — aucun état partagé.
# Le setter test-only `_set_current_scene_root_for_test` est utilisé pour injecter
# un scene tree synthétique sans déclencher de chargement threadé (pattern story-004
# cohérent avec `_simulate_load_elapsed_ms`).
#
# Story    : production/epics/level-system/story-009-spatial-lookups-api.md
# GDD      : design/gdd/level-system.md — AC-LVL-30 / AC-LVL-30b / AC-LVL-30c
# ADR      : ADR-0005 D-10 (API read-only consommée par peers depuis _on_level_active)

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Crée un LevelSystemScript frais attaché au tree (déclenche _ready).
func _make_level() -> LevelSystemScript:
	var level: LevelSystemScript = LevelSystemScript.new()
	add_child(level)
	return level


## Crée une Node3D racine attachée au tree (global_position disponible).
## Utilisée comme _current_scene_root injectable via _set_current_scene_root_for_test.
func _make_scene_root() -> Node3D:
	var root: Node3D = Node3D.new()
	add_child(root)
	return root


## Ajoute un Marker3D nommé `marker_name` à `parent` à la position `pos`.
## Retourne le Marker3D créé.
func _add_marker(parent: Node3D, marker_name: String, pos: Vector3 = Vector3.ZERO) -> Marker3D:
	var m: Marker3D = Marker3D.new()
	m.name = marker_name
	m.position = pos
	parent.add_child(m)
	return m


## Ajoute une Area3D nommée `area_name` à `parent`.
## Retourne l'Area3D créée.
func _add_area(parent: Node3D, area_name: String) -> Area3D:
	var a: Area3D = Area3D.new()
	a.name = area_name
	parent.add_child(a)
	return a


# ---------------------------------------------------------------------------
# AC-LVL-30 — get_tutorial_anchor : null sur tag inconnu, valide sur tag connu
# ---------------------------------------------------------------------------

## Vérifie que get_tutorial_anchor retourne null pour un tag inconnu,
## le Marker3D pour un tag connu, et null pour un tag avec casse différente.
## Source : AC-LVL-30, ADR-0005 D-10, story-009.
func test_get_tutorial_anchor_returns_null_for_unknown_tag() -> void:
	# Arrange
	var level: LevelSystemScript = _make_level()
	var root: Node3D = _make_scene_root()
	var dash_marker: Marker3D = _add_marker(root, "first_dash", Vector3(1.0, 0.0, 2.0))
	_add_marker(root, "first_wall", Vector3(5.0, 0.0, 0.0))
	level._set_current_scene_root_for_test(root)
	await get_tree().process_frame

	# Act — tag inconnu
	var result_unknown: Marker3D = level.get_tutorial_anchor("nonexistent")

	# Act — tag connu (case-sensitive match)
	var result_known: Marker3D = level.get_tutorial_anchor("first_dash")

	# Act — tag casse incorrecte (case-sensitive — "First_Dash" != "first_dash")
	var result_wrong_case: Marker3D = level.get_tutorial_anchor("First_Dash")

	# Assert
	assert_object(result_unknown) \
		.override_failure_message("AC-LVL-30: tag inconnu doit retourner null") \
		.is_null()
	assert_object(result_known) \
		.override_failure_message("AC-LVL-30: tag 'first_dash' doit retourner le Marker3D") \
		.is_same(dash_marker)
	assert_object(result_wrong_case) \
		.override_failure_message("AC-LVL-30: get_tutorial_anchor est case-sensitive — 'First_Dash' doit retourner null") \
		.is_null()

	level.free()
	root.free()


# ---------------------------------------------------------------------------
# AC-LVL-30b — get_checkpoint_slots : tuples paired volume↔anchor
# ---------------------------------------------------------------------------

## Vérifie que get_checkpoint_slots retourne un Array de 2 tuples {volume, anchor}
## correspondant aux paires CheckpointVolume_01/02 ↔ CheckpointAnchor_01/02.
## Volume sans anchor paired → skip silencieux (pas d'exception).
## 0 checkpoints → empty array.
## Source : AC-LVL-30b, ADR-0005 D-10, story-009.
func test_get_checkpoint_slots_returns_paired_tuples() -> void:
	# Arrange — 2 paires valides + 1 volume orphelin (CheckpointVolume_03 sans anchor)
	var level: LevelSystemScript = _make_level()
	var root: Node3D = _make_scene_root()

	var vol01: Area3D = _add_area(root, "CheckpointVolume_01")
	var anchor01: Marker3D = _add_marker(root, "CheckpointAnchor_01", Vector3(1.0, 0.5, 0.0))
	var vol02: Area3D = _add_area(root, "CheckpointVolume_02")
	var anchor02: Marker3D = _add_marker(root, "CheckpointAnchor_02", Vector3(10.0, 0.5, 5.0))
	# Volume orphelin sans anchor — doit être skippé avec push_warning
	_add_area(root, "CheckpointVolume_03")

	level._set_current_scene_root_for_test(root)
	await get_tree().process_frame

	# Act
	var slots: Array = level.get_checkpoint_slots()

	# Assert — longueur (volume_03 orphelin skippé)
	assert_array(slots) \
		.override_failure_message("AC-LVL-30b: get_checkpoint_slots() doit retourner 2 tuples (vol_03 orphelin skippé)") \
		.has_size(2)

	# Assert — structure des tuples (clés volume + anchor)
	for slot: Variant in slots:
		var entry: Dictionary = slot as Dictionary
		assert_bool(entry.has("volume")) \
			.override_failure_message("AC-LVL-30b: chaque tuple doit avoir la clé 'volume'") \
			.is_true()
		assert_bool(entry.has("anchor")) \
			.override_failure_message("AC-LVL-30b: chaque tuple doit avoir la clé 'anchor'") \
			.is_true()
		assert_bool(entry["volume"] is Area3D) \
			.override_failure_message("AC-LVL-30b: 'volume' doit être une Area3D") \
			.is_true()
		assert_bool(entry["anchor"] is Vector3) \
			.override_failure_message("AC-LVL-30b: 'anchor' doit être un Vector3") \
			.is_true()

	# Assert — positions anchor correctes (global_position du Marker3D paired).
	# On construit un dict volume→anchor pour vérifier indépendamment de l'ordre DFS.
	var pos_map: Dictionary = {}
	for slot: Variant in slots:
		var entry: Dictionary = slot as Dictionary
		pos_map[entry["volume"]] = entry["anchor"]

	assert_bool(pos_map.has(vol01)) \
		.override_failure_message("AC-LVL-30b: vol01 absent du résultat") \
		.is_true()
	assert_bool(pos_map.has(vol02)) \
		.override_failure_message("AC-LVL-30b: vol02 absent du résultat") \
		.is_true()
	assert_vector(pos_map[vol01]) \
		.override_failure_message("AC-LVL-30b: anchor01 position incorrecte") \
		.is_equal(anchor01.global_position)
	assert_vector(pos_map[vol02]) \
		.override_failure_message("AC-LVL-30b: anchor02 position incorrecte") \
		.is_equal(anchor02.global_position)

	level.free()
	root.free()


# ---------------------------------------------------------------------------
# Test get_enemy_slots : retourne tous les EnemySlot_* Marker3D
# ---------------------------------------------------------------------------

## Vérifie que get_enemy_slots retourne exactement 3 Marker3D pour une scène
## avec EnemySlot_01/02/03, et que chaque élément est bien un Marker3D.
## Edge case : 0 enemies → empty array.
## Source : AC-LVL-30 (implicit scope), ADR-0005 D-10, story-009.
func test_get_enemy_slots_returns_all_enemy_markers() -> void:
	# Arrange — 3 EnemySlot_*
	var level: LevelSystemScript = _make_level()
	var root: Node3D = _make_scene_root()
	_add_marker(root, "EnemySlot_01", Vector3(0.0, 0.0, 0.0))
	_add_marker(root, "EnemySlot_02", Vector3(5.0, 0.0, 0.0))
	_add_marker(root, "EnemySlot_03", Vector3(10.0, 0.0, 0.0))
	level._set_current_scene_root_for_test(root)
	await get_tree().process_frame

	# Act
	var slots: Array[Marker3D] = level.get_enemy_slots()

	# Assert — 3 markers, tous Marker3D
	assert_array(slots) \
		.override_failure_message("get_enemy_slots() doit retourner 3 éléments") \
		.has_size(3)
	for slot: Marker3D in slots:
		assert_bool(slot is Marker3D) \
			.override_failure_message("chaque élément de get_enemy_slots() doit être un Marker3D") \
			.is_true()

	# Edge case — 0 enemies (étage traversal-only)
	var level_empty: LevelSystemScript = _make_level()
	var root_empty: Node3D = _make_scene_root()
	level_empty._set_current_scene_root_for_test(root_empty)
	await get_tree().process_frame

	var slots_empty: Array[Marker3D] = level_empty.get_enemy_slots()
	assert_array(slots_empty) \
		.override_failure_message("get_enemy_slots() doit retourner un array vide si aucun ennemi") \
		.is_empty()

	level.free()
	root.free()
	level_empty.free()
	root_empty.free()


# ---------------------------------------------------------------------------
# Test get_hazard_slots : retourne tous les HazardSlot_* Marker3D
# ---------------------------------------------------------------------------

## Vérifie que get_hazard_slots retourne exactement 1 Marker3D pour une scène
## avec un unique HazardSlot_01.
## Source : AC-LVL-30 (implicit scope), ADR-0005 D-10, story-009.
func test_get_hazard_slots_returns_all_hazard_markers() -> void:
	# Arrange — 1 HazardSlot_*
	var level: LevelSystemScript = _make_level()
	var root: Node3D = _make_scene_root()
	_add_marker(root, "HazardSlot_01", Vector3(2.0, 0.0, 3.0))
	level._set_current_scene_root_for_test(root)
	await get_tree().process_frame

	# Act
	var slots: Array[Marker3D] = level.get_hazard_slots()

	# Assert
	assert_array(slots) \
		.override_failure_message("get_hazard_slots() doit retourner 1 élément") \
		.has_size(1)
	assert_bool(slots[0] is Marker3D) \
		.override_failure_message("get_hazard_slots()[0] doit être un Marker3D") \
		.is_true()

	level.free()
	root.free()


# ---------------------------------------------------------------------------
# AC-LVL-30c — Lookups avant level_active retournent valeurs safe
# ---------------------------------------------------------------------------

## Vérifie que les 4 méthodes lookup retournent des valeurs safe ([] ou null)
## quand _current_scene_root == null (état UNLOADED — level instancié sans load_etage()).
## Aucune exception ne doit être levée.
## Source : AC-LVL-30c, story-009 implementation notes.
func test_lookups_before_level_active_return_empty() -> void:
	# Arrange — level instancié sans load_etage(), _current_scene_root == null
	var level: LevelSystemScript = _make_level()
	await get_tree().process_frame
	# Précondition : état UNLOADED confirmé
	assert_int(level.get_state()) \
		.override_failure_message("AC-LVL-30c précondition: état doit être UNLOADED") \
		.is_equal(LevelSystemScript.LevelState.UNLOADED)

	# Act — appel des 4 méthodes sans scène chargée
	var checkpoint_slots: Array = level.get_checkpoint_slots()
	var enemy_slots: Array[Marker3D] = level.get_enemy_slots()
	var hazard_slots: Array[Marker3D] = level.get_hazard_slots()
	var tutorial_anchor: Marker3D = level.get_tutorial_anchor("foo")

	# Assert — valeurs safe, aucune exception
	assert_array(checkpoint_slots) \
		.override_failure_message("AC-LVL-30c: get_checkpoint_slots() avant level_active doit retourner []") \
		.is_empty()
	assert_array(enemy_slots) \
		.override_failure_message("AC-LVL-30c: get_enemy_slots() avant level_active doit retourner []") \
		.is_empty()
	assert_array(hazard_slots) \
		.override_failure_message("AC-LVL-30c: get_hazard_slots() avant level_active doit retourner []") \
		.is_empty()
	assert_object(tutorial_anchor) \
		.override_failure_message("AC-LVL-30c: get_tutorial_anchor() avant level_active doit retourner null") \
		.is_null()

	level.free()
