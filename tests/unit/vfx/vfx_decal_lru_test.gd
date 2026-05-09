# Tests unitaires Story-003 — VFXSystem decal cap LRU eviction.
# Couvre AC-VFX-01 + AC-VFX-03 + AC-VFX-30 + AC-NEW-05 + AC-NEW-06.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic — automated unit tests (coding-standards.md §Test Evidence).
#
# Architecture :
# - _make_vfx() : helper de base (sans CollisionShape3D) — tests no-raycast
# - _make_vfx_with_large_floor() : helper avec StaticBody3D 200×0.1×200 —
#   garantit hit DOWN raycast à toutes positions des 64 kills dispersés
#
# Pattern miroir story-002 vfx_combat_handlers_test.gd.

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
## → _is_active = true au boot, évite gating handlers story-003).
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


## Instancie VFXSystem + mocks + StaticBody3D floor 200×0.1×200 centré à y=0.
## Le floor très large garantit hit DOWN raycast à toutes positions des 64 kills.
## Retourne [vfx, mock_combat, mock_enemy, mock_camera, mock_gsm, floor_body].
func _make_vfx_with_large_floor() -> Array:
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.name = &"TestLargeFloor"
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(200.0, 0.1, 200.0)
	col_shape.shape = box
	col_shape.position = Vector3(0.0, -0.05, 0.0)
	floor_body.add_child(col_shape)
	floor_body.position = Vector3(0.0, 0.0, 0.0)
	add_child(floor_body)

	# 2 physics frames pour que le StaticBody3D soit enregistré dans le PhysicsServer
	await get_tree().physics_frame
	await get_tree().physics_frame

	var base: Array = _make_vfx()
	base.append(floor_body)
	return base


func _free_all(nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()


# =============================================================================
# AC-VFX-01 — LRU recycle 33ème kill (_room_decal_count plafonné, _decal_write_head croît)
# =============================================================================

## GIVEN VFXSystem actif avec large floor (raycast garanti),
## WHEN 32 kills successifs puis un 33ème kill,
## THEN après 32 kills : _room_decal_count==32 + _decal_write_head==32,
##      après 33ème kill : _room_decal_count reste 32 (plafond) + _decal_write_head==33.
## Source : AC-VFX-01 [BLOCKING][AUTO] + R-VFX-4 (MAX_DECALS_PER_ROOM=32).
func test_lru_recycles_oldest_decal_at_33rd_kill() -> void:
	# Arrange — VFX + large floor pour garantir hit raycast
	var nodes: Array = await _make_vfx_with_large_floor()
	var vfx: Node = nodes[0]
	var mock_enemy: Node = nodes[2]

	# Act — 32 kills successifs (cap atteint, positions dispersées sur X)
	for i: int in range(32):
		mock_enemy.emit_enemy_killed(null, Vector3(float(i) * 0.5, 1.0, 0.0))
		await get_tree().physics_frame

	# Assert post-32 : cap atteint exactement
	assert_int(vfx._room_decal_count) \
		.override_failure_message("AC-VFX-01: _room_decal_count doit être 32 après 32 kills (cap MAX_DECALS_PER_ROOM)") \
		.is_equal(32)
	assert_int(vfx._decal_write_head) \
		.override_failure_message("AC-VFX-01: _decal_write_head doit être 32 après 32 kills") \
		.is_equal(32)

	# Act — 33ème kill (recycle slot 32 via modulo, LRU ring buffer)
	mock_enemy.emit_enemy_killed(null, Vector3(99.0, 1.0, 0.0))
	await get_tree().physics_frame

	# Assert post-33 : _room_decal_count plafonné, _decal_write_head incrémenté
	assert_int(vfx._room_decal_count) \
		.override_failure_message("AC-VFX-01: _room_decal_count doit RESTER à 32 après 33ème kill (plafond MAX_DECALS_PER_ROOM)") \
		.is_equal(32)
	assert_int(vfx._decal_write_head) \
		.override_failure_message("AC-VFX-01: _decal_write_head doit être 33 après 33ème kill (croissance indéfinie)") \
		.is_equal(33)

	# Assert direct sémantique LRU recycling — slot _decal_pool[32] (33ème = 32 mod 64)
	# repositionné à la position du 33ème kill (X=99). Couvre qa-tester gap "couverture indirecte".
	var slot_32_x: float = vfx._decal_pool[32].global_position.x
	assert_float(slot_32_x) \
		.override_failure_message("AC-VFX-01: _decal_pool[32].global_position.x doit être ≈99 (33ème kill repositionné), got %f" % slot_32_x) \
		.is_greater(90.0)

	_free_all(nodes)


# =============================================================================
# AC-VFX-03 — No surface skip silencieux : _decal_write_head PAS incrémenté
# =============================================================================

## GIVEN VFXSystem actif sans CollisionShape3D (pas de surface),
## WHEN enemy_killed(null, Vector3(0, 100, 0)) reçu (position trop haute, no hit),
## THEN _decal_write_head reste 0 + _room_decal_count reste 0 (skip silencieux).
## Source : AC-VFX-03 [BLOCKING][AUTO] + EC-VFX-07 (skip silencieux no surface).
func test_decal_no_surface_does_not_increment_write_head() -> void:
	# Arrange — PAS de floor (raycast ne peut pas toucher de surface)
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_enemy: Node = nodes[2]

	await get_tree().physics_frame
	await get_tree().physics_frame

	# Act — kill très haut en l'air (raycast DOWN sur 3 m sans surface)
	mock_enemy.emit_enemy_killed(null, Vector3(0.0, 100.0, 0.0))
	await get_tree().physics_frame

	# Assert — _decal_write_head PAS incrémenté (skip silencieux)
	assert_int(vfx._decal_write_head) \
		.override_failure_message("AC-VFX-03: _decal_write_head doit RESTER à 0 quand raycast ne trouve aucune surface") \
		.is_equal(0)

	assert_int(vfx._room_decal_count) \
		.override_failure_message("AC-VFX-03: _room_decal_count doit RESTER à 0 (aucun decal spawné)") \
		.is_equal(0)

	_free_all(nodes)


# =============================================================================
# AC-VFX-30 — Combat-021 contract résolu : constants MAX_DECALS + POOL_SIZE + cross-ref
# =============================================================================

## GIVEN VFXSystem instancié,
## WHEN lecture des constantes pool LRU,
## THEN MAX_DECALS_PER_ROOM==32 (R-VFX-4) + DECAL_POOL_SIZE==64 (double-buffer R-VFX-2)
##      + story combat-021 reflète "Closed - Migrated to VFX System".
## Source : AC-VFX-30 [BLOCKING][AUTO] + AC-CMB-42 migration.
func test_combat_021_contract_resolved_max_decals_32() -> void:
	# Arrange + Act
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]

	# Assert constant MAX_DECALS_PER_ROOM == 32 (R-VFX-4 + AC-CMB-42 migration)
	assert_int(vfx.MAX_DECALS_PER_ROOM) \
		.override_failure_message("AC-VFX-30: MAX_DECALS_PER_ROOM doit être 32 (R-VFX-4 — contract Combat-021 migration)") \
		.is_equal(32)

	# Assert pool size == 2 × MAX (R-VFX-2 double-buffer LRU)
	assert_int(vfx.DECAL_POOL_SIZE) \
		.override_failure_message("AC-VFX-30: DECAL_POOL_SIZE doit être 64 (= 2 × MAX_DECALS_PER_ROOM, double-buffer)") \
		.is_equal(64)

	# Assert combat-021 story file : status reflète migration close-out
	# qa-tester GAP-fix : assert file existence d'abord — élimine skip silencieux fragile.
	# Le contrat cross-ref AC-VFX-30 ne peut pas être validé si combat-021 est rename/archivé.
	var combat_021_path: String = "res://production/epics/combat-system/story-021-vfx-decal-cap-pool-lru.md"
	assert_bool(FileAccess.file_exists(combat_021_path)) \
		.override_failure_message("AC-VFX-30: combat-021 story file introuvable à %s — contrat cross-ref non gardé (rename/archivage non prévu ?)" % combat_021_path) \
		.is_true()

	var f: FileAccess = FileAccess.open(combat_021_path, FileAccess.READ)
	var content: String = f.get_as_text()
	f.close()
	var has_migration_marker: bool = (
		content.contains("Closed - Migrated to VFX System")
		or content.contains("Closed-Migrated")
		or content.contains("Migrated to VFX")
	)
	assert_bool(has_migration_marker) \
		.override_failure_message("AC-VFX-30: combat story-021 status doit refléter migration close-out (marker absent)") \
		.is_true()

	_free_all(nodes)


# =============================================================================
# AC-NEW-05 — 64 kills : wrap complet LRU, tous 64 slots du pool utilisés
# =============================================================================

## GIVEN VFXSystem actif avec large floor (raycast garanti),
## WHEN 64 kills successifs (= DECAL_POOL_SIZE),
## THEN _decal_write_head==64 (croissance indéfinie) + _room_decal_count==32 (plafond)
##      + tous les 64 slots du pool ont visible==true (chaque slot visité 1× au moins).
## Source : AC-NEW-05 [BLOCKING][AUTO] — wrap ring buffer complet.
func test_lru_wraps_at_64_kills_all_pool_slots_used() -> void:
	# Arrange
	var nodes: Array = await _make_vfx_with_large_floor()
	var vfx: Node = nodes[0]
	var mock_enemy: Node = nodes[2]

	# Act — 64 kills (= DECAL_POOL_SIZE), positions dispersées pour couvrir le floor
	for i: int in range(64):
		mock_enemy.emit_enemy_killed(null, Vector3(float(i) * 0.5, 1.0, 0.0))
		await get_tree().physics_frame

	# Assert — write_head croissance indéfinie
	assert_int(vfx._decal_write_head) \
		.override_failure_message("AC-NEW-05: _decal_write_head doit être 64 après 64 kills (croissance indéfinie sans wrap variable)") \
		.is_equal(64)

	# Assert — room count plafonné
	assert_int(vfx._room_decal_count) \
		.override_failure_message("AC-NEW-05: _room_decal_count doit être 32 (plafonné MAX_DECALS_PER_ROOM)") \
		.is_equal(32)

	# Assert — tous les 64 slots ont été activés (visible=true après passage LRU)
	var visible_count: int = 0
	for d: Decal in vfx._decal_pool:
		if d.visible:
			visible_count += 1

	assert_int(visible_count) \
		.override_failure_message("AC-NEW-05: les 64 slots du pool doivent tous être visible=true (chaque slot utilisé 1× au minimum via ring buffer)") \
		.is_equal(64)

	_free_all(nodes)


# =============================================================================
# AC-NEW-06 — Respawn resets complet : pool + compteurs decals
# =============================================================================

## GIVEN VFXSystem avec _decal_write_head=50, _room_decal_count=32, 32 decals visibles,
## WHEN respawned(Vector3.ZERO) reçu,
## THEN _decal_write_head==0 + _room_decal_count==0 + tous decals visible==false.
## Source : AC-NEW-06 [BLOCKING][AUTO] — reset LRU complet sur respawn.
func test_respawn_resets_decal_pool_and_counters() -> void:
	# Arrange — pré-set état post-32 kills
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_camera: Node = nodes[3]

	vfx._decal_write_head = 50
	vfx._room_decal_count = 32
	for i: int in range(32):
		vfx._decal_pool[i].visible = true

	# Act
	mock_camera.emit_respawned(Vector3.ZERO)
	await get_tree().physics_frame

	# Assert — compteurs reset
	assert_int(vfx._decal_write_head) \
		.override_failure_message("AC-NEW-06: _decal_write_head doit être 0 après respawn") \
		.is_equal(0)

	assert_int(vfx._room_decal_count) \
		.override_failure_message("AC-NEW-06: _room_decal_count doit être 0 après respawn") \
		.is_equal(0)

	# Assert — tous les slots cachés (pas seulement les 32 activés)
	for i: int in range(vfx._decal_pool.size()):
		assert_bool(vfx._decal_pool[i].visible) \
			.override_failure_message("AC-NEW-06: _decal_pool[%d].visible doit être false après respawn" % i) \
			.is_false()

	_free_all(nodes)
