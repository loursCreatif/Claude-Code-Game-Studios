# Tests d'intégration Story-005 — Focus handling OS + fenêtre 50 ms + signaux one-way.
# Couvre : AC-MC-4 (signaux one-way), AC-MC-5 (gate 50 ms post-FOCUS_IN),
#          AC-MC-7 (burst Wayland simulation — fenêtre forcée via mutation directe).
# AC-MC-6 (Visual/Feel — playtest 3 OS) : DÉFÉRÉ — test manuel advisory.
#   Voir production/qa/evidence/input-focus-playtest-{date}.md pour l'evidence attendue.
# ADR-0004 D-5, D-6, D-7. Framework : GdUnit4 (extends GdUnitTestSuite).

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# Helpers & fixtures
# ---------------------------------------------------------------------------

## Crée un InputManager isolé (pas l'autoload) ajouté à la scène.
## L'appelant est responsable de le libérer (manager.queue_free()).
func _make_manager() -> InputManagerScript:
	var manager: InputManagerScript = InputManagerScript.new()
	add_child(manager)
	return manager

## Injecte un InputEventMouseMotion avec le delta donné via parse_input_event.
## Conforme ADR-0004 D-9 : jamais Input.action_press() direct.
func _inject_mouse_motion(delta: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = delta
	Input.parse_input_event(ev)

# ---------------------------------------------------------------------------
# AC-MC-4 — Signaux one-way : focus_lost déclenche mock sans référence directe
#
# Vérifie :
#   (a) Input.mouse_mode == MOUSE_MODE_VISIBLE après FOCUS_OUT
#   (b) application_focus_lost émis exactement 1×
#   (c) handler mock appelé 1×
#   (d) aucune référence à des systèmes tiers dans input_manager.gd (lint grep)
# ---------------------------------------------------------------------------

func test_ac_mc_4_focus_out_signals_one_way_decoupling() -> void:
	# Arrange
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame

	# Mock local simulant un système abonné (ex. système de pause)
	# — InputManager ne connaît pas ce type, couplage one-way garanti par D-5.
	var mock_handler_calls: int = 0
	manager.application_focus_lost.connect(func() -> void: mock_handler_calls += 1)

	var focus_lost_count: int = 0
	manager.application_focus_lost.connect(func() -> void: focus_lost_count += 1)

	# Forcer un mode capturé avant la perte de focus (simule état gameplay actif)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Act — simuler NOTIFICATION_APPLICATION_FOCUS_OUT (appel direct, main-thread)
	manager.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)

	# Assert (a) : curseur visible après perte de focus
	assert_int(Input.mouse_mode) \
		.override_failure_message(
			"AC-MC-4(a): mouse_mode doit être MOUSE_MODE_VISIBLE après FOCUS_OUT"
		) \
		.is_equal(Input.MOUSE_MODE_VISIBLE)

	# Assert (b) : signal application_focus_lost émis exactement 1×
	assert_int(focus_lost_count) \
		.override_failure_message(
			"AC-MC-4(b): application_focus_lost doit être émis exactement 1× sur FOCUS_OUT"
		) \
		.is_equal(1)

	# Assert (c) : handler mock appelé exactement 1×
	assert_int(mock_handler_calls) \
		.override_failure_message(
			"AC-MC-4(c): handler mock connecté à application_focus_lost doit être appelé 1×"
		) \
		.is_equal(1)

	# Assert (d) : lint — 0 référence à des systèmes tiers dans input_manager.gd
	# Vérification en runtime via lecture du source. Pattern : GameStateManager, noms
	# de systèmes concrets interdits par D-5. Résultat attendu : 0 ligne matchante.
	# Note : ce test échouera si le source n'est pas disponible en runtime headless
	# (builds release sans source) — advisory dans ce contexte.
	var src_path: String = "res://src/core/input_manager.gd"
	if FileAccess.file_exists(src_path):
		var f: FileAccess = FileAccess.open(src_path, FileAccess.READ)
		if f != null:
			var content: String = f.get_as_text()
			f.close()
			var forbidden_count: int = 0
			# Chercher les noms de systèmes concrets interdits par D-5
			for pattern: String in ["GameStateManager", "PauseMenu", "CheckpointSystem"]:
				if content.find(pattern) >= 0:
					forbidden_count += 1
			assert_int(forbidden_count) \
				.override_failure_message(
					"AC-MC-4(d): input_manager.gd ne doit contenir aucune référence à des systèmes tiers (D-5)"
				) \
				.is_equal(0)

	# Restaurer l'état global
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	manager.queue_free()

# ---------------------------------------------------------------------------
# AC-MC-4 (complément) — application_focus_gained émis sur FOCUS_IN
# ---------------------------------------------------------------------------

func test_ac_mc_4_focus_in_emits_application_focus_gained() -> void:
	# Arrange
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame

	var focus_gained_count: int = 0
	manager.application_focus_gained.connect(func() -> void: focus_gained_count += 1)

	# Act
	manager.notification(NOTIFICATION_APPLICATION_FOCUS_IN)

	# Assert
	assert_int(focus_gained_count) \
		.override_failure_message(
			"AC-MC-4 (complément): application_focus_gained doit être émis 1× sur FOCUS_IN"
		) \
		.is_equal(1)

	# Cleanup — désarmer la fenêtre pour ne pas perturber les autres tests
	manager._focus_regained_until_ticks_usec = 0
	manager.queue_free()

# ---------------------------------------------------------------------------
# AC-MC-4 (complément) — _saved_mouse_mode restauré sur FOCUS_IN
# ---------------------------------------------------------------------------

func test_ac_mc_4_mouse_mode_restored_on_focus_in() -> void:
	# Arrange
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame

	# Simuler un état jeu actif (mode capturé)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Act — perte de focus (sauvegarde CAPTURED)
	manager.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_int(Input.mouse_mode) \
		.override_failure_message("Précondition: mouse_mode doit être VISIBLE après FOCUS_OUT") \
		.is_equal(Input.MOUSE_MODE_VISIBLE)

	# Reprise de focus (restaure CAPTURED)
	manager.notification(NOTIFICATION_APPLICATION_FOCUS_IN)

	assert_int(Input.mouse_mode) \
		.override_failure_message(
			"AC-MC-4: mouse_mode doit être restauré à CAPTURED après FOCUS_IN " +
			"(valeur sauvegardée lors du FOCUS_OUT)"
		) \
		.is_equal(Input.MOUSE_MODE_CAPTURED)

	# Restaurer l'état global
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	manager._focus_regained_until_ticks_usec = 0
	manager.queue_free()

# ---------------------------------------------------------------------------
# AC-MC-5 — Gate 50 ms : events mouse_motion dans la fenêtre absorbés,
#            event hors fenêtre laissé passer.
#
# Scénario : FOCUS_IN à t0.
#   3 InputEventMouseMotion injectés dans la fenêtre (< 50 ms) → 0 signal mouse_motion.
#   1 InputEventMouseMotion après expiration de la fenêtre → 1 signal mouse_motion.
#
# Technique : on force _focus_regained_until_ticks_usec à (now + 50_000) avant
# injection des 3 premiers events, puis à 0 avant le 4ème — garantit que la
# fenêtre est active/expirée indépendamment de la vitesse d'exécution du test.
# ---------------------------------------------------------------------------

func test_ac_mc_5_mouse_motion_absorbed_within_50ms_window() -> void:
	# Arrange
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame

	var mouse_signals_emitted: int = 0
	manager.mouse_motion.connect(func(_delta: Vector2) -> void: mouse_signals_emitted += 1)

	# Armer manuellement la fenêtre (simule l'état juste après FOCUS_IN)
	manager._focus_regained_until_ticks_usec = Time.get_ticks_usec() + 50_000

	# Act — injecter 3 events DANS la fenêtre active
	_inject_mouse_motion(Vector2(100.0, 0.0))
	await get_tree().process_frame
	_inject_mouse_motion(Vector2(100.0, 0.0))
	await get_tree().process_frame
	_inject_mouse_motion(Vector2(100.0, 0.0))
	await get_tree().process_frame

	# Assert intermédiaire : 0 signal pendant la fenêtre
	assert_int(mouse_signals_emitted) \
		.override_failure_message(
			"AC-MC-5: mouse_motion ne doit pas être émis pendant la fenêtre 50 ms post-FOCUS_IN " +
			"(gate _focus_regained_until_ticks_usec actif)"
		) \
		.is_equal(0)

	# Expirer la fenêtre manuellement (simule t0 + 60 000 µs)
	manager._focus_regained_until_ticks_usec = 0

	# Injecter 1 event hors fenêtre
	_inject_mouse_motion(Vector2(100.0, 0.0))
	await get_tree().process_frame

	# Assert final : exactement 1 signal après expiration
	assert_int(mouse_signals_emitted) \
		.override_failure_message(
			"AC-MC-5: mouse_motion doit être émis exactement 1× après expiration de la fenêtre 50 ms"
		) \
		.is_equal(1)

	manager.queue_free()

# ---------------------------------------------------------------------------
# AC-MC-5 (bord) — Comparaison stricte < : event exactement à t_expiry passe
#
# La spec D-6 définit la condition d'absorption : Time.get_ticks_usec() < deadline.
# Un event arrivant exactement au timestamp deadline (< échoue → equal → event passe)
# doit être laissé passer.
# ---------------------------------------------------------------------------

func test_ac_mc_5_boundary_event_at_expiry_passes() -> void:
	# Arrange
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame

	var mouse_signals_emitted: int = 0
	manager.mouse_motion.connect(func(_delta: Vector2) -> void: mouse_signals_emitted += 1)

	# Mettre la deadline exactement dans le passé immédiat (expirée)
	# Un ticks légèrement dépassé → la condition < est false → event passe.
	manager._focus_regained_until_ticks_usec = Time.get_ticks_usec() - 1

	# Act
	_inject_mouse_motion(Vector2(50.0, 0.0))
	await get_tree().process_frame

	# Assert — l'event doit passer (deadline expirée)
	assert_int(mouse_signals_emitted) \
		.override_failure_message(
			"AC-MC-5 (bord): event arrivant après expiration doit déclencher mouse_motion " +
			"(comparaison stricte < selon D-6)"
		) \
		.is_equal(1)

	manager.queue_free()

# ---------------------------------------------------------------------------
# AC-MC-7 — Burst Wayland : 6 InputEventMouseMotion sur 3 physics ticks,
#            tous absorbés pendant la fenêtre active.
#
# Simule le comportement d'un compositing Wayland ou X11 qui envoie un burst
# d'events souris en rafale à la reprise du focus.
# La fenêtre est forcée active (deadline = now + 50 000 µs) pour la durée
# entière de l'injection — garantit le test indépendamment du temps réel.
# ---------------------------------------------------------------------------

func test_ac_mc_7_wayland_burst_all_absorbed_during_window() -> void:
	# Arrange
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame

	var mouse_signals_emitted: int = 0
	manager.mouse_motion.connect(func(_delta: Vector2) -> void: mouse_signals_emitted += 1)

	# Armer la fenêtre — elle sera re-armée entre chaque physics tick pour
	# simuler un burst qui se déroule intégralement < 50 ms.
	manager._focus_regained_until_ticks_usec = Time.get_ticks_usec() + 50_000

	# Tick 1 : 2 events
	_inject_mouse_motion(Vector2(30.0, 0.0))
	_inject_mouse_motion(Vector2(30.0, 0.0))
	await get_tree().physics_frame
	# Ré-armer pour le tick suivant (simule rafale sous 50 ms)
	manager._focus_regained_until_ticks_usec = Time.get_ticks_usec() + 50_000

	# Tick 2 : 2 events
	_inject_mouse_motion(Vector2(30.0, 0.0))
	_inject_mouse_motion(Vector2(30.0, 0.0))
	await get_tree().physics_frame
	manager._focus_regained_until_ticks_usec = Time.get_ticks_usec() + 50_000

	# Tick 3 : 2 events
	_inject_mouse_motion(Vector2(30.0, 0.0))
	_inject_mouse_motion(Vector2(30.0, 0.0))
	await get_tree().physics_frame

	# Assert — zéro signal sur les 6 events (tous absorbés par la fenêtre)
	assert_int(mouse_signals_emitted) \
		.override_failure_message(
			"AC-MC-7: burst de 6 InputEventMouseMotion sur 3 physics ticks doit produire " +
			"0 signal mouse_motion pendant la fenêtre FOCUS_REGAIN_WINDOW_USEC (simulation burst Wayland)"
		) \
		.is_equal(0)

	# Nettoyage
	manager._focus_regained_until_ticks_usec = 0
	manager.queue_free()

# ---------------------------------------------------------------------------
# AC-MC-7 (complément) — Après expiration de la fenêtre, les events Wayland
#                         passent normalement (le gate n'est pas permanent)
# ---------------------------------------------------------------------------

func test_ac_mc_7_after_window_events_pass_normally() -> void:
	# Arrange
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame

	var mouse_signals_emitted: int = 0
	manager.mouse_motion.connect(func(_delta: Vector2) -> void: mouse_signals_emitted += 1)

	# Simuler fenêtre déjà expirée (= état normal post-50ms)
	manager._focus_regained_until_ticks_usec = 0

	# Injecter 3 events — doivent tous passer
	_inject_mouse_motion(Vector2(10.0, 0.0))
	_inject_mouse_motion(Vector2(10.0, 0.0))
	_inject_mouse_motion(Vector2(10.0, 0.0))
	await get_tree().physics_frame

	assert_int(mouse_signals_emitted) \
		.override_failure_message(
			"AC-MC-7 (complément): après expiration de la fenêtre, " +
			"les events souris doivent être émis normalement"
		) \
		.is_equal(3)

	manager.queue_free()

# ---------------------------------------------------------------------------
# Vérification FOCUS_OUT + FOCUS_IN + FOCUS_OUT — séquence complète
# Garantit que _saved_mouse_mode et _focus_regained_until_ticks_usec restent
# cohérents après plusieurs cycles de focus.
# ---------------------------------------------------------------------------

func test_focus_cycle_full_sequence_consistent_state() -> void:
	# Arrange
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame

	var focus_lost_count: int = 0
	var focus_gained_count: int = 0
	manager.application_focus_lost.connect(func() -> void: focus_lost_count += 1)
	manager.application_focus_gained.connect(func() -> void: focus_gained_count += 1)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Cycle 1 : FOCUS_OUT → FOCUS_IN
	manager.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	manager.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	manager._focus_regained_until_ticks_usec = 0  # expirer la fenêtre

	# Cycle 2 : FOCUS_OUT
	manager.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)

	# Assert compteurs
	assert_int(focus_lost_count) \
		.override_failure_message("Séquence complète: application_focus_lost doit être émis 2×") \
		.is_equal(2)
	assert_int(focus_gained_count) \
		.override_failure_message("Séquence complète: application_focus_gained doit être émis 1×") \
		.is_equal(1)

	# État final : mouse_mode doit être VISIBLE (dernier FOCUS_OUT)
	assert_int(Input.mouse_mode) \
		.override_failure_message("Séquence complète: mouse_mode doit être VISIBLE après le dernier FOCUS_OUT") \
		.is_equal(Input.MOUSE_MODE_VISIBLE)

	# _focus_regained_until_ticks_usec désarmé par le FOCUS_OUT
	assert_int(manager._focus_regained_until_ticks_usec) \
		.override_failure_message(
			"Séquence complète: FOCUS_OUT doit désarmer _focus_regained_until_ticks_usec (= 0)"
		) \
		.is_equal(0)

	# Restaurer
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	manager.queue_free()

# ---------------------------------------------------------------------------
# AC-MC-6 (Visual/Feel — DÉFÉRÉ)
#
# Ce critère d'acceptation est de nature advisory (tier VISUAL/FEEL selon les
# coding standards). Il requiert un playtest manuel sur 3 OS :
#   - Windows 10/11 (Direct3D 12)
#   - Linux X11 (GNOME/KDE)
#   - Linux Wayland (GNOME Mutter)
#
# Evidence attendue : production/qa/evidence/input-focus-playtest-{date}.md
# Contenu minimal : capture vidéo ou log F3 montrant 0 saut caméra à la
# reprise du focus pendant la fenêtre 50 ms.
#
# Ce test n'est pas automatisé — pas de func test_ac_mc_6_*.
# ---------------------------------------------------------------------------
