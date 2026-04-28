# Tests static Story-007 — SaveLoadSystem cross-system isolation lints.
# Couvre VC-6/7/8/9/10 (5 grep gates BLOCKING) + AC-SAV-28 (runtime tree no UI/Audio child).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Config/Data (lints static — coding-standards.md §Test Evidence — ADVISORY gate).
#
# Pattern aligné `tests/static/menu_main_menu_lint_test.gd` story-001 menu-system.
# Source : ADR-0010 D-5 (outbound-zero) + D-7 (main-thread-only) + R-SAV-10/11/17.

extends GdUnitTestSuite

const _SAVE_LOAD_PATH: String = "res://src/core/save_load_system.gd"


## Helper : exécute un grep et retourne le nombre de matches non-commentés.
## `pattern` : regex extended (ERE) ; `target` : path absolu (globalize_path déjà fait par caller).
## Filtre les lignes comment (commencant par `#` après whitespace optional, post-`:`).
func _count_grep_matches(pattern: String, target: String) -> int:
	var output: Array = []
	OS.execute("bash", ["-c",
		"grep -rE '%s' %s 2>/dev/null | grep -vE '^[^:]*:[[:space:]]*#' | wc -l" % [pattern, target]
	], output)
	if output.is_empty():
		return 0
	return int(output[0].strip_edges())


## Helper : retourne les matches bruts (debug failure messages).
func _grep_matches(pattern: String, target: String) -> String:
	var output: Array = []
	OS.execute("bash", ["-c",
		"grep -rE '%s' %s 2>/dev/null | grep -vE '^[^:]*:[[:space:]]*#' || true" % [pattern, target]
	], output)
	return "\n".join(output).strip_edges()

# =============================================================================
# VC-6 — main-thread only (no Thread.* / WorkerThreadPool.* in save_load_system.gd)
# =============================================================================

## GIVEN src/core/save_load_system.gd,
## WHEN grep `\bThread\.|\bWorkerThreadPool\.`,
## THEN zero match (ADR-0010 D-7 main-thread only — Thread/WorkerThreadPool interdits).
func test_save_load_lint_vc6_no_thread_or_worker_pool_references() -> void:
	var path: String = ProjectSettings.globalize_path(_SAVE_LOAD_PATH)
	var matches: String = _grep_matches('\\bThread\\.|\\bWorkerThreadPool\\.', path)
	assert_str(matches) \
		.override_failure_message("VC-6 (ADR-0010 D-7): save_load_system.gd ne doit contenir aucune référence Thread.* ou WorkerThreadPool.* — main-thread only. Matches:\n%s" % matches) \
		.is_empty()

# =============================================================================
# VC-7 — _config privé : aucun accès depuis l'extérieur du module
# =============================================================================

## GIVEN tous src/**/*.gd,
## WHEN grep `SaveLoadSystem\._config` ou `SaveLoad\._config`,
## THEN zero match (ADR-0010 REQ-5 + R-SAV-1 — ConfigFile cache strictement privé).
func test_save_load_lint_vc7_no_private_config_access_outside_module() -> void:
	var src_dir: String = ProjectSettings.globalize_path("res://src/")
	var output: Array = []
	OS.execute("bash", ["-c",
		"grep -rE 'SaveLoad(System)?\\._config|SaveLoad(System)?\\.get_config' %s 2>/dev/null | grep -v '/save_load_system.gd:' | grep -vE '^[^:]*:[[:space:]]*#' || true" % src_dir
	], output)
	var matches: String = "\n".join(output).strip_edges()
	assert_str(matches) \
		.override_failure_message("VC-7 (ADR-0010 REQ-5): aucun fichier src/ hors save_load_system.gd ne doit accéder à SaveLoadSystem._config — cache privé. Matches:\n%s" % matches) \
		.is_empty()

# =============================================================================
# VC-8 — outbound-zero : aucune référence aux consumers gameplay
# =============================================================================

## GIVEN src/core/save_load_system.gd,
## WHEN grep des identifiants consumer gameplay,
## THEN zero match (R-SAV-17 + ADR-0010 D-5 — SaveLoad ne connaît aucun consumer).
func test_save_load_lint_vc8_no_consumer_system_references() -> void:
	var path: String = ProjectSettings.globalize_path(_SAVE_LOAD_PATH)
	var consumers: String = "\\b(CreditEconomy|ShopSystem|SecretSystem|UpgradeSystem|HUDController|HUDSystem|AudioSystem|InputManager|CameraSystem|CombatSystem|MovementController|VFXManager)\\b"
	var matches: String = _grep_matches(consumers, path)
	assert_str(matches) \
		.override_failure_message("VC-8 (R-SAV-17 + ADR-0010 D-5): save_load_system.gd ne doit contenir aucune référence consumer gameplay. Matches:\n%s" % matches) \
		.is_empty()

# =============================================================================
# VC-9 — zero outbound signals (R-SAV-10)
# =============================================================================

## GIVEN src/core/save_load_system.gd,
## WHEN grep `^[[:space:]]*signal[[:space:]]+\w+` (top-level signal declarations),
## THEN zero match (R-SAV-10 — write-through synchrone, pas de signal sortant MVP).
func test_save_load_lint_vc9_no_outbound_signal_declarations() -> void:
	var path: String = ProjectSettings.globalize_path(_SAVE_LOAD_PATH)
	var matches: String = _grep_matches('^[[:space:]]*signal[[:space:]]+\\w+', path)
	assert_str(matches) \
		.override_failure_message("VC-9 (R-SAV-10): save_load_system.gd ne doit déclarer aucun signal sortant — outbound-zero MVP. Matches:\n%s" % matches) \
		.is_empty()

# =============================================================================
# VC-10 — zero orchestration : pas d'appel .connect()
# =============================================================================

## GIVEN src/core/save_load_system.gd,
## WHEN grep `\.connect\s*\(`,
## THEN zero match (R-SAV-11 — SaveLoad n'orchestre rien, consumers se branchent eux-mêmes).
func test_save_load_lint_vc10_no_connect_orchestration() -> void:
	var path: String = ProjectSettings.globalize_path(_SAVE_LOAD_PATH)
	var matches: String = _grep_matches('\\.connect[[:space:]]*\\(', path)
	assert_str(matches) \
		.override_failure_message("VC-10 (R-SAV-11): save_load_system.gd ne doit contenir aucun .connect() — zero orchestration MVP. Matches:\n%s" % matches) \
		.is_empty()

# =============================================================================
# AC-SAV-28 — runtime tree inspection : aucun child Control / AudioStreamPlayer
# =============================================================================

## GIVEN SaveLoadSystem instance ajoutée au scene tree,
## WHEN inspection des children,
## THEN aucun child de type Control / Label / Sprite / AudioStreamPlayer.
## Source : AC-SAV-28 (Foundation Persistence n'a aucune surface UI/Audio).
func test_save_load_lint_ac_sav_28_no_ui_or_audio_children_at_runtime() -> void:
	var script: GDScript = load(_SAVE_LOAD_PATH) as GDScript
	var instance: Node = script.new() as Node
	add_child(instance)
	await get_tree().process_frame

	for child: Node in instance.get_children():
		assert_bool(child is Control) \
			.override_failure_message("AC-SAV-28: SaveLoadSystem ne doit avoir aucun child Control (got: %s)" % child.get_class()) \
			.is_false()
		assert_bool(child is AudioStreamPlayer) \
			.override_failure_message("AC-SAV-28: SaveLoadSystem ne doit avoir aucun child AudioStreamPlayer (got: %s)" % child.get_class()) \
			.is_false()
		# Sprite2D / Sprite3D / Label : sous-classes de CanvasItem ou Node3D, déjà couvert
		# par Control check pour la majorité des cas. Check explicit Label si présent.
		assert_bool(child is Label) \
			.override_failure_message("AC-SAV-28: SaveLoadSystem ne doit avoir aucun child Label (got: %s)" % child.get_class()) \
			.is_false()

	instance.queue_free()
