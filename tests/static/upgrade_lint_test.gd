# Static lint tests Stories-008 / 009 — UpgradeSystem anti-patterns.
# AC-UPG-6-bis (zéro mutation _CATALOG), AC-UPG-27 (zéro signal custom),
# AC-UPG-28 (zéro SaveLoadSystem.save_*/write_*), AC-UPG-34 (zéro UI nodes),
# AC-UPG-35 (zéro audio API), AC-UPG-36 (zéro revoke_upgrade).
# Framework : GdUnit4 (extends GdUnitTestSuite).

extends GdUnitTestSuite

const _UPGRADE_SOURCE: String = "res://src/gameplay/upgrade/upgrade_system.gd"


# =============================================================================
# Helpers
# =============================================================================

static func _read_source(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


static func _non_comment_matches(src: String, pattern: String) -> Array:
	var regex: RegEx = RegEx.new()
	regex.compile(pattern)
	var hits: Array = []
	for m in regex.search_all(src):
		var line_start: int = src.rfind("\n", m.get_start()) + 1
		var line_end: int = src.find("\n", m.get_end())
		if line_end == -1:
			line_end = src.length()
		var line: String = src.substr(line_start, line_end - line_start)
		if not line.strip_edges().begins_with("#"):
			hits.append(line.strip_edges())
	return hits


# =============================================================================
# AC-UPG-6-bis BLOCKING — zéro mutation _CATALOG en production
# =============================================================================

## GIVEN src/gameplay/upgrade/upgrade_system.gd,
## WHEN grep `\b_CATALOG\s*\[[^\]]*\]\s*=` excluant commentaires,
## THEN zéro match (lectures `_CATALOG[id]` rhs et `_CATALOG.has(id)` autorisées).
## Source : AC-UPG-6-bis + R-UPG-3 (catalog owned exclusivement Upgrade).
func test_upgrade_no_catalog_mutation_in_production_source() -> void:
	var src: String = _read_source(_UPGRADE_SOURCE)
	assert_str(src) \
		.override_failure_message("AC-UPG-6-bis: impossible de lire %s" % _UPGRADE_SOURCE) \
		.is_not_empty()

	var hits: Array = _non_comment_matches(src, "\\b_CATALOG\\s*\\[[^\\]]*\\]\\s*=")

	assert_int(hits.size()) \
		.override_failure_message("AC-UPG-6-bis VIOLATION: %d mutation(s) _CATALOG détectée(s): %s" % [hits.size(), hits]) \
		.is_equal(0)


# =============================================================================
# AC-UPG-27 BLOCKING — zéro signal custom (R-UPG-6)
# =============================================================================

## Whitelist signaux hérités Object/Node Godot 4.6.
## À ré-valider à chaque migration mineure (4.6 → 4.7 PR coordonnée VERSION.md).
const _GODOT_46_INHERITED_SIGNALS: Array[StringName] = [
	# Object
	&"script_changed",
	&"property_list_changed",
	# Node
	&"ready",
	&"renamed",
	&"tree_entered",
	&"tree_exiting",
	&"tree_exited",
	&"child_entered_tree",
	&"child_exiting_tree",
	&"child_order_changed",
	&"replacing_by",
	&"editor_description_changed",
	&"editor_state_changed",
]


## GIVEN UpgradeSystem instance bare,
## WHEN get_signal_list() filtré contre whitelist Object/Node Godot 4.6,
## THEN liste résultante vide (R-UPG-6 zéro signal outbound MVP).
func test_upgrade_no_custom_signals_outbound() -> void:
	var s: UpgradeSystem = UpgradeSystem.new()

	var custom_signals: Array = []
	for sig: Dictionary in s.get_signal_list():
		if not (StringName(sig.name) in _GODOT_46_INHERITED_SIGNALS):
			custom_signals.append(sig.name)

	assert_int(custom_signals.size()) \
		.override_failure_message("AC-UPG-27 VIOLATION: signaux custom détectés sur UpgradeSystem: %s" % custom_signals) \
		.is_equal(0)

	s.free()


# =============================================================================
# AC-UPG-28 BLOCKING — zéro SaveLoadSystem.save_*/write_* (R-UPG-10)
# =============================================================================

## GIVEN upgrade_system.gd source,
## WHEN grep `\bSaveLoad(System)?\s*\.\s*(save_|write_)`,
## THEN zéro match (Upgrade ne persiste jamais — seul Shop écrit owned_upgrades).
func test_upgrade_no_saveload_write_calls() -> void:
	var src: String = _read_source(_UPGRADE_SOURCE)
	var hits: Array = _non_comment_matches(src, "\\bSaveLoad(System)?\\s*\\.\\s*(save_|write_)")
	assert_int(hits.size()) \
		.override_failure_message("AC-UPG-28 VIOLATION: SaveLoadSystem.save_*/write_* trouvé: %s" % hits) \
		.is_equal(0)


# =============================================================================
# AC-UPG-34 BLOCKING — zéro référence UI nodes (R-UPG-14 single responsibility)
# =============================================================================

## GIVEN upgrade_system.gd,
## WHEN grep word-boundary contre liste UI nodes Godot 4.6 communs,
## THEN zéro match (pas de couplage UI dans Upgrade — UI consomme via pull pattern).
func test_upgrade_no_ui_node_references() -> void:
	var src: String = _read_source(_UPGRADE_SOURCE)
	var pattern: String = "\\b(Control|Label|CanvasLayer|Button|Panel|RichTextLabel|Container|VBoxContainer|HBoxContainer|TextureRect|NinePatchRect|Sprite2D|Sprite3D)\\b"
	var hits: Array = _non_comment_matches(src, pattern)
	assert_int(hits.size()) \
		.override_failure_message("AC-UPG-34 VIOLATION: UI nodes référencés: %s" % hits) \
		.is_equal(0)


# =============================================================================
# AC-UPG-35 BLOCKING — zéro API audio (R-UPG-14 single responsibility)
# =============================================================================

## GIVEN upgrade_system.gd,
## WHEN grep contre API audio Godot 4.6 (AudioStreamPlayer*, AudioServer, etc.),
## THEN zéro match (Audio System découpe consomme via pull pattern downstream).
func test_upgrade_no_audio_api_references() -> void:
	var src: String = _read_source(_UPGRADE_SOURCE)
	var pattern: String = "\\b(AudioStreamPlayer|AudioStreamPlayer2D|AudioStreamPlayer3D|AudioServer|AudioBus|audio_)"
	var hits: Array = _non_comment_matches(src, pattern)
	assert_int(hits.size()) \
		.override_failure_message("AC-UPG-35 VIOLATION: audio API référencée: %s" % hits) \
		.is_equal(0)


# =============================================================================
# AC-UPG-36 BLOCKING — zéro revoke_upgrade (R-UPG-12 pas de revoke MVP)
# =============================================================================

## GIVEN upgrade_system.gd,
## WHEN grep `\brevoke_upgrade\b` (word-boundary),
## THEN zéro match (R-UPG-12 — pas d'API revoke MVP, anti-pilier "skill tree").
func test_upgrade_no_revoke_upgrade_function() -> void:
	var src: String = _read_source(_UPGRADE_SOURCE)
	var hits: Array = _non_comment_matches(src, "\\brevoke_upgrade\\b")
	assert_int(hits.size()) \
		.override_failure_message("AC-UPG-36 VIOLATION: revoke_upgrade trouvé: %s" % hits) \
		.is_equal(0)
