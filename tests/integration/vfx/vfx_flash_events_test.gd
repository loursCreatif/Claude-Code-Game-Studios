# Tests d'intégration Story-004 — VFXSystem flash events kill/respawn wall-clock.
# Couvre AC-VFX-06/07/08/09/25/26 + R-VFX-15 (flash respawn 50 ms pop binaire) + EC-VFX-02.
# Note : AC-VFX-15 (GSM gating state_changed(MENU)) déféré story-006 (body GSM gating).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration — injection wall-clock Callable mock pour isolation time_scale.
#
# Architecture :
# - _make_vfx() : helper hermétique, mocks Combat/Enemy/Camera injectés.
# - Mock time injection : vfx._get_time_msec = func(): return mocked_msec
# - RE-ASSIGN Callable requis à chaque changement (closure capture par valeur GDScript).
# - Cleanup Engine.time_scale = 1.0 systématique dans tests slow-mo (AC-VFX-25/26).
# - `vfx._flash_last_msec = -333` : convention test pour bypass guard WCAG au premier appel
#   (=  0 - FLASH_MIN_INTERVAL_MS → garantit `now(0) - (-333) = 333 ≥ FLASH_MIN_INTERVAL_MS` PASS guard).

extends GdUnitTestSuite

var _VFXScript: GDScript = preload("res://src/core/vfx_system.gd")
var _MockCombat: GDScript = preload("res://tests/unit/vfx/mock_combat.gd")
var _MockEnemy: GDScript = preload("res://tests/unit/vfx/mock_enemy.gd")
var _MockCamera: GDScript = preload("res://tests/unit/vfx/mock_camera.gd")


# =============================================================================
# Helpers — instanciation hermétique
# =============================================================================

## Instancie VFXSystem + mocks Combat/Enemy/Camera sans CollisionShape3D.
## Retourne [vfx, mock_combat, mock_enemy, mock_camera].
func _make_vfx() -> Array:
	var mock_combat: Node = _MockCombat.new() as Node
	var mock_enemy: Node = _MockEnemy.new() as Node
	var mock_camera: Node = _MockCamera.new() as Node

	add_child(mock_combat)
	add_child(mock_enemy)
	add_child(mock_camera)

	var vfx: Node = _VFXScript.new() as Node
	add_child(vfx)

	vfx.connect_combat_signals(mock_combat)
	vfx.connect_enemy_signals(mock_enemy)
	vfx.connect_camera_signals(mock_camera)

	return [vfx, mock_combat, mock_enemy, mock_camera]


func _free_all(nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()


# =============================================================================
# AC-VFX-06 — Flash kill blanc 80 ms quand reduce_flash OFF
# =============================================================================

## GIVEN reduce_flash==false, mock time t=0,
## WHEN _trigger_flash_kill() appelé,
## THEN overlay visible + Color blanc alpha 1.0 ;
## WHEN tick _physics_process à t=80,
## THEN _flash_kill_active==false + overlay hidden.
func test_flash_kill_blanc_80ms_reduce_flash_off() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]

	vfx._reduce_flash = false

	var mocked_msec: int = 0
	vfx._get_time_msec = func() -> int: return mocked_msec
	# _flash_last_msec est 0, now=0, delta=0 < 333 → guard activerait le skip.
	# Forcer _flash_last_msec à -333 pour que le guard passe au premier appel.
	vfx._flash_last_msec = -333

	# Act — trigger à t=0
	vfx._trigger_flash_kill()

	# Assert — overlay actif, couleur blanc pur alpha 1.0
	assert_bool(vfx._flash_overlay_rect.visible) \
		.override_failure_message("AC-VFX-06: _flash_overlay_rect.visible doit être true juste après _trigger_flash_kill()") \
		.is_true()

	assert_bool(vfx._flash_kill_active) \
		.override_failure_message("AC-VFX-06: _flash_kill_active doit être true après trigger") \
		.is_true()

	assert_float(vfx._flash_overlay_rect.color.r) \
		.override_failure_message("AC-VFX-06: color.r doit être 1.0 (blanc pur, reduce_flash==false)") \
		.is_equal_approx(1.0, 0.001)

	assert_float(vfx._flash_overlay_rect.color.a) \
		.override_failure_message("AC-VFX-06: color.a doit être 1.0 (t=0 → alpha max)") \
		.is_equal_approx(1.0, 0.001)

	# Avancer à t=40 ms (mi-fade) — assert alpha ≈ 0.5 (linéaire 1.0 - 40/80)
	# Couvre spec QA Test Cases AC-VFX-06 ligne 187 "à t=40 → alpha ≈ 0.5".
	mocked_msec = 40
	vfx._get_time_msec = func() -> int: return mocked_msec
	vfx._physics_process(0.016)
	assert_float(vfx._flash_overlay_rect.color.a) \
		.override_failure_message("AC-VFX-06: color.a doit être ≈0.5 à t=40 ms (fade-out linéaire 1.0→0.0 sur 80 ms)") \
		.is_equal_approx(0.5, 0.01)

	# Avancer le temps mock à t=80 ms (= FLASH_KILL_DURATION_MS)
	mocked_msec = 80
	vfx._get_time_msec = func() -> int: return mocked_msec

	# Tick _physics_process
	vfx._physics_process(0.016)

	# Assert — flash terminé
	assert_bool(vfx._flash_kill_active) \
		.override_failure_message("AC-VFX-06: _flash_kill_active doit être false après 80 ms écoulés") \
		.is_false()

	assert_bool(vfx._flash_overlay_rect.visible) \
		.override_failure_message("AC-VFX-06: _flash_overlay_rect.visible doit être false quand flash terminé (pas de respawn actif)") \
		.is_false()

	_free_all(nodes)


# =============================================================================
# AC-VFX-07 — Flash kill gris #A0A0A0 quand reduce_flash ON
# =============================================================================

## GIVEN reduce_flash==true, mock time t=0,
## WHEN _trigger_flash_kill() appelé,
## THEN overlay visible + Color gris (r≈0.625) + alpha 1.0 ; jamais Color blanc pur.
func test_flash_kill_grey_80ms_reduce_flash_on() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]

	vfx._reduce_flash = true
	vfx._flash_last_msec = -333

	var mocked_msec: int = 0
	vfx._get_time_msec = func() -> int: return mocked_msec

	# Act
	vfx._trigger_flash_kill()

	# Assert — couleur gris #A0A0A0 = 0.625 RGB
	assert_bool(vfx._flash_overlay_rect.visible) \
		.override_failure_message("AC-VFX-07: _flash_overlay_rect.visible doit être true (reduce_flash → gris substitute, pas suppression)") \
		.is_true()

	assert_bool(vfx._flash_kill_active) \
		.override_failure_message("AC-VFX-07: _flash_kill_active doit être true") \
		.is_true()

	# Gris #A0A0A0 = 160/255 ≈ 0.625 — jamais 1.0 blanc pur
	var color_r: float = vfx._flash_overlay_rect.color.r
	assert_float(color_r) \
		.override_failure_message("AC-VFX-07: color.r doit être ≈0.625 (REDUCE_FLASH_BRIGHTNESS, #A0A0A0), got %f" % color_r) \
		.is_equal_approx(0.625, 0.001)

	assert_float(vfx._flash_overlay_rect.color.g) \
		.override_failure_message("AC-VFX-07: color.g doit être ≈0.625 (gris uniforme)") \
		.is_equal_approx(0.625, 0.001)

	assert_float(vfx._flash_overlay_rect.color.b) \
		.override_failure_message("AC-VFX-07: color.b doit être ≈0.625 (gris uniforme)") \
		.is_equal_approx(0.625, 0.001)

	assert_float(vfx._flash_overlay_rect.color.a) \
		.override_failure_message("AC-VFX-07: color.a doit être 1.0 (t=0 → alpha max)") \
		.is_equal_approx(1.0, 0.001)

	# Confirmer _flash_kill_use_grey mémorisé
	assert_bool(vfx._flash_kill_use_grey) \
		.override_failure_message("AC-VFX-07: _flash_kill_use_grey doit être true quand reduce_flash==true au moment du trigger") \
		.is_true()

	_free_all(nodes)


# =============================================================================
# AC-VFX-08 — WCAG guard bloque burst dans les 333 ms
# =============================================================================

## GIVEN _flash_last_msec=100, mock time=200 (delta 100 < 333 ms),
## WHEN _trigger_flash_kill() appelé,
## THEN _flash_kill_active==false (skip silencieux — guard WCAG actif).
func test_wcag_guard_blocks_burst_within_333ms() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]

	vfx._flash_last_msec = 100

	var mocked_msec: int = 200  # delta = 100 < FLASH_MIN_INTERVAL_MS=333
	vfx._get_time_msec = func() -> int: return mocked_msec

	# Assert pré-condition
	assert_bool(vfx._flash_kill_active) \
		.override_failure_message("Pré-condition : _flash_kill_active doit être false avant trigger") \
		.is_false()

	# Act
	vfx._trigger_flash_kill()

	# Assert — flash bloqué
	assert_bool(vfx._flash_kill_active) \
		.override_failure_message("AC-VFX-08: _flash_kill_active doit rester false quand guard WCAG bloque (delta 100 < 333 ms)") \
		.is_false()

	# _flash_last_msec ne doit pas avoir changé
	assert_int(vfx._flash_last_msec) \
		.override_failure_message("AC-VFX-08: _flash_last_msec ne doit pas changer quand guard bloque") \
		.is_equal(100)

	assert_bool(vfx._flash_overlay_rect.visible) \
		.override_failure_message("AC-VFX-08: overlay doit rester hidden quand guard bloque") \
		.is_false()

	_free_all(nodes)


# =============================================================================
# AC-VFX-08 (burst) — 10 events sur 1 s → max 3 flashs autorisés
# =============================================================================

## GIVEN 10 appels _trigger_flash_kill() espacés de 100 ms (0, 100, 200, ..., 900 ms),
## WHEN on compte combien de fois _flash_last_msec est mis à jour (flash réel),
## THEN ≤ 3 flashs autorisés (t=0, t=333, t=666 — guard 333 ms → t=100..332 blocked).
func test_burst_10_events_1sec_max_3_flashs() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]

	var flash_count: int = 0
	var last_flash_msec: int = -333  # Forcer premier flash autorisé

	# Act — 10 triggers espacés de 100 ms
	for i: int in range(10):
		var current_msec: int = i * 100
		vfx._flash_last_msec = last_flash_msec
		vfx._get_time_msec = func() -> int: return current_msec
		vfx._trigger_flash_kill()
		# Si flash autorisé, _flash_last_msec est mis à jour
		if vfx._flash_last_msec == current_msec:
			flash_count += 1
			last_flash_msec = current_msec
		# Pas de tick _physics_process entre triggers (teste uniquement le guard)

	# Assert — max 3 flashs sur 10 events espacés de 100 ms (guard 333 ms WCAG 2.3.1).
	# Avec pas 100 ms sur t=0..900 :
	#   t=0   → OK (premier flash, _flash_last_msec = -333 forcé)
	#   t=100 → blocked (100 - 0 = 100 < 333)
	#   t=200 → blocked (200 - 0 = 200 < 333)
	#   t=300 → blocked (300 - 0 = 300 < 333)
	#   t=400 → OK    (400 - 0 = 400 ≥ 333)
	#   t=500 → blocked (500 - 400 = 100 < 333)
	#   t=600 → blocked (600 - 400 = 200 < 333)
	#   t=700 → blocked (700 - 400 = 300 < 333)
	#   t=800 → OK    (800 - 400 = 400 ≥ 333)
	#   t=900 → blocked (900 - 800 = 100 < 333)
	# → 3 flashs autorisés (t=0, t=400, t=800)
	assert_bool(flash_count <= 3) \
		.override_failure_message("AC-VFX-08 burst: flash_count=%d doit être ≤ 3 sur 10 events / 1 s (guard 333 ms)" % flash_count) \
		.is_true()

	assert_bool(flash_count >= 1) \
		.override_failure_message("AC-VFX-08 burst: au moins 1 flash doit passer (t=0 autorisé)") \
		.is_true()

	_free_all(nodes)


# =============================================================================
# AC-VFX-09 — Respawn : zéro flash si reduce_flash ON
# =============================================================================

## GIVEN reduce_flash==true,
## WHEN _trigger_flash_respawn() appelé,
## THEN _flash_respawn_active==false + overlay hidden (AC-VFX-09 — zéro flash respawn).
func test_respawn_no_flash_if_reduce_flash_on() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]

	vfx._reduce_flash = true

	# Act
	vfx._trigger_flash_respawn()

	# Assert
	assert_bool(vfx._flash_respawn_active) \
		.override_failure_message("AC-VFX-09: _flash_respawn_active doit être false quand reduce_flash==true") \
		.is_false()

	assert_bool(vfx._flash_overlay_rect.visible) \
		.override_failure_message("AC-VFX-09: overlay doit rester hidden quand reduce_flash==true (zéro flash respawn)") \
		.is_false()

	_free_all(nodes)


# =============================================================================
# AC-VFX-25 — Flash kill 80 ms wall-clock invariant sous slow-mo
# =============================================================================

## GIVEN Engine.time_scale=0.3 + mock wall-clock t=0 puis t=80 (indépendant de time_scale),
## WHEN _trigger_flash_kill() puis tick _physics_process à wall-t=80,
## THEN _flash_kill_active==false à t=80 ms wall-clock (PAS t=80/0.3≈267 ms scaled).
## CLEANUP Engine.time_scale=1.0 systématique.
func test_flash_kill_80ms_invariant_under_slow_mo() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]

	Engine.time_scale = 0.3
	vfx._reduce_flash = false
	vfx._flash_last_msec = -333

	var mocked_msec: int = 0
	vfx._get_time_msec = func() -> int: return mocked_msec

	# Act — trigger à wall-t=0
	vfx._trigger_flash_kill()

	assert_bool(vfx._flash_kill_active) \
		.override_failure_message("AC-VFX-25: _flash_kill_active doit être true après trigger (pré-condition slow-mo test)") \
		.is_true()

	# Avancer wall-clock à t=79 ms — flash doit encore être actif
	mocked_msec = 79
	vfx._get_time_msec = func() -> int: return mocked_msec
	vfx._physics_process(0.016)

	assert_bool(vfx._flash_kill_active) \
		.override_failure_message("AC-VFX-25: _flash_kill_active doit encore être true à t=79 ms wall-clock (< 80 ms)") \
		.is_true()

	# Avancer wall-clock à t=80 ms = FLASH_KILL_DURATION_MS — flash doit se terminer
	mocked_msec = 80
	vfx._get_time_msec = func() -> int: return mocked_msec
	vfx._physics_process(0.016)

	assert_bool(vfx._flash_kill_active) \
		.override_failure_message("AC-VFX-25: _flash_kill_active doit être false à t=80 ms wall-clock (indépendant de time_scale=0.3)") \
		.is_false()

	# Cleanup — impératif pour ne pas polluer les autres tests
	Engine.time_scale = 1.0

	_free_all(nodes)


# =============================================================================
# AC-VFX-26 — Flash kill gris 80 ms sous slow-mo + reduce_flash
# =============================================================================

## GIVEN Engine.time_scale=0.3 + reduce_flash==true,
## WHEN _trigger_flash_kill() puis tick à wall-t=80,
## THEN couleur gris 0.625 RGB au démarrage + _flash_kill_active==false à t=80.
## CLEANUP Engine.time_scale=1.0.
func test_flash_kill_grey_under_slow_mo_reduce_flash() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]

	Engine.time_scale = 0.3
	vfx._reduce_flash = true
	vfx._flash_last_msec = -333

	var mocked_msec: int = 0
	vfx._get_time_msec = func() -> int: return mocked_msec

	# Act — trigger
	vfx._trigger_flash_kill()

	# Assert couleur gris au démarrage
	assert_float(vfx._flash_overlay_rect.color.r) \
		.override_failure_message("AC-VFX-26: color.r doit être 0.625 (gris reduce_flash) sous slow-mo") \
		.is_equal_approx(0.625, 0.001)

	assert_float(vfx._flash_overlay_rect.color.a) \
		.override_failure_message("AC-VFX-26: color.a doit être 1.0 (t=0, alpha max)") \
		.is_equal_approx(1.0, 0.001)

	# Avancer wall-clock à t=80 ms — flash doit se terminer
	mocked_msec = 80
	vfx._get_time_msec = func() -> int: return mocked_msec
	vfx._physics_process(0.016)

	assert_bool(vfx._flash_kill_active) \
		.override_failure_message("AC-VFX-26: _flash_kill_active doit être false à wall-t=80 ms (time_scale=0.3 ne doit pas étirer la durée)") \
		.is_false()

	# Cleanup
	Engine.time_scale = 1.0

	_free_all(nodes)


# =============================================================================
# R-VFX-15 — Flash respawn 50 ms pop binaire
# =============================================================================

## GIVEN reduce_flash==false, mock time t=0,
## WHEN _trigger_flash_respawn() appelé,
## THEN _flash_respawn_active==true + visible==true + color blanc pur ;
## WHEN tick _physics_process à t=50,
## THEN _flash_respawn_active==false + overlay hidden.
func test_flash_respawn_50ms_pop_binaire() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]

	vfx._reduce_flash = false

	var mocked_msec: int = 0
	vfx._get_time_msec = func() -> int: return mocked_msec

	# Act — trigger respawn
	vfx._trigger_flash_respawn()

	# Assert — flash respawn actif + blanc pur
	assert_bool(vfx._flash_respawn_active) \
		.override_failure_message("R-VFX-15: _flash_respawn_active doit être true après _trigger_flash_respawn()") \
		.is_true()

	assert_bool(vfx._flash_overlay_rect.visible) \
		.override_failure_message("R-VFX-15: overlay doit être visible après _trigger_flash_respawn()") \
		.is_true()

	assert_float(vfx._flash_overlay_rect.color.r) \
		.override_failure_message("R-VFX-15: color.r doit être 1.0 (blanc pur — pas de gris substitute pour respawn)") \
		.is_equal_approx(1.0, 0.001)

	assert_float(vfx._flash_overlay_rect.color.a) \
		.override_failure_message("R-VFX-15: color.a doit être 1.0 (pop binaire)") \
		.is_equal_approx(1.0, 0.001)

	# Avancer wall-clock à t=50 ms = FLASH_RESPAWN_DURATION_MS — flash doit se terminer
	mocked_msec = 50
	vfx._get_time_msec = func() -> int: return mocked_msec

	vfx._physics_process(0.016)

	# Assert — flash terminé
	assert_bool(vfx._flash_respawn_active) \
		.override_failure_message("R-VFX-15: _flash_respawn_active doit être false après 50 ms écoulés") \
		.is_false()

	assert_bool(vfx._flash_overlay_rect.visible) \
		.override_failure_message("R-VFX-15: overlay doit être hidden quand flash respawn terminé (pas de kill flash actif)") \
		.is_false()

	_free_all(nodes)
