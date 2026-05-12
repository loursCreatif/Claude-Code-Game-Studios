# Tests unitaires Story-006 — VFXSystem GSM visibility gating.
# Couvre AC-VFX-15 (trail freeze MENU) + AC-VFX-16 (pool freeze PAUSED) +
#        AC-VFX-17 (restore PLAYING) + AC-NEW-08 (boot MENU state) + EC-VFX-05 (full trail sequence).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Unit — injection mock GSM + wall-clock mock.
#
# Architecture :
# - _make_vfx() : helper hermétique retourne [vfx, mock_combat, mock_enemy, mock_camera, mock_accessibility, mock_gsm].
# - mock_gsm expose state_changed(new_state: int) + get_current_state() -> int + set_state(s: int) + emit_state_changed(s: int).
# - await get_tree().process_frame × 2 pour laisser CONNECT_DEFERRED dispatcher.

extends GdUnitTestSuite

var _VFXScript: GDScript = preload("res://src/core/vfx_system.gd")
var _MockCombat: GDScript = preload("res://tests/unit/vfx/mock_combat.gd")
var _MockEnemy: GDScript = preload("res://tests/unit/vfx/mock_enemy.gd")
var _MockCamera: GDScript = preload("res://tests/unit/vfx/mock_camera.gd")
var _MockGSM: GDScript = preload("res://tests/unit/vfx/mock_gsm.gd")
var _MockAccessibility: GDScript = preload("res://tests/unit/vfx/mock_accessibility.gd")


# =============================================================================
# Helpers — instanciation hermétique
# =============================================================================

## Instancie VFXSystem + mocks Combat/Enemy/Camera/Accessibility/GSM.
## Retourne [vfx, mock_combat, mock_enemy, mock_camera, mock_accessibility, mock_gsm].
## mock_gsm initial state = PLAYING (1) → _is_active = true après connect_gsm_signals.
func _make_vfx() -> Array:
	var mock_combat: Node = _MockCombat.new() as Node
	var mock_enemy: Node = _MockEnemy.new() as Node
	var mock_camera: Node = _MockCamera.new() as Node
	var mock_accessibility: Node = _MockAccessibility.new() as Node
	var mock_gsm: Node = _MockGSM.new() as Node

	add_child(mock_combat)
	add_child(mock_enemy)
	add_child(mock_camera)
	add_child(mock_accessibility)
	add_child(mock_gsm)

	var vfx: Node = _VFXScript.new() as Node
	add_child(vfx)

	vfx.connect_combat_signals(mock_combat)
	vfx.connect_enemy_signals(mock_enemy)
	vfx.connect_camera_signals(mock_camera)
	vfx.connect_accessibility_signals(mock_accessibility)
	vfx.connect_gsm_signals(mock_gsm)  # story-006 — inject + pull initial (PLAYING → _is_active=true)

	return [vfx, mock_combat, mock_enemy, mock_camera, mock_accessibility, mock_gsm]


func _free_all(nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()


# =============================================================================
# AC-VFX-15 — MENU pendant swing : trail freeze + swing_ended ignoré
# =============================================================================

## GIVEN swing actif (_trail_active==true, _trail_mesh.visible==true),
## WHEN state_changed(MENU=0) émis,
## THEN trail cleared (_trail_active==false, visible==false)
##   ET swing_ended ultérieur ignoré (_trail_fade_start_msec reste 0).
func test_menu_during_swing_disables_trail_and_ignores_swing_ended() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_combat: Node = nodes[1]
	var mock_gsm: Node = nodes[5]

	# Désactiver le clock pour éviter un fade-out pendant le test
	vfx._get_time_msec = func() -> int: return 0

	# Act — swing_started (trail actif)
	mock_combat.swing_started.emit(Vector3.FORWARD)
	await get_tree().process_frame
	await get_tree().process_frame

	# Assert trail actif
	assert_bool(vfx._trail_active) \
		.override_failure_message("AC-VFX-15: _trail_active doit être true après swing_started") \
		.is_true()
	assert_bool(vfx._trail_mesh.visible) \
		.override_failure_message("AC-VFX-15: trail_mesh.visible doit être true après swing_started") \
		.is_true()

	# Act — state_changed(MENU=0) → freeze
	mock_gsm.state_changed.emit(0)
	await get_tree().process_frame
	await get_tree().process_frame

	# Assert freeze
	assert_bool(vfx._is_active) \
		.override_failure_message("AC-VFX-15: _is_active doit être false après state_changed(MENU)") \
		.is_false()
	assert_bool(vfx._trail_active) \
		.override_failure_message("AC-VFX-15: _trail_active doit être false après freeze MENU") \
		.is_false()
	assert_bool(vfx._trail_mesh.visible) \
		.override_failure_message("AC-VFX-15: trail_mesh.visible doit être false après freeze MENU") \
		.is_false()

	# Act — swing_ended ignoré (post-MENU, _is_active==false)
	mock_combat.swing_ended.emit()
	await get_tree().process_frame
	await get_tree().process_frame

	# Assert swing_ended ignoré : _trail_fade_start_msec reste 0
	assert_int(vfx._trail_fade_start_msec) \
		.override_failure_message("AC-VFX-15: _trail_fade_start_msec doit rester 0 (swing_ended ignoré en MENU)") \
		.is_equal(0)
	assert_bool(vfx._trail_active) \
		.override_failure_message("AC-VFX-15: _trail_active doit rester false après swing_ended en MENU") \
		.is_false()

	_free_all(nodes)


# =============================================================================
# AC-VFX-16 — PAUSED freeze pool + flash overlay
# =============================================================================

## GIVEN slots emitting=true + _flash_kill_active=true + overlay visible,
## WHEN state_changed(PAUSED=2) émis,
## THEN tous slots emitting==false + process_mode==DISABLED
##   ET flash overlay hidden + _flash_kill_active==false + trail cleared.
func test_paused_freezes_pool_and_flash_overlay() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_gsm: Node = nodes[5]

	# Pré-setter 3 premiers slots emitting=true
	for i: int in range(3):
		(vfx._blood_particle_pool[i] as GPUParticles3D).emitting = true

	# Pré-setter flash actif
	vfx._flash_kill_active = true
	vfx._flash_overlay_rect.visible = true
	vfx._trail_active = true
	vfx._trail_mesh.visible = true

	# Act — state_changed(PAUSED=2)
	mock_gsm.state_changed.emit(2)
	await get_tree().process_frame
	await get_tree().process_frame

	# Assert _is_active
	assert_bool(vfx._is_active) \
		.override_failure_message("AC-VFX-16: _is_active doit être false après state_changed(PAUSED)") \
		.is_false()

	# Assert tous les slots pool DISABLED
	for i: int in range(vfx._blood_particle_pool.size()):
		var p: GPUParticles3D = vfx._blood_particle_pool[i] as GPUParticles3D
		assert_bool(p.emitting) \
			.override_failure_message("AC-VFX-16: slot %d emitting doit être false après freeze PAUSED" % i) \
			.is_false()
		assert_int(p.process_mode) \
			.override_failure_message("AC-VFX-16: slot %d process_mode doit être PROCESS_MODE_DISABLED après freeze" % i) \
			.is_equal(Node.PROCESS_MODE_DISABLED)

	# Assert flash overlay cleared
	assert_bool(vfx._flash_overlay_rect.visible) \
		.override_failure_message("AC-VFX-16: flash_overlay_rect.visible doit être false après freeze PAUSED") \
		.is_false()
	assert_bool(vfx._flash_kill_active) \
		.override_failure_message("AC-VFX-16: _flash_kill_active doit être false après freeze PAUSED") \
		.is_false()

	# Assert _flash_respawn_active aussi cleared (couvert par _freeze_vfx, qa-tester gap fix)
	assert_bool(vfx._flash_respawn_active) \
		.override_failure_message("AC-VFX-16: _flash_respawn_active doit être false après freeze PAUSED") \
		.is_false()

	# Assert trail cleared
	assert_bool(vfx._trail_mesh.visible) \
		.override_failure_message("AC-VFX-16: trail_mesh.visible doit être false après freeze PAUSED") \
		.is_false()
	assert_bool(vfx._trail_active) \
		.override_failure_message("AC-VFX-16: _trail_active doit être false après freeze PAUSED") \
		.is_false()

	_free_all(nodes)


# =============================================================================
# AC-VFX-17 — PAUSED → PLAYING restaure process_mode
# =============================================================================

## GIVEN VFX en état PAUSED (tous slots PROCESS_MODE_DISABLED, _is_active=false),
## WHEN state_changed(PLAYING=1) émis,
## THEN _is_active==true + tous slots process_mode==PROCESS_MODE_INHERIT
##   ET trail Idle (visible==false) + flash overlay prêt (visible==false).
func test_paused_to_playing_restores_process_mode() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_gsm: Node = nodes[5]

	# Forcer état PAUSED (force directement, sans passer par signal pour isoler)
	vfx._is_active = false
	for p: GPUParticles3D in vfx._blood_particle_pool:
		p.process_mode = Node.PROCESS_MODE_DISABLED

	# Act — state_changed(PLAYING=1) → restore
	mock_gsm.state_changed.emit(1)
	await get_tree().process_frame
	await get_tree().process_frame

	# Assert _is_active
	assert_bool(vfx._is_active) \
		.override_failure_message("AC-VFX-17: _is_active doit être true après state_changed(PLAYING)") \
		.is_true()

	# Assert tous les slots process_mode INHERIT
	for i: int in range(vfx._blood_particle_pool.size()):
		var p: GPUParticles3D = vfx._blood_particle_pool[i] as GPUParticles3D
		assert_int(p.process_mode) \
			.override_failure_message("AC-VFX-17: slot %d process_mode doit être PROCESS_MODE_INHERIT après restore PLAYING" % i) \
			.is_equal(Node.PROCESS_MODE_INHERIT)

	# Assert trail Idle (pas orphelin)
	assert_bool(vfx._trail_mesh.visible) \
		.override_failure_message("AC-VFX-17: trail_mesh.visible doit être false (Idle) après restore PLAYING") \
		.is_false()
	assert_bool(vfx._trail_active) \
		.override_failure_message("AC-VFX-17: _trail_active doit être false (Idle) après restore PLAYING") \
		.is_false()

	# Assert flash overlay prêt (pas affiché)
	assert_bool(vfx._flash_overlay_rect.visible) \
		.override_failure_message("AC-VFX-17: flash_overlay_rect.visible doit être false après restore PLAYING") \
		.is_false()

	_free_all(nodes)


# =============================================================================
# AC-VFX-16/17 (extension) — BOSS_DEFEATED freeze (matrice ADR-0007 D-2)
# =============================================================================

## GIVEN VFX actif (PLAYING),
## WHEN state_changed(BOSS_DEFEATED=4) émis,
## THEN identique freeze PAUSED — _is_active=false + slots DISABLED + flash hidden.
## Protège contre régression silencieuse si enum GSM réordonnée post-autoload boot.
func test_boss_defeated_freezes_pool_like_paused() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_gsm: Node = nodes[5]

	# Pré-setter pool actif
	vfx._blood_particle_pool[0].emitting = true
	vfx._flash_overlay_rect.visible = true
	vfx._flash_kill_active = true

	# Act — state_changed(BOSS_DEFEATED=4)
	mock_gsm.state_changed.emit(4)
	await get_tree().process_frame
	await get_tree().process_frame

	# Assert freeze identique PAUSED
	assert_bool(vfx._is_active) \
		.override_failure_message("AC-VFX-16/17 ext: _is_active doit être false après state_changed(BOSS_DEFEATED=4)") \
		.is_false()
	assert_int(vfx._blood_particle_pool[0].process_mode) \
		.override_failure_message("AC-VFX-16/17 ext: slot[0].process_mode doit être PROCESS_MODE_DISABLED après BOSS_DEFEATED freeze") \
		.is_equal(Node.PROCESS_MODE_DISABLED)
	assert_bool(vfx._flash_overlay_rect.visible) \
		.override_failure_message("AC-VFX-16/17 ext: flash overlay doit être hidden après BOSS_DEFEATED freeze") \
		.is_false()

	_free_all(nodes)


# =============================================================================
# AC-VFX-17 (extension) — RESPAWNING actif (matrice ADR-0007 D-2 Pillar 3)
# =============================================================================

## GIVEN VFX en état frozen (MENU = 0 force _is_active=false),
## WHEN state_changed(RESPAWNING=3) émis,
## THEN _is_active==true + restore process_mode (Pillar 3 — VFX visible pendant respawn 50 ms).
## Protège story-004 flash respawn dépendant de cet état.
func test_respawning_state_keeps_vfx_active() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_gsm: Node = nodes[5]

	# Force état frozen (MENU)
	mock_gsm.state_changed.emit(0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(vfx._is_active) \
		.override_failure_message("Pré-condition: _is_active=false après MENU freeze") \
		.is_false()

	# Act — state_changed(RESPAWNING=3) → restore (Pillar 3)
	mock_gsm.state_changed.emit(3)
	await get_tree().process_frame
	await get_tree().process_frame

	# Assert RESPAWNING actif (identique PLAYING)
	assert_bool(vfx._is_active) \
		.override_failure_message("AC-VFX-17 ext: _is_active doit être true après state_changed(RESPAWNING=3) — Pillar 3 VFX visible respawn") \
		.is_true()

	for i: int in range(vfx._blood_particle_pool.size()):
		var p: GPUParticles3D = vfx._blood_particle_pool[i] as GPUParticles3D
		assert_int(p.process_mode) \
			.override_failure_message("AC-VFX-17 ext: slot[%d].process_mode doit être PROCESS_MODE_INHERIT après RESPAWNING restore" % i) \
			.is_equal(Node.PROCESS_MODE_INHERIT)

	_free_all(nodes)


# =============================================================================
# AC-NEW-08 — boot MENU state : pool DISABLED + enemy_killed bloqué
# =============================================================================

## GIVEN mock_gsm.set_state(MENU=0) AVANT injection,
## WHEN connect_gsm_signals(mock_gsm) → pull initial → _apply_visibility_for_state(0) → freeze,
## THEN _is_active==false + tous slots process_mode==PROCESS_MODE_DISABLED
##   ET enemy_killed ultérieur ne trigger aucun slot emitting.
func test_boot_menu_state_disables_pool_and_blocks_spawn() -> void:
	# Arrange — mock GSM en état MENU avant injection
	var mock_combat: Node = _MockCombat.new() as Node
	var mock_enemy: Node = _MockEnemy.new() as Node
	var mock_camera: Node = _MockCamera.new() as Node
	var mock_accessibility: Node = _MockAccessibility.new() as Node
	var mock_gsm: Node = _MockGSM.new() as Node

	add_child(mock_combat)
	add_child(mock_enemy)
	add_child(mock_camera)
	add_child(mock_accessibility)
	add_child(mock_gsm)

	# Set MENU state AVANT injection VFX
	mock_gsm.set_state(0)  # STATE_MENU = 0

	var vfx: Node = _VFXScript.new() as Node
	add_child(vfx)

	vfx.connect_combat_signals(mock_combat)
	vfx.connect_enemy_signals(mock_enemy)
	vfx.connect_camera_signals(mock_camera)
	vfx.connect_accessibility_signals(mock_accessibility)
	# Injecter GSM en dernier → pull initial → MENU → freeze
	vfx.connect_gsm_signals(mock_gsm)

	# Assert état boot MENU
	assert_bool(vfx._is_active) \
		.override_failure_message("AC-NEW-08: _is_active doit être false après boot en état MENU") \
		.is_false()

	for i: int in range(vfx._blood_particle_pool.size()):
		var p: GPUParticles3D = vfx._blood_particle_pool[i] as GPUParticles3D
		assert_int(p.process_mode) \
			.override_failure_message("AC-NEW-08: slot %d process_mode doit être PROCESS_MODE_DISABLED après boot MENU" % i) \
			.is_equal(Node.PROCESS_MODE_DISABLED)

	# Act — enemy_killed en état MENU (doit être bloqué)
	vfx._flash_last_msec = -333  # bypass guard WCAG au cas où
	mock_enemy.enemy_killed.emit(null, Vector3.ZERO)
	await get_tree().process_frame
	await get_tree().process_frame

	# Assert aucun slot emitting
	for i: int in range(vfx._blood_particle_pool.size()):
		var p: GPUParticles3D = vfx._blood_particle_pool[i] as GPUParticles3D
		assert_bool(p.emitting) \
			.override_failure_message("AC-NEW-08: slot %d emitting doit être false (gated par _is_active=false)" % i) \
			.is_false()

	var all_nodes: Array = [vfx, mock_combat, mock_enemy, mock_camera, mock_accessibility, mock_gsm]
	_free_all(all_nodes)


# =============================================================================
# EC-VFX-05 — séquence complète trail : MENU pendant swing → retour PLAYING
# =============================================================================

## GIVEN PLAYING initial + swing_started,
## WHEN state_changed(MENU) → swing_ended (ignoré) → state_changed(PLAYING),
## THEN trail final Idle : visible==false, _trail_active==false, _trail_fade_start_msec==0.
## Vérifie qu'il n'y a pas de trail orphelin après la séquence.
func test_menu_during_trail_full_sequence_no_orphan() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_combat: Node = nodes[1]
	var mock_gsm: Node = nodes[5]

	vfx._get_time_msec = func() -> int: return 0

	# Act — swing_started (PLAYING initial)
	mock_combat.swing_started.emit(Vector3.FORWARD)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_bool(vfx._trail_active) \
		.override_failure_message("EC-VFX-05: _trail_active doit être true après swing_started") \
		.is_true()

	# Act — state_changed(MENU) → freeze trail
	mock_gsm.state_changed.emit(0)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_bool(vfx._trail_active) \
		.override_failure_message("EC-VFX-05: _trail_active doit être false après MENU freeze") \
		.is_false()

	# Act — swing_ended ignoré (frozen)
	mock_combat.swing_ended.emit()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_int(vfx._trail_fade_start_msec) \
		.override_failure_message("EC-VFX-05: _trail_fade_start_msec doit rester 0 (swing_ended ignoré en MENU)") \
		.is_equal(0)

	# Act — state_changed(PLAYING) → restore
	mock_gsm.state_changed.emit(1)
	await get_tree().process_frame
	await get_tree().process_frame

	# Assert état final — trail Idle, pas orphelin
	assert_bool(vfx._is_active) \
		.override_failure_message("EC-VFX-05: _is_active doit être true après retour PLAYING") \
		.is_true()
	assert_bool(vfx._trail_active) \
		.override_failure_message("EC-VFX-05: _trail_active doit être false (Idle, pas orphelin) après retour PLAYING") \
		.is_false()
	assert_bool(vfx._trail_mesh.visible) \
		.override_failure_message("EC-VFX-05: trail_mesh.visible doit être false (Idle) après retour PLAYING") \
		.is_false()
	assert_int(vfx._trail_fade_start_msec) \
		.override_failure_message("EC-VFX-05: _trail_fade_start_msec doit être 0 (pas de fade-out orphelin)") \
		.is_equal(0)

	_free_all(nodes)
