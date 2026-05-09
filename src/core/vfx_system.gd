## VFXSystem — Autoload singleton Presentation layer pour les effets visuels Chrome Ascent.
##
## class_name VFXSystemScript (suffix -Script mandatory — cf. mémoire
## feedback_godot_class_name_autoload_collision — autoload enregistré comme "VFXSystem").
##
## Responsabilités story-001 :
## - Pool pré-alloué 74 nodes au _ready() (8 GPUParticles3D + 64 Decal + 1 Trail + 1 Flash)
## - Un ShaderMaterial UNIQUE partagé entre les 8 particles sang (R-VFX-16 budget draw calls)
## - Connexion upstream signals CONNECT_DEFERRED (R-VFX-3 + ADR-0009 D-4)
## - Stubs handlers no-op pour stories 003-006
##
## Responsabilités story-002 :
## - Handlers combat : _on_swing_started, _on_swing_ended, _on_enemy_killed, _on_respawned
## - Trail katana fade-out exponentiel 100 ms dans _physics_process (R-VFX-7)
## - Blood spurt round-robin pool + reduce_motion cone mult (R-VFX-8 + AC-VFX-12)
## - Decal raycast PhysicsDirectSpaceState3D + skip silencieux EC-VFX-07
## - Flash kill stub WCAG 333 ms guard (story-004 body)
##
## Responsabilités story-005 :
## - Pull AccessibilityService (ADR-0015 D-1 Option A) au boot + live update via settings_changed
## - _accessibility_service_ref injectable pour test mock substitution
## - _pull_accessibility_settings() : guard EC-VFX-08 defaults safe si Service absent
## - _on_accessibility_settings_changed() : body re-pull + apply live mid-swing (AC-NEW-07)
##
## Responsabilités story-006 :
## - GSM visibility gating : freeze pool + trail + flash quand MENU/PAUSED/BOSS_DEFEATED
## - _gsm_ref injectable pour test mock substitution
## - _on_state_changed() : body complet + _apply_visibility_for_state + _freeze_vfx/_restore_vfx
## - _pull_initial_gsm_state() : pull boot ADR-0007 D-9
## - early-out guard if not _is_active dans handlers story-002/004 + _physics_process
##
## ADR-0001 (wall-clock timer Callable injection), ADR-0009 D-2 (pool exclusive),
## ADR-0009 D-4 (CONNECT_DEFERRED), R-VFX-2 (zero-alloc hot path), R-VFX-14 (outbound-only).
## Story-001 : implémentation initiale. Story-002 : combat handlers bodies.
## Story-005 : accessibility pull live update. Story-006 : GSM visibility gating.

class_name VFXSystemScript

extends Node


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Taille du pool de particules sang (GPUParticles3D).
const BLOOD_PARTICLE_POOL_SIZE: int = 8

## Taille du pool de decals au sol.
const DECAL_POOL_SIZE: int = 64

## Nombre max de decals par room avant LRU eviction (story-003).
const MAX_DECALS_PER_ROOM: int = 32

## Durée flash kill en ms (story-004 wall-clock timer).
const FLASH_KILL_DURATION_MS: int = 80

## Durée flash respawn en ms (story-004 wall-clock timer).
const FLASH_RESPAWN_DURATION_MS: int = 50

## Intervalle minimum entre deux flashs (WCAG 333 ms — story-004).
const FLASH_MIN_INTERVAL_MS: int = 333

## Layer CanvasLayer overlay flash (< 100 — GSM owns 100, R-HUD-11 pattern).
const FLASH_OVERLAY_LAYER: int = 60

## Couleur sang pour particles + decals.
const BLOOD_COLOR: Color = Color(0.784, 0.137, 0.173, 1.0)  # #C8232C

## Couleur trail katana.
const TRAIL_COLOR: Color = Color(0.910, 0.910, 0.878, 1.0)  # #E8E8E0

## Nombre de particules par splash sang (cone 30°).
const BLOOD_SPURT_PARTICLE_COUNT: int = 6

## Angle du cone de dispersion des particules sang (degrés).
const BLOOD_CONE_ANGLE_DEG: float = 30.0

## Durée de vie d'une particule sang en ms.
const PARTICLE_LIFETIME_MS: int = 400

## GSM enum states (mirror GameStateManager.State — à confirmer post-GSM autoload boot Sprint A multi-epic).
## MVP : valeurs synchrones avec mock_gsm.gd story-001 (PLAYING = 1).
const STATE_MENU: int = 0
const STATE_PLAYING: int = 1
const STATE_PAUSED: int = 2
const STATE_RESPAWNING: int = 3
const STATE_BOSS_DEFEATED: int = 4

## Distance max du raycast pour projection decal sur surface.
const DECAL_RAYCAST_MAX_DISTANCE: float = 3.0

## Brightness flash blanc nominal (R-VFX-5).
const DEFAULT_FLASH_BRIGHTNESS: float = 1.0

## Brightness flash gris substitute reduce_flash (#A0A0A0 = 0.625) — F-VFX-2.
const REDUCE_FLASH_BRIGHTNESS: float = 0.625

## Opacité max du trail katana (R-VFX-7).
const KATANA_TRAIL_OPACITY_MAX: float = 0.7

## Durée fade-out trail katana en ms (R-VFX-7 exponentiel).
const KATANA_TRAIL_FADE_MS: int = 100

## Multiplicateur cone angle quand reduce_motion actif (AC-VFX-12).
const REDUCE_MOTION_PARTICLE_ANGLE_MULT: float = 0.5

## Multiplicateur opacité trail quand reduce_motion actif.
const REDUCE_MOTION_TRAIL_MULT: float = 0.5

## Directions cardinales pré-allouées pour raycast fallback (R-VFX-2 zero-alloc hot path).
## Évite alloc heap d'un Array literal à chaque call _perform_decal_raycast.
const _RAYCAST_FALLBACK_DIRS: Array[Vector3] = [
	Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK,
]


# ---------------------------------------------------------------------------
# Pool references
# ---------------------------------------------------------------------------

## Pool GPUParticles3D pré-alloués (8 slots round-robin).
var _blood_particle_pool: Array[GPUParticles3D] = []

## Pool Decal pré-alloués (64 slots ring buffer — LRU story-003).
var _decal_pool: Array[Decal] = []

## Trail mesh katana (ImmediateMesh — body story-002).
var _trail_mesh: MeshInstance3D = null

## Material StandardMaterial3D pré-alloué pour le trail (R-VFX-2 zero-alloc hot path).
var _trail_material: StandardMaterial3D = null

## ColorRect overlay flash (body story-004).
var _flash_overlay_rect: ColorRect = null

## ShaderMaterial partagé pour toutes les particles sang (R-VFX-16).
var _blood_shader_material: ShaderMaterial = null


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Index round-robin courant pour le pool particles sang.
var _blood_idx: int = 0

## Write head ring buffer pour le pool decals.
var _decal_write_head: int = 0

## Nombre de decals spawned dans la room courante (LRU guard story-003).
var _room_decal_count: int = 0

## True quand le VFXSystem est actif (false = paused/menu, story-006).
var _is_active: bool = true

## Timestamp du dernier flash émis (WCAG 333 ms guard story-004).
var _flash_last_msec: int = 0

## Reduce motion actif (pull depuis AccessibilityService story-005 — défaut false).
var _reduce_motion: bool = false

## Reduce flash actif (pull depuis AccessibilityService story-005 — défaut false).
var _reduce_flash: bool = false

## Multiplicateur flash brightness (story-005 — défaut 1.0).
var _flash_mult: float = 1.0

## True quand flash kill actif (wall-clock timer en cours dans _physics_process).
var _flash_kill_active: bool = false

## Timestamp démarrage flash kill (0 = pas de flash en cours).
var _flash_kill_start_msec: int = 0

## True si reduce_flash actif au moment du trigger (gris substitute pour la durée du flash).
var _flash_kill_use_grey: bool = false

## True quand flash respawn actif (wall-clock timer en cours).
var _flash_respawn_active: bool = false

## Timestamp démarrage flash respawn (0 = pas de flash en cours).
var _flash_respawn_start_msec: int = 0

## True quand le trail katana est actif (swing en cours OU fade-out).
var _trail_active: bool = false

## Timestamp de démarrage du fade-out trail (0 = pas de fade-out en cours).
var _trail_fade_start_msec: int = 0

## Direction de l'attaque mémorisée depuis swing_started.
var _swing_aim_forward: Vector3 = Vector3.FORWARD

## Dernier cone effectif calculé (testable — AC-VFX-12).
var _last_effective_cone_deg: float = BLOOD_CONE_ANGLE_DEG


# ---------------------------------------------------------------------------
# Wall-clock injection (ADR-0001 + ADR-0006 D-4 pattern)
# ---------------------------------------------------------------------------

## Callable injecté wall-clock — substituable en test.
## `_get_time_msec.call()` → `Time.get_ticks_msec()` (int).
var _get_time_msec: Callable = Time.get_ticks_msec

## Référence injectable AccessibilityService — set par connect_accessibility_signals
## ou _connect_upstream_signals (autoload global fallback). Test injection pattern.
## null = fallback sur `/root/AccessibilityService` en prod.
var _accessibility_service_ref: Node = null

## Référence injectable GSM — set par connect_gsm_signals ou _connect_upstream_signals.
## null = fallback sur `/root/GameStateManager` autoload prod.
var _gsm_ref: Node = null


# ---------------------------------------------------------------------------
# _ready
# ---------------------------------------------------------------------------

func _ready() -> void:
	# ADR-0007 D-4 : PROCESS_MODE_ALWAYS pour recevoir state_changed(PLAYING)
	# DEFERRED même quand SceneTree est paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_blood_shader_material = _create_blood_shader_material()
	_setup_vfx_pool()
	_connect_upstream_signals()
	_pull_accessibility_settings()  # story-005 — pull initial boot ADR-0015 D-1
	_pull_initial_gsm_state()       # story-006 — pull initial GSM state ADR-0007 D-9

	print("[VFXSystem] boot — pool=%d/%d trail=%d flash_layer=%d" % [
		BLOOD_PARTICLE_POOL_SIZE,
		DECAL_POOL_SIZE,
		1 if _trail_mesh != null else 0,
		FLASH_OVERLAY_LAYER,
	])


# ---------------------------------------------------------------------------
# Private — pool setup
# ---------------------------------------------------------------------------

## Instancie tous les nodes VFX au boot. Jamais étendu runtime (R-VFX-2 + ADR-0009 D-2).
func _setup_vfx_pool() -> void:
	# Node parent organisation — garde le scene tree propre.
	var pool_root: Node3D = Node3D.new()
	pool_root.name = &"VFXPool3D"
	add_child(pool_root)

	# 8 × GPUParticles3D sang — ShaderMaterial UNIQUE partagé (R-VFX-16).
	for _i: int in range(BLOOD_PARTICLE_POOL_SIZE):
		var p: GPUParticles3D = GPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.amount = 6
		p.lifetime = 0.4
		# Matériau partagé (même instance — pas duplicate) — R-VFX-16.
		p.process_material = _blood_shader_material
		pool_root.add_child(p)
		_blood_particle_pool.append(p)

	# 64 × Decal sol sang.
	var decal_color: Color = Color(BLOOD_COLOR.r, BLOOD_COLOR.g, BLOOD_COLOR.b, 0.7)
	for _i: int in range(DECAL_POOL_SIZE):
		var d: Decal = Decal.new()
		d.visible = false
		d.modulate = decal_color
		d.size = Vector3(0.6, 0.3, 0.6)
		pool_root.add_child(d)
		_decal_pool.append(d)

	# 1 × MeshInstance3D trail katana + StandardMaterial3D pré-alloué (R-VFX-2 zero-alloc).
	_trail_material = StandardMaterial3D.new()
	_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_material.albedo_color = TRAIL_COLOR

	_trail_mesh = MeshInstance3D.new()
	_trail_mesh.name = &"KatanaTrailMesh"
	_trail_mesh.visible = false
	_trail_mesh.mesh = ImmediateMesh.new()
	_trail_mesh.material_override = _trail_material
	pool_root.add_child(_trail_mesh)

	# 1 × CanvasLayer overlay flash + 1 × ColorRect.
	var flash_layer: CanvasLayer = CanvasLayer.new()
	flash_layer.name = &"VFXFlashOverlay"
	flash_layer.layer = FLASH_OVERLAY_LAYER
	add_child(flash_layer)

	_flash_overlay_rect = ColorRect.new()
	_flash_overlay_rect.name = &"FlashOverlayRect"
	_flash_overlay_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_overlay_rect.visible = false
	flash_layer.add_child(_flash_overlay_rect)


## Crée le ShaderMaterial partagé pour particles sang.
## TODO story-002 : implémenter shader code flat unshaded BLOOD_COLOR + opacity
## fade-out (F-VFX-3 — deferred explicitement au story-002 scope).
## Story-001 : instance vide correctement typée — partagée entre les 8 slots (R-VFX-16).
func _create_blood_shader_material() -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	# TODO story-002: shader = load("res://assets/shaders/blood_particle.gdshader")
	# TODO story-002: ajouter shader_parameter BLOOD_COLOR + opacity fade-out
	return mat


# ---------------------------------------------------------------------------
# Private — upstream signal connections
# ---------------------------------------------------------------------------

## Connecte tous les upstream signals avec CONNECT_DEFERRED (R-VFX-3 + ADR-0009 D-4).
## Guard get_node_or_null pour chaque autoload — résistant aux boot ordering gaps
## et aux test fixtures qui substituent les autoloads réels.
## 8 connexions : Combat (3) + Enemy (1) + Camera (2) + GSM (1) + Accessibility (1).
func _connect_upstream_signals() -> void:
	# Combat signals
	var combat: Node = get_node_or_null("/root/CombatSystem")
	if combat != null:
		if combat.has_signal(&"swing_started") and not combat.swing_started.is_connected(_on_swing_started):
			combat.swing_started.connect(_on_swing_started, CONNECT_DEFERRED)
		if combat.has_signal(&"swing_ended") and not combat.swing_ended.is_connected(_on_swing_ended):
			combat.swing_ended.connect(_on_swing_ended, CONNECT_DEFERRED)
		if combat.has_signal(&"multi_kill") and not combat.multi_kill.is_connected(_on_multi_kill):
			combat.multi_kill.connect(_on_multi_kill, CONNECT_DEFERRED)

	# Enemy signal
	var enemy: Node = get_node_or_null("/root/EnemySystem")
	if enemy != null:
		if enemy.has_signal(&"enemy_killed") and not enemy.enemy_killed.is_connected(_on_enemy_killed):
			enemy.enemy_killed.connect(_on_enemy_killed, CONNECT_DEFERRED)

	# Camera signals (died + respawned — flash triggers story-004)
	var camera: Node = get_node_or_null("/root/CameraSystem")
	if camera != null:
		if camera.has_signal(&"died") and not camera.died.is_connected(_on_died):
			camera.died.connect(_on_died, CONNECT_DEFERRED)
		if camera.has_signal(&"respawned") and not camera.respawned.is_connected(_on_respawned):
			camera.respawned.connect(_on_respawned, CONNECT_DEFERRED)

	# GSM state_changed (visibility gating story-006)
	var gsm: Node = get_node_or_null("/root/GameStateManager")
	if gsm != null:
		_gsm_ref = gsm  # story-006 — store ref pour pull
		if gsm.has_signal(&"state_changed") and not gsm.state_changed.is_connected(_on_state_changed):
			gsm.state_changed.connect(_on_state_changed, CONNECT_DEFERRED)

	# AccessibilityService settings_changed (reduce_flash / reduce_motion story-005)
	var accessibility: Node = get_node_or_null("/root/AccessibilityService")
	if accessibility != null:
		_accessibility_service_ref = accessibility  # story-005 — store ref pour pull
		if accessibility.has_signal(&"settings_changed") and not accessibility.settings_changed.is_connected(_on_accessibility_settings_changed):
			accessibility.settings_changed.connect(_on_accessibility_settings_changed, CONNECT_DEFERRED)


# ---------------------------------------------------------------------------
# Public connection helper (test injection pattern)
# ---------------------------------------------------------------------------

## Permet aux tests d'injecter des mocks à la place des autoloads absents.
## Connecte les signaux depuis un node externe (pattern AudioSystem.connect_combat_signals).
## Idempotent : skip si déjà connecté.
func connect_combat_signals(combat: Node) -> void:
	if combat == null:
		return
	if combat.has_signal(&"swing_started") and not combat.swing_started.is_connected(_on_swing_started):
		combat.swing_started.connect(_on_swing_started, CONNECT_DEFERRED)
	if combat.has_signal(&"swing_ended") and not combat.swing_ended.is_connected(_on_swing_ended):
		combat.swing_ended.connect(_on_swing_ended, CONNECT_DEFERRED)
	if combat.has_signal(&"multi_kill") and not combat.multi_kill.is_connected(_on_multi_kill):
		combat.multi_kill.connect(_on_multi_kill, CONNECT_DEFERRED)


## Injecte un mock Enemy et connecte ses signaux.
func connect_enemy_signals(enemy: Node) -> void:
	if enemy == null:
		return
	if enemy.has_signal(&"enemy_killed") and not enemy.enemy_killed.is_connected(_on_enemy_killed):
		enemy.enemy_killed.connect(_on_enemy_killed, CONNECT_DEFERRED)


## Injecte un mock Camera et connecte ses signaux.
func connect_camera_signals(camera: Node) -> void:
	if camera == null:
		return
	if camera.has_signal(&"died") and not camera.died.is_connected(_on_died):
		camera.died.connect(_on_died, CONNECT_DEFERRED)
	if camera.has_signal(&"respawned") and not camera.respawned.is_connected(_on_respawned):
		camera.respawned.connect(_on_respawned, CONNECT_DEFERRED)


## Injecte un mock GSM et connecte son signal.
## Story-006 : store _gsm_ref + re-pull immédiat post-injection (ADR-0007 D-9).
func connect_gsm_signals(gsm: Node) -> void:
	if gsm == null:
		return
	_gsm_ref = gsm  # story-006 — store ref pour pull
	if gsm.has_signal(&"state_changed") and not gsm.state_changed.is_connected(_on_state_changed):
		gsm.state_changed.connect(_on_state_changed, CONNECT_DEFERRED)
	_pull_initial_gsm_state()  # story-006 — re-pull immédiat post-injection


## Injecte un mock AccessibilityService et connecte son signal.
## Story-005 : set _accessibility_service_ref pour pull + re-pull immédiat post-injection.
func connect_accessibility_signals(accessibility: Node) -> void:
	if accessibility == null:
		return
	_accessibility_service_ref = accessibility  # story-005 — store ref pour pull
	if accessibility.has_signal(&"settings_changed") and not accessibility.settings_changed.is_connected(_on_accessibility_settings_changed):
		accessibility.settings_changed.connect(_on_accessibility_settings_changed, CONNECT_DEFERRED)
	_pull_accessibility_settings()  # story-005 — re-pull immédiat post-injection


# ---------------------------------------------------------------------------
# _physics_process — trail fade-out wall-clock (story-002)
# ---------------------------------------------------------------------------

## Trail fade-out exponentiel 100 ms (R-VFX-7 + AC-VFX-14).
## Calcul wall-clock via _get_time_msec pour résistance Engine.time_scale.
## story-006 : early-out guard si frozen (MENU/PAUSED/BOSS_DEFEATED).
func _physics_process(_delta: float) -> void:
	if not _is_active:
		return  # story-006 — skip trail + flash ticks quand frozen

	if _trail_active and _trail_fade_start_msec > 0:
		var elapsed_ms: int = _get_time_msec.call() - _trail_fade_start_msec
		if elapsed_ms >= KATANA_TRAIL_FADE_MS:
			_trail_mesh.visible = false
			_trail_active = false
			_trail_fade_start_msec = 0
		else:
			var t: float = float(elapsed_ms) / float(KATANA_TRAIL_FADE_MS)
			var opacity: float = KATANA_TRAIL_OPACITY_MAX * exp(-3.0 * t)
			var color: Color = TRAIL_COLOR
			color.a = opacity
			_set_trail_color(color)

	# NEW story-004 — Flash kill wall-clock 80 ms (R-VFX-5 + AC-VFX-06/25)
	if _flash_kill_active:
		var elapsed_kill_ms: int = _get_time_msec.call() - _flash_kill_start_msec
		if elapsed_kill_ms >= FLASH_KILL_DURATION_MS:
			_flash_kill_active = false
			_flash_overlay_rect.visible = _flash_respawn_active  # garde si respawn en cours
		else:
			var t_kill: float = float(elapsed_kill_ms) / float(FLASH_KILL_DURATION_MS)
			_apply_flash_kill_color(t_kill)

	# NEW story-004 — Flash respawn wall-clock 50 ms binaire pop (R-VFX-15 + AC-VFX-09/15)
	if _flash_respawn_active:
		var elapsed_respawn_ms: int = _get_time_msec.call() - _flash_respawn_start_msec
		if elapsed_respawn_ms >= FLASH_RESPAWN_DURATION_MS:
			_flash_respawn_active = false
			_flash_overlay_rect.visible = _flash_kill_active  # garde si kill en cours
		# 50 ms = pop binaire, pas de fade interpolé MVP (R-VFX-15)


# ---------------------------------------------------------------------------
# Signal handlers — stories 002-006
# ---------------------------------------------------------------------------

## Handler swing_started (Combat) — story-002.
## Active le trail katana ImmediateMesh avec opacité max (R-VFX-7 + AC-VFX-13).
func _on_swing_started(direction: Vector3 = Vector3.ZERO) -> void:
	if not _is_active:
		return
	_swing_aim_forward = direction.normalized()
	_trail_active = true
	_trail_fade_start_msec = 0
	_trail_mesh.visible = true
	var trail_color: Color = TRAIL_COLOR
	trail_color.a = KATANA_TRAIL_OPACITY_MAX * (REDUCE_MOTION_TRAIL_MULT if _reduce_motion else 1.0)
	_set_trail_color(trail_color)


## Handler swing_ended (Combat) — story-002.
## Déclenche le fade-out exponentiel 100 ms du trail (R-VFX-7 + AC-VFX-14).
## Le fade est géré dans _physics_process.
## story-006 : ignoré si frozen — trail déjà cleared par _freeze_vfx.
func _on_swing_ended() -> void:
	if not _is_active or not _trail_active:
		return
	_trail_fade_start_msec = _get_time_msec.call()


## Handler multi_kill (Combat) — no-op MVP.
## R-VFX-10 : burst additif déjà couvert par enemy_killed séquentiels.
func _on_multi_kill(_count: int = 0) -> void:
	pass


## Handler enemy_killed (Enemy) — story-002.
## CRITIQUE ADR-0006 D-3 / R-AUD-7 : utiliser `position` parameter EXCLUSIVEMENT.
## Jamais `enemy.global_position` — enemy peut être queue_free post-DEFERRED.
func _on_enemy_killed(_enemy: Node = null, position: Vector3 = Vector3.ZERO) -> void:
	if not _is_active:
		return
	_spawn_blood_spurt(position)
	_spawn_decal_on_surface(position)
	_trigger_flash_kill()


## Handler died (Camera) — story-004.
## Déclenche le flash kill 80 ms wall-clock + WCAG 333 ms guard (R-VFX-5 + AC-VFX-06).
func _on_died() -> void:
	if not _is_active:
		return
	_trigger_flash_kill()


## Handler respawned (Camera) — story-002+004.
## AC-VFX-22 : reset complet pool blood + trail + decals dans le même frame.
## Story-004 : ajoute trigger flash respawn 50 ms (R-VFX-15 + AC-VFX-09).
## Note ordre : restart() en GPUParticles3D one_shot remet emitting=true → on force false après.
func _on_respawned(_position: Vector3 = Vector3.ZERO) -> void:
	for p: GPUParticles3D in _blood_particle_pool:
		p.restart()
		p.emitting = false
	_trail_mesh.visible = false
	_trail_active = false
	_trail_fade_start_msec = 0
	for d: Decal in _decal_pool:
		d.visible = false
	_room_decal_count = 0
	_decal_write_head = 0

	# NEW story-004 — Trigger flash respawn (skip si reduce_flash via R-VFX-15 guard)
	_trigger_flash_respawn()


## Handler state_changed (GSM) — story-006.
## R-VFX-12 + ADR-0007 D-2 : freeze pool + trail + flash overlay si MENU/PAUSED/BOSS_DEFEATED ;
## restore process_mode si retour PLAYING (AC-VFX-17).
func _on_state_changed(new_state: int = 0) -> void:
	_apply_visibility_for_state(new_state)


## Handler settings_changed (AccessibilityService) — story-005.
## Re-pull live + apply update mid-swing si reduce_motion changé (R-VFX-11 + AC-NEW-07).
## Note : flash en cours non rétroactif (durée 80 ms trop courte) — AC-VFX-20 next flash.
func _on_accessibility_settings_changed() -> void:
	var prev_reduce_motion: bool = _reduce_motion
	_pull_accessibility_settings()

	# AC-NEW-07 — apply live update mid-swing si reduce_motion changé
	if _trail_active and prev_reduce_motion != _reduce_motion:
		var trail_color: Color = TRAIL_COLOR
		trail_color.a = KATANA_TRAIL_OPACITY_MAX * (REDUCE_MOTION_TRAIL_MULT if _reduce_motion else 1.0)
		_set_trail_color(trail_color)


# ---------------------------------------------------------------------------
# Private helpers — story-005
# ---------------------------------------------------------------------------

## Pull les settings AccessibilityService (R-VFX-5/11/15 + ADR-0015 D-1 Option A).
## Guard EC-VFX-08 : defaults safe si Service non initialisé OU mock absent.
## Lit depuis _accessibility_service_ref (test mock) OU autoload global fallback.
## Utilise les methods canoniques du service (cohérent avec accessibility_service.gd).
func _pull_accessibility_settings() -> void:
	var svc: Node = _accessibility_service_ref
	if svc == null:
		# Fallback autoload global (prod)
		svc = get_node_or_null("/root/AccessibilityService")
	if not is_instance_valid(svc):
		# Defaults safe — corrigés par settings_changed live dès Service prêt
		_reduce_flash = false
		_flash_mult = 1.0
		_reduce_motion = false
		push_warning("VFX: AccessibilityService not yet initialized at pull — using defaults")
		return

	# Pull via methods canoniques (real service + mock délègue properties)
	if svc.has_method(&"is_reduce_flash_enabled"):
		_reduce_flash = svc.is_reduce_flash_enabled()
	if svc.has_method(&"get_flash_mult"):
		_flash_mult = svc.get_flash_mult()
	if svc.has_method(&"is_reduce_motion_enabled"):
		_reduce_motion = svc.is_reduce_motion_enabled()


# ---------------------------------------------------------------------------
# Private helpers — story-006
# ---------------------------------------------------------------------------

## Applique la matrice visibilité ADR-0007 D-2 :
## PLAYING + RESPAWNING → VFX actif ; MENU + PAUSED + BOSS_DEFEATED → freeze.
## Détecte transition (was_active != _is_active) pour appel freeze/restore.
func _apply_visibility_for_state(state: int) -> void:
	var was_active: bool = _is_active
	_is_active = (state == STATE_PLAYING or state == STATE_RESPAWNING)
	if not _is_active:
		_freeze_vfx()
	elif not was_active:  # transition false → true (PLAYING/RESPAWNING return)
		_restore_vfx()


## Freeze pool VFX (R-VFX-12 + AC-VFX-15/16).
## - GPUParticles3D : emitting=false + process_mode=PROCESS_MODE_DISABLED
## - Trail : visible=false + _trail_active=false + _trail_fade_start_msec=0
## - Flash overlay : visible=false + _flash_kill_active=false + _flash_respawn_active=false
## - Decals : restent visibles (mémoire physique salle Pillar 2 — reset par respawn story-003 only).
func _freeze_vfx() -> void:
	for p: GPUParticles3D in _blood_particle_pool:
		p.emitting = false
		p.process_mode = Node.PROCESS_MODE_DISABLED

	_trail_mesh.visible = false
	_trail_active = false
	_trail_fade_start_msec = 0

	_flash_overlay_rect.visible = false
	_flash_kill_active = false
	_flash_respawn_active = false
	_flash_kill_start_msec = 0
	_flash_respawn_start_msec = 0


## Restore pool VFX au retour PLAYING (R-VFX-12 + AC-VFX-17).
## process_mode restauré INHERIT ; trail Idle (pas orphelin) ; flash overlay prêt.
## emitting reste false (sera re-trigger par prochain enemy_killed via handlers).
func _restore_vfx() -> void:
	for p: GPUParticles3D in _blood_particle_pool:
		p.process_mode = Node.PROCESS_MODE_INHERIT

	_trail_mesh.visible = false
	_trail_active = false
	_flash_overlay_rect.visible = false


## Pull initial GSM state au boot (ADR-0007 D-9 pull pattern).
## Guard EC : si GSM non initialisé OU pas de get_current_state, default PLAYING.
func _pull_initial_gsm_state() -> void:
	var svc: Node = _gsm_ref
	if svc == null:
		svc = get_node_or_null("/root/GameStateManager")
	if not is_instance_valid(svc):
		# GSM autoload Not Started — default PLAYING (mitigation MVP)
		_is_active = true
		push_warning("VFX: GSM not available at pull — defaulting _is_active = true (PLAYING assumption)")
		return

	if svc.has_method(&"get_current_state"):
		var initial_state: int = svc.get_current_state()
		_apply_visibility_for_state(initial_state)
	else:
		_is_active = true  # default safe


# ---------------------------------------------------------------------------
# Private helpers — story-002
# ---------------------------------------------------------------------------

## Spawn un slot blood spurt depuis le pool round-robin.
## Applique reduce_motion mult sur cone angle (AC-VFX-12).
func _spawn_blood_spurt(position: Vector3) -> void:
	var slot: GPUParticles3D = _blood_particle_pool[_blood_idx]
	slot.global_position = position
	slot.emitting = false
	slot.restart()
	slot.emitting = true

	var effective_cone_deg: float = BLOOD_CONE_ANGLE_DEG
	if _reduce_motion:
		effective_cone_deg *= REDUCE_MOTION_PARTICLE_ANGLE_MULT
	_last_effective_cone_deg = effective_cone_deg
	# TODO story-002 polish : appliquer effective_cone_deg sur ParticleProcessMaterial.spread
	# (ParticleProcessMaterial non assigné au MVP — ShaderMaterial sans spread param).

	_blood_idx = (_blood_idx + 1) % BLOOD_PARTICLE_POOL_SIZE


## Projette un decal sur la surface la plus proche via raycast.
## Skip silencieux + push_warning si aucune surface trouvée (EC-VFX-07).
func _spawn_decal_on_surface(position: Vector3) -> void:
	var surface_pos: Vector3 = _perform_decal_raycast(position)
	if surface_pos == Vector3.INF:
		push_warning("VFX: no surface found for decal at %s" % position)
		return
	var slot: Decal = _decal_pool[_decal_write_head % DECAL_POOL_SIZE]
	slot.global_position = surface_pos
	slot.visible = true
	_decal_write_head += 1
	_room_decal_count = mini(_room_decal_count + 1, MAX_DECALS_PER_ROOM)


## Raycast vers le sol puis vers les murs pour trouver la surface de projection decal.
## Retourne Vector3.INF si aucune surface trouvée dans DECAL_RAYCAST_MAX_DISTANCE.
func _perform_decal_raycast(from_position: Vector3) -> Vector3:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector3.INF
	var world: World3D = viewport.world_3d
	if world == null:
		return Vector3.INF
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if space_state == null:
		return Vector3.INF

	# Priorité : sol (Vector3.DOWN)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from_position,
		from_position + Vector3.DOWN * DECAL_RAYCAST_MAX_DISTANCE
	)
	var result: Dictionary = space_state.intersect_ray(query)

	# Fallback : murs (4 directions cardinales) — itère constante pré-allouée (R-VFX-2)
	if result.is_empty():
		for dir: Vector3 in _RAYCAST_FALLBACK_DIRS:
			query = PhysicsRayQueryParameters3D.create(
				from_position,
				from_position + dir * DECAL_RAYCAST_MAX_DISTANCE
			)
			result = space_state.intersect_ray(query)
			if not result.is_empty():
				break

	if result.is_empty():
		return Vector3.INF

	return result["position"] as Vector3


## Flash kill 80 ms wall-clock + WCAG 333 ms plancher 3 Hz guard (R-VFX-5/13 + AC-VFX-06/08).
## reduce_flash → fondu gris #A0A0A0 substitute (R-VFX-5 + AC-VFX-07 + F-VFX-2).
## story-006 : early-out guard si frozen (MENU/PAUSED/BOSS_DEFEATED).
func _trigger_flash_kill() -> void:
	if not _is_active:
		return
	var now: int = _get_time_msec.call()
	if now - _flash_last_msec < FLASH_MIN_INTERVAL_MS:
		push_warning("VFX: flash rate guard triggered — skip flash kill (last=%d, now=%d, delta=%d ms)" % [
			_flash_last_msec, now, now - _flash_last_msec
		])
		return
	_flash_last_msec = now
	_flash_kill_active = true
	_flash_kill_start_msec = now
	_flash_kill_use_grey = _reduce_flash
	_flash_overlay_rect.visible = true
	_apply_flash_kill_color(0.0)  # t = 0 → opacity max


## Applique la couleur flash kill au tick `t` ∈ [0, 1] (0 = début, 1 = fin).
## Gère reduce_flash gris substitute via _flash_kill_use_grey (F-VFX-2).
## Fade-out linéaire alpha 1.0 → 0.0 sur 80 ms wall-clock.
##
## TODO MVP scope : `_flash_mult` continu (pullé story-005) non consommé ici —
## brightness binaire 0.625 (gris) / 1.0 (blanc) suffit MVP. Si interpolation continue
## requise post-MVP (F-VFX-2 spec drift), utiliser `_flash_mult` au lieu de
## REDUCE_FLASH_BRIGHTNESS — story-007 polish ou enhancement future.
func _apply_flash_kill_color(t: float) -> void:
	var base_brightness: float = REDUCE_FLASH_BRIGHTNESS if _flash_kill_use_grey else DEFAULT_FLASH_BRIGHTNESS
	var alpha: float = 1.0 - t
	_flash_overlay_rect.color = Color(base_brightness, base_brightness, base_brightness, alpha)


## Flash respawn 50 ms blanc pur (R-VFX-15 + AC-VFX-09).
## reduce_flash → flash supprimé entièrement (pas de substitut gris — durée 50 ms trop courte).
## story-006 : early-out guard si frozen (MENU/PAUSED/BOSS_DEFEATED).
func _trigger_flash_respawn() -> void:
	if not _is_active:
		return
	if _reduce_flash:
		return  # AC-VFX-09 — zéro flash respawn si reduce_flash ON
	var now: int = _get_time_msec.call()
	_flash_respawn_active = true
	_flash_respawn_start_msec = now
	_flash_overlay_rect.visible = true
	_flash_overlay_rect.color = Color(DEFAULT_FLASH_BRIGHTNESS, DEFAULT_FLASH_BRIGHTNESS, DEFAULT_FLASH_BRIGHTNESS, 1.0)


## Applique une couleur (avec alpha) sur le trail mesh via le material pré-alloué.
## Renommé `_set_trail_color` (au lieu de `_set_trail_modulate`) — MeshInstance3D
## est un Node3D (pas CanvasItem), donc pas de `.modulate`. _trail_material
## (StandardMaterial3D) pré-alloué dans _setup_vfx_pool (R-VFX-2 zero-alloc hot path).
func _set_trail_color(color: Color) -> void:
	_trail_material.albedo_color = color
