# Tests d'intégration Story-002 — VFXSystem combat handlers.
# Couvre AC-VFX-02/06/11/12/13/14/22/27 + EC-VFX-07.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration — scene 3D hermétique avec PhysicsBody pour raycast.
#
# Architecture :
# - _make_vfx() : helper de base (sans CollisionShape3D) — tests no-raycast
# - _make_vfx_with_floor() : helper avec StaticBody3D floor à y=0 — tests raycast
# - Mock time injection : vfx._get_time_msec = func(): return mocked_msec
#
# Pattern miroir story-001 boot_test.gd.

extends GdUnitTestSuite

var _VFXScript: GDScript = preload("res://src/core/vfx_system.gd")
var _MockCombat: GDScript = preload("res://tests/unit/vfx/mock_combat.gd")
var _MockEnemy: GDScript = preload("res://tests/unit/vfx/mock_enemy.gd")
var _MockCamera: GDScript = preload("res://tests/unit/vfx/mock_camera.gd")
var _MockGSM: GDScript = preload("res://tests/unit/vfx/mock_gsm.gd")


# =============================================================================
# Helpers — instanciation hermétique
# =============================================================================

## Instancie VFXSystem + mocks Combat/Enemy/Camera/GSM sans CollisionShape3D.
## Retourne [vfx, mock_combat, mock_enemy, mock_camera, mock_gsm].
## story-006 fix : mock_gsm injecté pour overrider autoload réel (retourne PLAYING=1
## → _is_active = true au boot, évite gating handlers story-002/004).
func _make_vfx() -> Array:
	var mock_combat: Node = _MockCombat.new() as Node
	var mock_enemy: Node = _MockEnemy.new() as Node
	var mock_camera: Node = _MockCamera.new() as Node
	var mock_gsm: Node = _MockGSM.new() as Node

	add_child(mock_combat)
	add_child(mock_enemy)
	add_child(mock_camera)
	add_child(mock_gsm)

	var vfx: Node = _VFXScript.new() as Node
	add_child(vfx)

	vfx.connect_combat_signals(mock_combat)
	vfx.connect_enemy_signals(mock_enemy)
	vfx.connect_camera_signals(mock_camera)
	vfx.connect_gsm_signals(mock_gsm)  # story-006 fix — inject + re-pull → _is_active = true

	return [vfx, mock_combat, mock_enemy, mock_camera, mock_gsm]


## Instancie VFXSystem + mocks + StaticBody3D floor à y=0 (4×0.1×4).
## Le floor permet au raycast DOWN de toucher une surface sous y=0.
## Retourne [vfx, mock_combat, mock_enemy, mock_camera, mock_gsm, floor_body].
func _make_vfx_with_floor() -> Array:
	# Floor : StaticBody3D + BoxShape3D 4×0.1×4 centré à y=-0.05
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.name = &"TestFloor"
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(4.0, 0.1, 4.0)
	col_shape.shape = box
	col_shape.position = Vector3(0.0, -0.05, 0.0)
	floor_body.add_child(col_shape)
	floor_body.position = Vector3(0.0, 0.0, 0.0)
	add_child(floor_body)

	var base: Array = _make_vfx()
	base.append(floor_body)
	return base


func _free_all(nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()


# =============================================================================
# AC-VFX-02 — Decal apparaît sur la surface sol après enemy_killed
# =============================================================================

## GIVEN un enemy_killed reçu avec une surface floor à y=0 et < 32 decals,
## WHEN le raycast DOWN réussit (hit à y=0 environ),
## THEN _decal_pool[0].visible==true + _room_decal_count==1 + position.y proche 0.
func test_enemy_killed_decal_appears_on_floor_surface() -> void:
	# Arrange
	var nodes: Array = _make_vfx_with_floor()
	var vfx: Node = nodes[0]
	var mock_enemy: Node = nodes[2]

	# Laisser la physique s'initialiser
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Act — enemy_killed avec position y=1 (1m au-dessus du sol)
	mock_enemy.emit_enemy_killed(null, Vector3(0.0, 1.0, 0.0))
	await get_tree().physics_frame

	# Assert
	assert_bool(vfx._decal_pool[0].visible) \
		.override_failure_message("AC-VFX-02: _decal_pool[0].visible doit être true après enemy_killed avec surface") \
		.is_true()

	assert_int(vfx._room_decal_count) \
		.override_failure_message("AC-VFX-02: _room_decal_count doit être 1 après 1 kill") \
		.is_equal(1)

	# Decal doit être projeté sur la surface (y proche 0, pas à y=1)
	# Tolerance < 0.1 m (au lieu de < 1.0) — vrai test de projection raycast (qa-tester GAP-1).
	var decal_y: float = vfx._decal_pool[0].global_position.y
	assert_float(decal_y) \
		.override_failure_message("AC-VFX-02: decal.global_position.y doit être proche 0 (projeté sur sol), got %f" % decal_y) \
		.is_less(0.1)

	_free_all(nodes)


# =============================================================================
# AC-VFX-06 — Flash kill WCAG 333 ms guard
# =============================================================================

## GIVEN un premier enemy_killed met à jour _flash_last_msec,
## WHEN un second enemy_killed arrive immédiatement (< 333 ms),
## THEN le guard WCAG empêche le second flash (_flash_last_msec inchangé).
func test_enemy_killed_triggers_flash_kill_with_wcag_guard() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_enemy: Node = nodes[2]

	# Mock time fixe à t=1000 ms
	var mocked_msec: int = 1000
	vfx._get_time_msec = func() -> int: return mocked_msec

	# Act — premier kill : flash autorisé
	mock_enemy.emit_enemy_killed(null, Vector3.ZERO)
	await get_tree().physics_frame

	var flash_after_first: int = vfx._flash_last_msec
	assert_int(flash_after_first) \
		.override_failure_message("AC-VFX-06: _flash_last_msec doit être mis à jour au premier kill (attendu 1000)") \
		.is_equal(1000)

	# Act — second kill immédiat (toujours t=1000, delta=0 < 333 ms) : flash bloqué
	mock_enemy.emit_enemy_killed(null, Vector3.ZERO)
	await get_tree().physics_frame

	# _flash_last_msec ne doit pas avoir changé (guard skip)
	assert_int(vfx._flash_last_msec) \
		.override_failure_message("AC-VFX-06: _flash_last_msec ne doit PAS changer quand guard WCAG bloque le flash") \
		.is_equal(flash_after_first)

	_free_all(nodes)


# =============================================================================
# AC-VFX-11 — 6 particules splash sang, amount correct, round-robin avancé
# =============================================================================

## GIVEN reduce_motion==false, VFXSystem actif,
## WHEN enemy_killed(null, Vector3.ZERO) reçu,
## THEN blood_particle_pool[0].emitting==true, amount==6, lifetime==0.4, _blood_idx==1.
func test_enemy_killed_emits_six_blood_particles_cone_30deg() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_enemy: Node = nodes[2]

	# Assurer reduce_motion false (défaut)
	vfx._reduce_motion = false

	# Act
	mock_enemy.emit_enemy_killed(null, Vector3.ZERO)
	await get_tree().physics_frame

	# Assert — slot 0 doit être actif (premier slot round-robin)
	assert_bool(vfx._blood_particle_pool[0].emitting) \
		.override_failure_message("AC-VFX-11: _blood_particle_pool[0].emitting doit être true après enemy_killed") \
		.is_true()

	assert_int(vfx._blood_particle_pool[0].amount) \
		.override_failure_message("AC-VFX-11: blood_particle_pool[0].amount doit être 6 (BLOOD_SPURT_PARTICLE_COUNT)") \
		.is_equal(6)

	assert_float(vfx._blood_particle_pool[0].lifetime) \
		.override_failure_message("AC-VFX-11: blood_particle_pool[0].lifetime doit être 0.4 (PARTICLE_LIFETIME_MS/1000)") \
		.is_equal_approx(0.4, 0.001)

	assert_int(vfx._blood_idx) \
		.override_failure_message("AC-VFX-11: _blood_idx doit être 1 après 1 kill (round-robin avancé)") \
		.is_equal(1)

	# Partial coverage AC-VFX-11 "flat shader sans PBR" — full assertion hors scope story-002
	# (shader code GLSL = story-007 polish). Ici on assert au minimum que le slot active
	# bien le ShaderMaterial partagé R-VFX-16 (pas un material distinct ou null) — qa-tester GAP-2.
	assert_object(vfx._blood_particle_pool[0].process_material) \
		.override_failure_message("AC-VFX-11: process_material doit être le _blood_shader_material partagé (R-VFX-16)") \
		.is_same(vfx._blood_shader_material)

	_free_all(nodes)


# =============================================================================
# AC-VFX-11 (suite) — round-robin pool wrap après 8 kills successifs
# =============================================================================

## GIVEN VFXSystem actif, _blood_idx == 0,
## WHEN 8 enemy_killed successifs reçus,
## THEN _blood_idx wrap à 0 après le 8ème (ring buffer round-robin complet — qa-tester edge case).
func test_round_robin_wraps_after_pool_size_kills() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_enemy: Node = nodes[2]

	assert_int(vfx._blood_idx) \
		.override_failure_message("Pré-condition : _blood_idx doit être 0 au boot") \
		.is_equal(0)

	# Act — 8 kills (= BLOOD_PARTICLE_POOL_SIZE)
	for i: int in range(8):
		mock_enemy.emit_enemy_killed(null, Vector3(float(i), 100.0, 0.0))
		await get_tree().physics_frame

	# Assert — wrap complet (8 % 8 == 0)
	assert_int(vfx._blood_idx) \
		.override_failure_message("AC-VFX-11 round-robin wrap: _blood_idx doit être 0 après 8 kills (wrap modulo 8), got %d" % vfx._blood_idx) \
		.is_equal(0)

	# Tous les 8 slots doivent avoir emitting=true (chaque slot a été utilisé)
	for i: int in range(vfx._blood_particle_pool.size()):
		assert_bool(vfx._blood_particle_pool[i].emitting) \
			.override_failure_message("AC-VFX-11 round-robin: slot[%d].emitting doit être true après 8 kills cycle complet" % i) \
			.is_true()

	_free_all(nodes)


# =============================================================================
# AC-VFX-12 — reduce_motion réduit le cone à 15°
# =============================================================================

## GIVEN reduce_motion==true,
## WHEN enemy_killed reçu,
## THEN _last_effective_cone_deg == 15.0 (30° × 0.5).
func test_reduce_motion_halves_cone_angle() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_enemy: Node = nodes[2]

	vfx._reduce_motion = true

	# Act
	mock_enemy.emit_enemy_killed(null, Vector3.ZERO)
	await get_tree().physics_frame

	# Assert
	assert_float(vfx._last_effective_cone_deg) \
		.override_failure_message("AC-VFX-12: _last_effective_cone_deg doit être 15.0 quand reduce_motion==true (30°×0.5)") \
		.is_equal_approx(15.0, 0.01)

	_free_all(nodes)


# =============================================================================
# AC-VFX-13 — swing_started active le trail visible avec aim_forward
# =============================================================================

## GIVEN VFXSystem actif, trail invisible,
## WHEN swing_started(Vector3.FORWARD) reçu,
## THEN _trail_mesh.visible==true + _trail_active==true + _swing_aim_forward==Vector3.FORWARD.
func test_swing_started_activates_trail_visible_with_aim() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_combat: Node = nodes[1]

	# Vérifier état initial
	assert_bool(vfx._trail_mesh.visible) \
		.override_failure_message("AC-VFX-13: _trail_mesh.visible doit être false avant swing_started") \
		.is_false()

	# Act
	mock_combat.emit_swing_started(Vector3.FORWARD)
	await get_tree().physics_frame

	# Assert
	assert_bool(vfx._trail_mesh.visible) \
		.override_failure_message("AC-VFX-13: _trail_mesh.visible doit être true après swing_started") \
		.is_true()

	assert_bool(vfx._trail_active) \
		.override_failure_message("AC-VFX-13: _trail_active doit être true après swing_started") \
		.is_true()

	assert_vector(vfx._swing_aim_forward) \
		.override_failure_message("AC-VFX-13: _swing_aim_forward doit être Vector3.FORWARD après swing_started(FORWARD)") \
		.is_equal_approx(Vector3.FORWARD, Vector3(0.001, 0.001, 0.001))

	_free_all(nodes)


# =============================================================================
# AC-VFX-14 — swing_ended déclenche fade-out trail en 100 ms
# =============================================================================

## GIVEN trail actif post swing_started,
## WHEN swing_ended() reçu puis 110 ms simulés via mock time,
## THEN _trail_mesh.visible==false + _trail_active==false après tick _physics_process.
func test_swing_ended_trail_fades_out_in_100ms() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_combat: Node = nodes[1]

	# Mock time — démarrer à t=500 ms
	var mocked_msec: int = 500
	vfx._get_time_msec = func() -> int: return mocked_msec

	# Activer le trail
	mock_combat.emit_swing_started(Vector3.FORWARD)
	await get_tree().physics_frame

	assert_bool(vfx._trail_active) \
		.override_failure_message("AC-VFX-14: pré-condition _trail_active doit être true après swing_started") \
		.is_true()

	# Act — déclencher swing_ended (enregistre _trail_fade_start_msec = 500)
	mock_combat.emit_swing_ended()
	await get_tree().physics_frame

	assert_int(vfx._trail_fade_start_msec) \
		.override_failure_message("AC-VFX-14: _trail_fade_start_msec doit être 500 juste après swing_ended") \
		.is_equal(500)

	# Avancer le temps mock à t=610 ms (110 ms après swing_ended → > KATANA_TRAIL_FADE_MS=100)
	mocked_msec = 610
	vfx._get_time_msec = func() -> int: return mocked_msec

	# Simuler un tick _physics_process
	vfx._physics_process(0.016)

	# Assert — trail doit être éteint
	assert_bool(vfx._trail_mesh.visible) \
		.override_failure_message("AC-VFX-14: _trail_mesh.visible doit être false après 110 ms (> KATANA_TRAIL_FADE_MS=100)") \
		.is_false()

	assert_bool(vfx._trail_active) \
		.override_failure_message("AC-VFX-14: _trail_active doit être false après fade-out complet") \
		.is_false()

	assert_int(vfx._trail_fade_start_msec) \
		.override_failure_message("AC-VFX-14: _trail_fade_start_msec doit être remis à 0 après fade complet") \
		.is_equal(0)

	_free_all(nodes)


# =============================================================================
# AC-VFX-22 — respawned resets blood pool, trail, decals
# =============================================================================

## GIVEN 3 slots blood GPUParticles3D actifs + trail visible + decals visibles,
## WHEN respawned(Vector3.ZERO) reçu,
## THEN tous 8 slots emitting==false + trail invisible + _room_decal_count==0 + decals hidden + _decal_write_head==0.
func test_respawned_resets_blood_pool_and_trail() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_camera: Node = nodes[3]

	# Pré-activer 3 slots sang manuellement
	for i: int in range(3):
		vfx._blood_particle_pool[i].emitting = true

	# Pré-activer le trail
	vfx._trail_active = true
	vfx._trail_mesh.visible = true
	vfx._trail_fade_start_msec = 1234

	# Pré-activer quelques decals
	vfx._decal_pool[0].visible = true
	vfx._decal_pool[1].visible = true
	vfx._room_decal_count = 2
	vfx._decal_write_head = 2

	# Act
	mock_camera.emit_respawned(Vector3.ZERO)
	await get_tree().physics_frame

	# Assert — tous slots sang éteints
	for i: int in range(vfx._blood_particle_pool.size()):
		assert_bool(vfx._blood_particle_pool[i].emitting) \
			.override_failure_message("AC-VFX-22: blood_particle_pool[%d].emitting doit être false après respawn" % i) \
			.is_false()

	# Assert — trail éteint
	assert_bool(vfx._trail_mesh.visible) \
		.override_failure_message("AC-VFX-22: _trail_mesh.visible doit être false après respawn") \
		.is_false()

	assert_bool(vfx._trail_active) \
		.override_failure_message("AC-VFX-22: _trail_active doit être false après respawn") \
		.is_false()

	assert_int(vfx._trail_fade_start_msec) \
		.override_failure_message("AC-VFX-22: _trail_fade_start_msec doit être 0 après respawn") \
		.is_equal(0)

	# Assert — decals cachés + compteurs reset
	assert_int(vfx._room_decal_count) \
		.override_failure_message("AC-VFX-22: _room_decal_count doit être 0 après respawn") \
		.is_equal(0)

	assert_int(vfx._decal_write_head) \
		.override_failure_message("AC-VFX-22: _decal_write_head doit être 0 après respawn") \
		.is_equal(0)

	for i: int in range(vfx._decal_pool.size()):
		assert_bool(vfx._decal_pool[i].visible) \
			.override_failure_message("AC-VFX-22: _decal_pool[%d].visible doit être false après respawn" % i) \
			.is_false()

	_free_all(nodes)


# =============================================================================
# AC-VFX-27 — Chrome Zen palette constants correctes
# =============================================================================

## GIVEN VFXSystem instancié,
## WHEN lecture des constantes couleur,
## THEN BLOOD_COLOR == #C8232C (r≈0.784 g≈0.137 b≈0.173) + TRAIL_COLOR == #E8E8E0
##      + _decal_pool[0].modulate.a == 0.7.
func test_chrome_zen_palette_constants_correct() -> void:
	# Arrange + Act
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]

	# Assert BLOOD_COLOR (#C8232C = 200/255, 35/255, 44/255)
	assert_float(vfx.BLOOD_COLOR.r) \
		.override_failure_message("AC-VFX-27: BLOOD_COLOR.r doit être ≈0.784 (200/255)") \
		.is_equal_approx(200.0 / 255.0, 0.002)

	assert_float(vfx.BLOOD_COLOR.g) \
		.override_failure_message("AC-VFX-27: BLOOD_COLOR.g doit être ≈0.137 (35/255)") \
		.is_equal_approx(35.0 / 255.0, 0.002)

	assert_float(vfx.BLOOD_COLOR.b) \
		.override_failure_message("AC-VFX-27: BLOOD_COLOR.b doit être ≈0.173 (44/255)") \
		.is_equal_approx(44.0 / 255.0, 0.002)

	# Assert TRAIL_COLOR (#E8E8E0 = 232/255, 232/255, 224/255)
	assert_float(vfx.TRAIL_COLOR.r) \
		.override_failure_message("AC-VFX-27: TRAIL_COLOR.r doit être ≈0.910 (232/255)") \
		.is_equal_approx(232.0 / 255.0, 0.002)

	assert_float(vfx.TRAIL_COLOR.g) \
		.override_failure_message("AC-VFX-27: TRAIL_COLOR.g doit être ≈0.910 (232/255)") \
		.is_equal_approx(232.0 / 255.0, 0.002)

	assert_float(vfx.TRAIL_COLOR.b) \
		.override_failure_message("AC-VFX-27: TRAIL_COLOR.b doit être ≈0.878 (224/255)") \
		.is_equal_approx(224.0 / 255.0, 0.002)

	# Assert decal modulate alpha == 0.7
	var decal_alpha: float = vfx._decal_pool[0].modulate.a
	assert_float(decal_alpha) \
		.override_failure_message("AC-VFX-27: _decal_pool[0].modulate.a doit être 0.7 (défini dans _setup_vfx_pool)") \
		.is_equal_approx(0.7, 0.001)

	_free_all(nodes)


# =============================================================================
# EC-VFX-07 — Raycast no surface : skip silencieux, pas de decal
# =============================================================================

## GIVEN aucune CollisionShape3D dans la scene,
## WHEN enemy_killed(null, Vector3(0, 100, 0)) reçu (en l'air, no surface),
## THEN _room_decal_count==0 + _decal_pool[0].visible==false + particules actives.
## Note qa-tester GAP-4 : `push_warning` est un side-effect debug — le test asserte
## les effets observables (decal absent + particules continuent). GdUnit4 v5 n'a pas
## `assert_warning` natif ; pattern capture via `_last_warning_message` polluerait prod
## code. Acceptable scope story-002 — story-007 lints CI valideront le path warning.
func test_decal_raycast_no_surface_skips_silently() -> void:
	# Arrange — PAS de floor (utiliser _make_vfx sans CollisionShape3D)
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_enemy: Node = nodes[2]

	await get_tree().physics_frame
	await get_tree().physics_frame

	# Act — position très haute, aucune surface accessible dans 3 m
	mock_enemy.emit_enemy_killed(null, Vector3(0.0, 100.0, 0.0))
	await get_tree().physics_frame

	# Assert — pas de decal spawné
	assert_int(vfx._room_decal_count) \
		.override_failure_message("EC-VFX-07: _room_decal_count doit être 0 (no surface — skip silencieux)") \
		.is_equal(0)

	assert_bool(vfx._decal_pool[0].visible) \
		.override_failure_message("EC-VFX-07: _decal_pool[0].visible doit être false (no surface — skip silencieux)") \
		.is_false()

	# Assert — particules sang actives malgré l'absence de decal
	assert_bool(vfx._blood_particle_pool[0].emitting) \
		.override_failure_message("EC-VFX-07: _blood_particle_pool[0].emitting doit être true (particles indépendantes du decal)") \
		.is_true()

	_free_all(nodes)
