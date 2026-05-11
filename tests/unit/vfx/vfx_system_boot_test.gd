# Tests unitaires Story-001 — VFXSystem autoload skeleton + pool pré-allocation.
# Couvre AC-VFX-04 + AC-VFX-05 + AC-NEW-01 + AC-NEW-02 + AC-NEW-03 + AC-NEW-04.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic — automated unit tests (coding-standards.md §Test Evidence).
#
# Naming : test_[scenario]_[expected_result] (test-standards.md).
#
# Architecture : instanciation directe de VFXSystemScript (pas via autoload)
# pour tests hermétiques — mocks injectés via connect_* helpers publics.
# Pattern : miroir de hud_system_boot_test.gd + audio epic.

extends GdUnitTestSuite

const _VFX_SCRIPT_PATH: String = "res://src/core/vfx_system.gd"
const _MOCK_COMBAT_PATH: String = "res://tests/unit/vfx/mock_combat.gd"
const _MOCK_ENEMY_PATH: String = "res://tests/unit/vfx/mock_enemy.gd"
const _MOCK_CAMERA_PATH: String = "res://tests/unit/vfx/mock_camera.gd"
const _MOCK_GSM_PATH: String = "res://tests/unit/vfx/mock_gsm.gd"
const _MOCK_ACCESSIBILITY_PATH: String = "res://tests/unit/vfx/mock_accessibility.gd"

# Préchargés une fois — évite preload répété dans chaque test.
var _VFXScript: GDScript = preload("res://src/core/vfx_system.gd")
var _MockCombat: GDScript = preload("res://tests/unit/vfx/mock_combat.gd")
var _MockEnemy: GDScript = preload("res://tests/unit/vfx/mock_enemy.gd")
var _MockCamera: GDScript = preload("res://tests/unit/vfx/mock_camera.gd")
var _MockGSM: GDScript = preload("res://tests/unit/vfx/mock_gsm.gd")
var _MockAccessibility: GDScript = preload("res://tests/unit/vfx/mock_accessibility.gd")


# =============================================================================
# Helpers — instanciation hermétique
# =============================================================================

## Instancie VFXSystem + mocks hermétiques.
## Retourne [vfx, mock_combat, mock_enemy, mock_camera, mock_gsm, mock_accessibility].
## add_child(vfx) déclenche _ready() après injection des mocks.
## Note : les mocks ne sont PAS dans /root/ — VFXSystem._connect_upstream_signals()
## retourne no-op (get_node_or_null retourne null). Les connexions sont ensuite
## réalisées via les helpers publics connect_*_signals().
func _make_vfx() -> Array:
	var mock_combat: Node = _MockCombat.new() as Node
	var mock_enemy: Node = _MockEnemy.new() as Node
	var mock_camera: Node = _MockCamera.new() as Node
	var mock_gsm: Node = _MockGSM.new() as Node
	var mock_accessibility: Node = _MockAccessibility.new() as Node

	add_child(mock_combat)
	add_child(mock_enemy)
	add_child(mock_camera)
	add_child(mock_gsm)
	add_child(mock_accessibility)

	var vfx: Node = _VFXScript.new() as Node
	add_child(vfx)  # déclenche _ready()

	# Injection via helpers publics (pattern AudioSystem.connect_combat_signals)
	vfx.connect_combat_signals(mock_combat)
	vfx.connect_enemy_signals(mock_enemy)
	vfx.connect_camera_signals(mock_camera)
	vfx.connect_gsm_signals(mock_gsm)
	vfx.connect_accessibility_signals(mock_accessibility)

	return [vfx, mock_combat, mock_enemy, mock_camera, mock_gsm, mock_accessibility]


func _free_all(nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()


# =============================================================================
# AC-VFX-04 — MEMORY_STATIC delta < 16 KB après 60 ticks idle post-boot
# =============================================================================
# Scope story-001 : idle 60 ticks SANS signal entrant — couvre l'invariant
# "no allocation post-boot quand VFXSystem est silencieux". Stress 30 kills =
# story-002+ scope (handlers bodies ajoutent splash + decal + flash hot path).

## GIVEN VFXSystem instancié et 60 physics ticks simulés idle (zero signal entrant),
## WHEN delta MEMORY_STATIC mesuré,
## THEN delta < 16 384 octets (16 KB).
## Source : AC-VFX-04 [BLOCKING][AUTO] — scope story-001 idle uniquement.
func test_zero_alloc_post_boot_under_16kb() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]

	# Stabilisation post-_ready() — force GC avant mesure baseline
	await get_tree().process_frame
	await get_tree().process_frame

	var mem_before: int = Performance.get_monitor(Performance.MEMORY_STATIC)

	# Act — 60 ticks idle via _physics_process (VFXSystem n'a pas de _physics_process
	# en story-001 — les stubs handlers sont no-op, donc aucune alloc à vérifier).
	# On simule 60 frames engine pour être sûr.
	for _i: int in range(60):
		await get_tree().process_frame

	var mem_after: int = Performance.get_monitor(Performance.MEMORY_STATIC)
	var delta: int = mem_after - mem_before

	# Assert
	assert_int(delta) \
		.override_failure_message("AC-VFX-04: delta MEMORY_STATIC idle 60 ticks = %d bytes (limite 16384)" % delta) \
		.is_less_equal(16384)

	_free_all(nodes)


# =============================================================================
# AC-VFX-05 — lint static : zéro GPUParticles3D.new() hors vfx_system.gd
# =============================================================================

## GIVEN le codebase src/,
## WHEN grep récursif GPUParticles3D.new()|Decal.new()|MeshInstance3D.new()
##      hors src/core/vfx_system.gd,
## THEN zéro match (R-VFX-2 pool exclusive — pattern ADR-0009 D-2).
## Source : AC-VFX-05 [BLOCKING][AUTO] — lint statique inline (story-007 = lint complet).
func test_no_vfx_new_outside_vfx_system() -> void:
	var violations: PackedStringArray = PackedStringArray()
	var pattern: RegEx = RegEx.new()
	pattern.compile("(GPUParticles3D|Decal|MeshInstance3D)\\.new\\(\\)")

	var src_dir: String = "res://src"
	var vfx_system_path: String = "res://src/core/vfx_system.gd"

	_scan_dir_for_pattern(src_dir, pattern, vfx_system_path, violations)

	assert_int(violations.size()) \
		.override_failure_message("AC-VFX-05: %d violation(s) GPUParticles3D/Decal/MeshInstance3D.new() hors vfx_system.gd:\n%s" % [
			violations.size(),
			"\n".join(Array(violations)),
		]) \
		.is_equal(0)


## Scan récursif d'un répertoire pour un pattern RegEx.
## Skip le fichier `excluded_path`. Remplit `out_violations`.
func _scan_dir_for_pattern(
	dir_path: String,
	pattern: RegEx,
	excluded_path: String,
	out_violations: PackedStringArray,
) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full_path: String = dir_path + "/" + name
		if dir.current_is_dir():
			_scan_dir_for_pattern(full_path, pattern, excluded_path, out_violations)
		elif name.ends_with(".gd"):
			if full_path != excluded_path:
				_check_file_for_pattern(full_path, pattern, out_violations)
		name = dir.get_next()
	dir.list_dir_end()


## Lit un fichier ligne par ligne et ajoute les violations dans out_violations.
func _check_file_for_pattern(
	file_path: String,
	pattern: RegEx,
	out_violations: PackedStringArray,
) -> void:
	var f: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return
	var line_num: int = 0
	while not f.eof_reached():
		var line: String = f.get_line()
		line_num += 1
		# Skip comment lines
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		# Skip lignes annotées `lint-vfx-pool-ok` (parité shell lint vfx-anti-patterns.md)
		if line.find("lint-vfx-pool-ok") != -1:
			continue
		if pattern.search(line) != null:
			out_violations.append("%s:%d: %s" % [file_path, line_num, stripped])
	f.close()


# =============================================================================
# AC-NEW-01 — pool sizes et références non-null après _ready()
# =============================================================================

## GIVEN VFXSystem instancié,
## WHEN _ready() exécuté,
## THEN _blood_particle_pool.size()==8, _decal_pool.size()==64,
##      _trail_mesh != null, _flash_overlay_rect != null.
## Source : AC-NEW-01 [BLOCKING][AUTO].
func test_pool_preallocated_exact_sizes() -> void:
	# Arrange + Act
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]

	# Assert pool particles
	assert_int(vfx._blood_particle_pool.size()) \
		.override_failure_message("AC-NEW-01: _blood_particle_pool.size() doit être 8") \
		.is_equal(8)

	# Assert pool decals
	assert_int(vfx._decal_pool.size()) \
		.override_failure_message("AC-NEW-01: _decal_pool.size() doit être 64") \
		.is_equal(64)

	# Assert trail mesh non-null
	assert_object(vfx._trail_mesh) \
		.override_failure_message("AC-NEW-01: _trail_mesh doit être non-null après _ready()") \
		.is_not_null()

	# Assert flash overlay non-null
	assert_object(vfx._flash_overlay_rect) \
		.override_failure_message("AC-NEW-01: _flash_overlay_rect doit être non-null après _ready()") \
		.is_not_null()

	_free_all(nodes)


# =============================================================================
# AC-NEW-01 (suite) — scene tree topology : VFXPool3D + VFXFlashOverlay layer
# =============================================================================

## GIVEN VFXSystem instancié,
## WHEN _ready() exécuté,
## THEN scene tree contient VFXPool3D (Node3D) + VFXFlashOverlay (CanvasLayer
##      avec layer == FLASH_OVERLAY_LAYER) + ColorRect avec mouse_filter IGNORE.
## Source : AC-NEW-01 [BLOCKING][AUTO] — topology garde-fou refactor (qa-tester GAP-1).
func test_pool_scene_tree_topology_correct() -> void:
	# Arrange + Act
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]

	# Assert VFXPool3D enfant direct
	var pool_root: Node = vfx.get_node_or_null("VFXPool3D")
	assert_object(pool_root) \
		.override_failure_message("AC-NEW-01: VFXPool3D enfant direct VFXSystem absent") \
		.is_not_null()
	assert_bool(pool_root is Node3D) \
		.override_failure_message("AC-NEW-01: VFXPool3D doit être un Node3D") \
		.is_true()

	# Assert VFXFlashOverlay CanvasLayer enfant direct
	var flash_layer: Node = vfx.get_node_or_null("VFXFlashOverlay")
	assert_object(flash_layer) \
		.override_failure_message("AC-NEW-01: VFXFlashOverlay enfant direct VFXSystem absent") \
		.is_not_null()
	assert_bool(flash_layer is CanvasLayer) \
		.override_failure_message("AC-NEW-01: VFXFlashOverlay doit être un CanvasLayer") \
		.is_true()

	# Assert layer == FLASH_OVERLAY_LAYER (60 — sous GSM 100)
	var layer_value: int = (flash_layer as CanvasLayer).layer
	assert_int(layer_value) \
		.override_failure_message("AC-NEW-01: VFXFlashOverlay.layer doit être %d (got %d)" % [
			vfx.FLASH_OVERLAY_LAYER, layer_value
		]) \
		.is_equal(vfx.FLASH_OVERLAY_LAYER)

	# Assert ColorRect mouse_filter IGNORE
	assert_int(vfx._flash_overlay_rect.mouse_filter) \
		.override_failure_message("AC-NEW-01: FlashOverlayRect.mouse_filter doit être MOUSE_FILTER_IGNORE pour ne pas bloquer input") \
		.is_equal(Control.MOUSE_FILTER_IGNORE)

	_free_all(nodes)


# =============================================================================
# AC-NEW-02 — tous les nodes pool sont invisibles au boot
# =============================================================================

## GIVEN VFXSystem instancié,
## WHEN _ready() exécuté,
## THEN tous GPUParticles3D.emitting==false, tous Decal.visible==false,
##      _trail_mesh.visible==false, _flash_overlay_rect.visible==false.
## Source : AC-NEW-02 [BLOCKING][AUTO].
func test_pool_nodes_invisible_after_ready() -> void:
	# Arrange + Act
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]

	# Assert particles emitting == false
	for i: int in range(vfx._blood_particle_pool.size()):
		var p: GPUParticles3D = vfx._blood_particle_pool[i]
		assert_bool(p.emitting) \
			.override_failure_message("AC-NEW-02: GPUParticles3D[%d].emitting doit être false au boot" % i) \
			.is_false()

	# Assert decals invisible
	for i: int in range(vfx._decal_pool.size()):
		var d: Decal = vfx._decal_pool[i]
		assert_bool(d.visible) \
			.override_failure_message("AC-NEW-02: Decal[%d].visible doit être false au boot" % i) \
			.is_false()

	# Assert trail mesh invisible
	assert_bool(vfx._trail_mesh.visible) \
		.override_failure_message("AC-NEW-02: _trail_mesh.visible doit être false au boot") \
		.is_false()

	# Assert flash overlay invisible
	assert_bool(vfx._flash_overlay_rect.visible) \
		.override_failure_message("AC-NEW-02: _flash_overlay_rect.visible doit être false au boot") \
		.is_false()

	_free_all(nodes)


# =============================================================================
# AC-NEW-03 — ShaderMaterial partagé (même instance) entre tous les slots particles
# =============================================================================

## GIVEN VFXSystem instancié,
## WHEN _ready() exécuté,
## THEN _blood_particle_pool[0].process_material == _blood_particle_pool[7].process_material
##      (même référence objet — is_same identity check — R-VFX-16 budget draw calls).
## Source : AC-NEW-03 [BLOCKING][AUTO].
func test_blood_shader_material_shared_instance() -> void:
	# Arrange + Act
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]

	# Assert ShaderMaterial partagé non-null
	assert_object(vfx._blood_shader_material) \
		.override_failure_message("AC-NEW-03: _blood_shader_material doit être non-null") \
		.is_not_null()

	# Assert toutes les particules partagent la MÊME instance (is_same identity check)
	var mat_ref: ShaderMaterial = vfx._blood_particle_pool[0].process_material as ShaderMaterial
	assert_object(mat_ref) \
		.override_failure_message("AC-NEW-03: pool[0].process_material doit être un ShaderMaterial") \
		.is_not_null()

	for i: int in range(1, vfx._blood_particle_pool.size()):
		var mat_i: ShaderMaterial = vfx._blood_particle_pool[i].process_material as ShaderMaterial
		# Vérification identité GdUnit4 idiomatic — is_same() évite fragilité futur
		# Resource _init custom equality (qa-tester A2 2026-05-05).
		assert_object(mat_i) \
			.override_failure_message(
				"AC-NEW-03: pool[%d].process_material doit être la MÊME instance que pool[0] (R-VFX-16 shared material)" % i
			) \
			.is_same(mat_ref)

	_free_all(nodes)


# =============================================================================
# AC-NEW-04 — connexions upstream CONNECT_DEFERRED présentes
# =============================================================================

## GIVEN VFXSystem instancié avec mocks injectés,
## WHEN connexions réalisées via connect_*_signals(),
## THEN tous les signals mockés ont >= 1 connection avec flag CONNECT_DEFERRED.
## Source : AC-NEW-04 [BLOCKING][AUTO].
func test_upstream_signals_connected_deferred() -> void:
	# Arrange + Act
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_combat: Node = nodes[1]
	var mock_enemy: Node = nodes[2]
	var mock_camera: Node = nodes[3]
	var mock_gsm: Node = nodes[4]
	var mock_accessibility: Node = nodes[5]

	# Helper : vérifie qu'un signal a >= 1 connection avec CONNECT_DEFERRED.
	# get_connections() retourne Array[Dictionary] avec clés : signal, callable, flags.
	# CONNECT_DEFERRED = 1 en Godot 4.6 (vérifié runtime debug_flags.gd 2026-05-09).
	# Pas 8 — valeur 4.3 era stale. Utiliser la constante symbolique ENGINE.
	const CONNECT_DEFERRED_FLAG: int = CONNECT_DEFERRED

	# Combat — swing_started
	var swing_started_conns: Array = mock_combat.swing_started.get_connections()
	assert_int(swing_started_conns.size()) \
		.override_failure_message("AC-NEW-04: mock_combat.swing_started doit avoir exactement 1 connection (détecteur double-connect)") \
		.is_equal(1)
	assert_int(int(swing_started_conns[0].get("flags", 0)) & CONNECT_DEFERRED_FLAG) \
		.override_failure_message("AC-NEW-04: mock_combat.swing_started doit être connecté CONNECT_DEFERRED") \
		.is_equal(CONNECT_DEFERRED_FLAG)

	# Combat — swing_ended
	var swing_ended_conns: Array = mock_combat.swing_ended.get_connections()
	assert_int(swing_ended_conns.size()) \
		.override_failure_message("AC-NEW-04: mock_combat.swing_ended doit avoir exactement 1 connection (détecteur double-connect)") \
		.is_equal(1)
	assert_int(int(swing_ended_conns[0].get("flags", 0)) & CONNECT_DEFERRED_FLAG) \
		.override_failure_message("AC-NEW-04: mock_combat.swing_ended doit être connecté CONNECT_DEFERRED") \
		.is_equal(CONNECT_DEFERRED_FLAG)

	# Combat — multi_kill
	var multi_kill_conns: Array = mock_combat.multi_kill.get_connections()
	assert_int(multi_kill_conns.size()) \
		.override_failure_message("AC-NEW-04: mock_combat.multi_kill doit avoir exactement 1 connection (détecteur double-connect)") \
		.is_equal(1)
	assert_int(int(multi_kill_conns[0].get("flags", 0)) & CONNECT_DEFERRED_FLAG) \
		.override_failure_message("AC-NEW-04: mock_combat.multi_kill doit être connecté CONNECT_DEFERRED") \
		.is_equal(CONNECT_DEFERRED_FLAG)

	# Enemy — enemy_killed
	var enemy_killed_conns: Array = mock_enemy.enemy_killed.get_connections()
	assert_int(enemy_killed_conns.size()) \
		.override_failure_message("AC-NEW-04: mock_enemy.enemy_killed doit avoir exactement 1 connection (détecteur double-connect)") \
		.is_equal(1)
	assert_int(int(enemy_killed_conns[0].get("flags", 0)) & CONNECT_DEFERRED_FLAG) \
		.override_failure_message("AC-NEW-04: mock_enemy.enemy_killed doit être connecté CONNECT_DEFERRED") \
		.is_equal(CONNECT_DEFERRED_FLAG)

	# Camera — died
	var died_conns: Array = mock_camera.died.get_connections()
	assert_int(died_conns.size()) \
		.override_failure_message("AC-NEW-04: mock_camera.died doit avoir exactement 1 connection (détecteur double-connect)") \
		.is_equal(1)
	assert_int(int(died_conns[0].get("flags", 0)) & CONNECT_DEFERRED_FLAG) \
		.override_failure_message("AC-NEW-04: mock_camera.died doit être connecté CONNECT_DEFERRED") \
		.is_equal(CONNECT_DEFERRED_FLAG)

	# Camera — respawned
	var respawned_conns: Array = mock_camera.respawned.get_connections()
	assert_int(respawned_conns.size()) \
		.override_failure_message("AC-NEW-04: mock_camera.respawned doit avoir exactement 1 connection (détecteur double-connect)") \
		.is_equal(1)
	assert_int(int(respawned_conns[0].get("flags", 0)) & CONNECT_DEFERRED_FLAG) \
		.override_failure_message("AC-NEW-04: mock_camera.respawned doit être connecté CONNECT_DEFERRED") \
		.is_equal(CONNECT_DEFERRED_FLAG)

	# GSM — state_changed
	var state_changed_conns: Array = mock_gsm.state_changed.get_connections()
	assert_int(state_changed_conns.size()) \
		.override_failure_message("AC-NEW-04: mock_gsm.state_changed doit avoir exactement 1 connection (détecteur double-connect)") \
		.is_equal(1)
	assert_int(int(state_changed_conns[0].get("flags", 0)) & CONNECT_DEFERRED_FLAG) \
		.override_failure_message("AC-NEW-04: mock_gsm.state_changed doit être connecté CONNECT_DEFERRED") \
		.is_equal(CONNECT_DEFERRED_FLAG)

	# AccessibilityService — settings_changed
	var settings_conns: Array = mock_accessibility.settings_changed.get_connections()
	assert_int(settings_conns.size()) \
		.override_failure_message("AC-NEW-04: mock_accessibility.settings_changed doit avoir exactement 1 connection (détecteur double-connect)") \
		.is_equal(1)
	assert_int(int(settings_conns[0].get("flags", 0)) & CONNECT_DEFERRED_FLAG) \
		.override_failure_message("AC-NEW-04: mock_accessibility.settings_changed doit être connecté CONNECT_DEFERRED") \
		.is_equal(CONNECT_DEFERRED_FLAG)

	_free_all(nodes)
