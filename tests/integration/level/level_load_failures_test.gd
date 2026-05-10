# Tests d'intégration Story-004 — signaux level_load_failed (EC-3) + level_load_slow advisory (EC-10).
# Couvre AC-LVL-6 (missing scene → level_load_failed), AC-LVL-7 (slow load > 600 ms → level_load_slow).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Fixtures : tests/fixtures/levels/test_etage_42.tscn (Node3D + Marker3D PlayerStart).
# Chaque test crée sa propre instance de LevelSystemScript — aucun état partagé.
#
# Stratégie déterminisme (AC-LVL-7) :
#   Option A — helper _simulate_load_elapsed_ms(ms) décale _load_started_msec en arrière
#   pour simuler un chargement lent sans vrai sleep (debug build only — no-op en release).
#   Cela évite les dépendances à la durée réelle du chargement (variance CI).

extends GdUnitTestSuite

const _FIXTURE_PATH_TEMPLATE: String = "res://tests/fixtures/levels/test_etage_%02d.tscn"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Crée un LevelSystemScript avec la fixture de test et l'attache au scene tree.
## scene_path_template défini AVANT add_child() (DI principle).
func _make_level() -> LevelSystemScript:
	var level: LevelSystemScript = LevelSystemScript.new()
	level.scene_path_template = _FIXTURE_PATH_TEMPLATE
	add_child(level)
	return level


## Crée un LevelSystemScript utilisant le path template DE PRODUCTION (pas de fixture).
## Sert à tester les failures sur des id inexistants (etage_999 → path prod absent).
func _make_level_production_paths() -> LevelSystemScript:
	var level: LevelSystemScript = LevelSystemScript.new()
	# scene_path_template non overridé → _DEFAULT_SCENE_PATH_TEMPLATE (prod)
	add_child(level)
	return level

# ---------------------------------------------------------------------------
# AC-LVL-6 — load_etage(999) sur id inexistant émet level_load_failed(999, reason)
# ---------------------------------------------------------------------------

## Vérifie que load_etage(999) sur un id inexistant :
##   1. Émet level_load_failed(999, reason) avec reason non vide
##   2. Laisse l'état en UNLOADED
##   3. Laisse get_current_etage_id() == -1
## Source : TR-lvl-026, TR-lvl-029, ADR-0007 D-7.
## Méthode : path prod "res://scenes/levels/etage_999.tscn" n'existe pas →
## ResourceLoader.exists() retourne false → pré-check level_system.gd l.258.
func test_load_etage_999_emits_level_load_failed() -> void:
	# Arrange — path production (etage_999.tscn n'existe pas en prod ni en tests)
	var level: LevelSystemScript = _make_level_production_paths()
	await get_tree().process_frame

	# Container Dictionary pour bypass GDScript lambda capture-by-value sur primitives.
	var captured: Dictionary = {"etage_id": -99, "reason": ""}
	level.level_load_failed.connect(func(eid: int, reason: String) -> void:
		captured["etage_id"] = eid
		captured["reason"] = reason
	)

	# Act
	level.load_etage(999)

	# Vérification immédiate post-appel : l'état ne doit PAS être LOADING (pré-check détecté)
	# et le flag pending est positionné pour l'emit au prochain _physics_process.
	assert_int(level.get_state()) \
		.override_failure_message("AC-LVL-6: état doit rester UNLOADED après load_etage(999) — path inexistant") \
		.is_equal(LevelSystemScript.LevelState.UNLOADED)
	assert_int(level.get_current_etage_id()) \
		.override_failure_message("AC-LVL-6: etage_id doit être -1 immédiatement après load_etage(999) rejeté") \
		.is_equal(-1)

	# Await signal level_load_failed depuis _physics_process (ADR-0005 D-4 — deferred).
	await await_signal_on(level, "level_load_failed", [], 2000)

	# Assert payload
	assert_int(captured["etage_id"]) \
		.override_failure_message("AC-LVL-6: level_load_failed.etage_id doit être 999") \
		.is_equal(999)
	assert_bool((captured["reason"] as String).length() > 0) \
		.override_failure_message("AC-LVL-6: level_load_failed.reason ne doit pas être vide") \
		.is_true()

	# Assert état final — UNLOADED (invariant AC-LVL-6)
	assert_int(level.get_state()) \
		.override_failure_message("AC-LVL-6: état doit être UNLOADED après level_load_failed") \
		.is_equal(LevelSystemScript.LevelState.UNLOADED)
	assert_int(level.get_current_etage_id()) \
		.override_failure_message("AC-LVL-6: get_current_etage_id() doit être -1 après failure") \
		.is_equal(-1)

	# Cleanup
	level.queue_free()


## Variante AC-LVL-6 : vérifie que la reason inclut le path de la scène manquante.
## Permet de diagnostiquer quel fichier était absent (TR-lvl-029 : "debug : push_error details").
func test_load_etage_999_reason_contains_path() -> void:
	# Arrange
	var level: LevelSystemScript = _make_level_production_paths()
	await get_tree().process_frame

	# Container Dictionary pour bypass GDScript lambda capture-by-value sur primitives.
	var captured: Dictionary = {"reason": ""}
	level.level_load_failed.connect(func(_eid: int, reason: String) -> void:
		captured["reason"] = reason
	)

	# Act
	level.load_etage(999)
	await await_signal_on(level, "level_load_failed", [], 2000)

	# Assert — la reason mentionne "999" (id de l'étage absent)
	assert_bool((captured["reason"] as String).contains("999")) \
		.override_failure_message(
			"AC-LVL-6 variante: reason doit contenir '999' pour faciliter le diagnostic (got: '%s')" % captured["reason"]
		) \
		.is_true()

	# Cleanup
	level.queue_free()

# ---------------------------------------------------------------------------
# AC-LVL-7 — level_load_slow émis une fois si load > 600 ms, puis level_active
# ---------------------------------------------------------------------------

## Vérifie que :
##   1. level_load_slow est émis exactement une fois (elapsed_ms ≥ 600)
##   2. Le chargement continue (non-bloquant — AC-LVL-7 invariant)
##   3. level_active est ensuite émis (AC-LVL-7 : "load continue, level_active toujours émis")
##   4. L'état final est ACTIVE
##
## Stratégie déterminisme : _simulate_load_elapsed_ms(700) décale _load_started_msec
## en arrière de 700 ms → le polling _process voit (now - started) > 600 dès le tick suivant.
## Pas de vrai sleep 800 ms → test rapide et stable en CI.
## Source : TR-lvl-027, story-004 Option A, ADR-0011 D-5.
func test_level_load_slow_emitted_after_600ms() -> void:
	# Arrange — fixture etage_42 existe dans tests/fixtures/levels/
	var level: LevelSystemScript = _make_level()
	await get_tree().process_frame

	# Container Dictionary pour bypass GDScript lambda capture-by-value sur primitives.
	var captured: Dictionary = {"slow_count": 0, "slow_elapsed": -1, "active_received": false}
	level.level_load_slow.connect(func(elapsed_ms: int) -> void:
		captured["slow_count"] += 1
		captured["slow_elapsed"] = elapsed_ms
	)
	level.level_active.connect(func(_eid: int, _pos: Vector3) -> void:
		captured["active_received"] = true
	)

	# Act — démarrer le chargement
	level.load_etage(42)

	# Simuler 700 ms écoulés (> seuil 600 ms) sans attendre réellement.
	# L'appel est synchrone : décale _load_started_msec avant le prochain _process tick.
	level._simulate_load_elapsed_ms(700)

	# Attendre level_load_slow (émis depuis _physics_process dès le seuil détecté en _process).
	# Timeout 2000 ms largement suffisant.
	await await_signal_on(level, "level_load_slow", [], 2000)

	# Assert slow signal — reçu exactement 1 fois
	assert_int(captured["slow_count"]) \
		.override_failure_message("AC-LVL-7: level_load_slow doit être émis exactement 1 fois") \
		.is_equal(1)

	# Assert elapsed — ≥ 600 ms (simulation garantit ≥ 700 ms)
	assert_bool(captured["slow_elapsed"] >= 600) \
		.override_failure_message(
			"AC-LVL-7: elapsed_ms doit être ≥ 600 (got: %d)" % captured["slow_elapsed"]
		) \
		.is_true()

	# Pump explicite jusqu'à level_active (le chargement continue après le signal slow —
	# invariant AC-LVL-7). _process polls ResourceLoader status, _physics_process commit
	# LOADING → ACTIVE quand THREAD_LOAD_LOADED. En headless, await physics_frame ne pump
	# pas systématiquement. Boucle bornée 200× ≈ 3.3 sec wall-clock max. Common case
	# break early ~5-10 iter ; bump 50→200 pour absorber scheduler jitter CI ubuntu shared
	# runners (pattern cohérent commit 481ac3d).
	for i: int in range(200):
		if level.get_state() == LevelSystemScript.LevelState.ACTIVE:
			break
		level._process(0.0)
		level._physics_process(0.0)
		await get_tree().physics_frame

	# Assert chargement complet
	assert_bool(captured["active_received"]) \
		.override_failure_message("AC-LVL-7: level_active doit être émis après level_load_slow (load non bloqué)") \
		.is_true()
	assert_int(level.get_state()) \
		.override_failure_message("AC-LVL-7: état doit être ACTIVE après le chargement complet") \
		.is_equal(LevelSystemScript.LevelState.ACTIVE)

	# Cleanup
	level.queue_free()


## Edge case AC-LVL-7 : level_load_slow ne doit être émis qu'une seule fois par load.
## Simule 900 ms (> 600 ms) puis attend plusieurs frames pour vérifier l'absence de double émission.
func test_level_load_slow_emitted_only_once_per_load() -> void:
	# Arrange
	var level: LevelSystemScript = _make_level()
	await get_tree().process_frame

	# Container Dictionary pour bypass GDScript lambda capture-by-value sur primitives.
	var captured: Dictionary = {"slow_count": 0}
	level.level_load_slow.connect(func(_elapsed: int) -> void:
		captured["slow_count"] += 1
	)

	# Act
	level.load_etage(42)
	level._simulate_load_elapsed_ms(900)  # > 600 ms

	# Attendre le signal slow
	await await_signal_on(level, "level_load_slow", [], 2000)

	# Attendre quelques frames supplémentaires pour s'assurer qu'aucun second emit ne se produit
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Assert — exactement 1 émission
	assert_int(captured["slow_count"]) \
		.override_failure_message("AC-LVL-7 edge: level_load_slow ne doit être émis qu'une seule fois (got: %d)" % captured["slow_count"]) \
		.is_equal(1)

	# Cleanup direct (pas d'await level_active : non-essentiel pour ce test, pollution
	# inter-test cross-instance ResourceLoader peut bloquer le 2nd load_etage successif).
	level.queue_free()


## Edge case AC-LVL-7 : après unload + reload, le flag _load_slow_emitted est reset.
## Un second load_etage() peut re-émettre level_load_slow si le second load est aussi lent.
func test_level_load_slow_flag_reset_on_reload() -> void:
	# Arrange — charger puis décharger pour revenir à UNLOADED
	var level: LevelSystemScript = _make_level()
	await get_tree().process_frame

	# Premier load — sans slow simulation (charge normalement). Pump explicite.
	# Boucle 200× pour cohérence anti-flake (pattern commit 481ac3d) — common case
	# break early ~5-10 iter, bump absorbe scheduler jitter CI ubuntu shared runners.
	level.load_etage(42)
	for i: int in range(200):
		if level.get_state() == LevelSystemScript.LevelState.ACTIVE:
			break
		level._process(0.0)
		level._physics_process(0.0)
		await get_tree().physics_frame

	# Décharger
	level.unload_current()
	level._physics_process(0.0)  # UNLOADING → UNLOADED

	assert_int(level.get_state()) \
		.override_failure_message("Precondition: état doit être UNLOADED avant le second load") \
		.is_equal(LevelSystemScript.LevelState.UNLOADED)

	# Container Dictionary pour bypass GDScript lambda capture-by-value sur primitives.
	var captured: Dictionary = {"slow_count": 0}
	level.level_load_slow.connect(func(_elapsed: int) -> void:
		captured["slow_count"] += 1
	)

	level.load_etage(42)
	level._simulate_load_elapsed_ms(700)  # Simule slow load sur le second load

	# Assert — le signal doit être ré-émissible après reset du flag.
	# Pump explicite `_process` + `_physics_process(0.0)` + `await physics_frame` :
	# pump sans await peut flake en CI ubuntu (signal emit_deferred Godot peut nécessiter
	# un physics_frame complet pour propager). Pattern miroir helper `_load_and_wait`
	# (commit f1dd477). 200 iterations pour absorber jitter scheduler shared runners.
	for i: int in range(200):
		level._process(0.0)
		level._physics_process(0.0)
		await get_tree().physics_frame
		if captured["slow_count"] >= 1:
			break

	assert_int(captured["slow_count"]) \
		.override_failure_message("AC-LVL-7 edge reload: level_load_slow doit être ré-émis après reload (flag resetté)") \
		.is_equal(1)

	# Cleanup direct (pas d'await level_active : non-essentiel pour ce test, peut hang
	# en headless GdUnit4 cross-test ResourceLoader pollution).
	level.queue_free()
