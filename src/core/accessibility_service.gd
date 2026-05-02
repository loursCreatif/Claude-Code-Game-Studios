## Autoload single-source-of-truth des préférences d'accessibilité.
## ADR-0015 D-1 : autoload position #5 dans project.godot [autoload].
## class_name suffixé -Script pour éviter collision avec autoload identifier.
##
## API pull-pattern (ADR-0015 D-3) : consumers lisent au _ready() via 7 typed
## getters + reconnect signal `settings_changed` pour live update mid-game.
## Persistance déléguée ADR-0014 via SettingsResource.
## Bornes clampées service-level (D-7) — consumers ne re-clampent pas.
## Defaults invariant garanti (D-5) — tous flags OFF → comportement identique
## MVP non-accessibility.
## Outbound-zero (D-8) — aucune référence consumer (Camera/Combat/Movement/
## Enemy/VFX/HUD).
class_name AccessibilityServiceScript
extends Node

## Émis sur toute mutation des settings (apply_settings ou reload).
signal settings_changed

## Bornes ADR-0015 D-7 (service-level clamping).
const SLOW_MO_SCALE_MULT_MIN: float = 1.0
const SLOW_MO_SCALE_MULT_MAX: float = 3.33
const FLASH_MULT_MIN: float = 0.0
const FLASH_MULT_MAX: float = 1.0

## Camera GDD Rule 14 multipliers reduce_motion (D-3 / D-7).
const REDUCE_MOTION_TILT_MULT: float = 0.25
const REDUCE_MOTION_FOV_KICK_MULT: float = 0.5
const REDUCE_MOTION_SHAKE_MULT: float = 0.0

## Enemy `DEATH_TWEEN_DURATION_MS` defaults (D-3).
const DEFAULT_DEATH_TWEEN_MS: int = 150
const REDUCE_MOTION_DEATH_TWEEN_MS: int = 400

## Settings Resource chargé au _ready() (private — mutation via apply_settings()).
var _settings: AccessibilitySettings = null

## Test hook (cohérent ADR-0014 pattern camera_settings/input_settings)
## permet aux tests de skipper le auto-load filesystem au boot.
var suppress_settings_load: bool = false


## Boot : charge settings via helper ADR-0014, applique OR-merge OS bridge.
func _ready() -> void:
	if suppress_settings_load:
		return
	_load_settings()


## Charge ou crée defaults via helper SettingsResource (ADR-0014 D-3/D-4).
## Applique OR-merge OS bridge (ADR-0015 D-6).
func _load_settings() -> void:
	_settings = SettingsResource.load_or_default(
		"accessibility",
		Callable(AccessibilitySettings, "create_defaults"),
		Callable(AccessibilitySettings, "migrate_from"),
	) as AccessibilitySettings
	_apply_os_bridge()


## OR-merge `OS.is_reduce_motion_enabled()` (Godot 4.5+ AccessKit) avec user toggle.
## Sémantique : OS=true OR user=true → reduce_motion=true. Jamais downgrade.
## Fallback gracieux si OS API absente (Godot < 4.5 théorique, OS non-AccessKit).
## ADR-0015 D-6.
func _apply_os_bridge() -> void:
	if _settings == null:
		return
	# OS.call(...) bypass static type-check du parser Godot 4.6 (méthode résolue
	# dynamiquement, présente avec AccessKit 4.5+ sur plateformes supportées).
	if OS.has_method("is_reduce_motion_enabled") and bool(OS.call("is_reduce_motion_enabled")):
		_settings.reduce_motion = true


## Lecture O(1) du flag global reduce_motion (effective post-OR-merge).
func is_reduce_motion_enabled() -> bool:
	return _settings.reduce_motion if _settings != null else false


## Lecture O(1) du flag reduce_flash.
func is_reduce_flash_enabled() -> bool:
	return _settings.reduce_flash if _settings != null else false


## Combat story-022 — toggle disable slow-mo complet.
func get_disable_slow_mo() -> bool:
	return _settings.disable_slow_mo if _settings != null else false


## Combat story-022 — multiplier slow-mo, clampé [1.0, 3.33] (D-7).
func get_slow_mo_scale_mult() -> float:
	if _settings == null:
		return 1.0
	return clampf(_settings.slow_mo_scale_mult, SLOW_MO_SCALE_MULT_MIN, SLOW_MO_SCALE_MULT_MAX)


## VFX/Combat flash alpha multiplier, clampé [0.0, 1.0] (D-7).
func get_flash_mult() -> float:
	if _settings == null:
		return 1.0
	return clampf(_settings.flash_mult, FLASH_MULT_MIN, FLASH_MULT_MAX)


## Camera Rule 14 — tilt multiplier computed (× 0.25 si reduce_motion).
func get_camera_tilt_mult() -> float:
	if _settings == null:
		return 1.0
	if _settings.reduce_motion:
		return clampf(_settings.tilt_mult * REDUCE_MOTION_TILT_MULT, 0.0, 1.0)
	return clampf(_settings.tilt_mult, 0.0, 1.0)


## Camera Rule 14 — FOV kick multiplier computed (× 0.5 si reduce_motion).
func get_camera_fov_kick_mult() -> float:
	if _settings == null:
		return 1.0
	if _settings.reduce_motion:
		return clampf(_settings.fov_kick_mult * REDUCE_MOTION_FOV_KICK_MULT, 0.0, 1.0)
	return clampf(_settings.fov_kick_mult, 0.0, 1.0)


## Camera Rule 14 — shake multiplier computed (× 0.0 si reduce_motion = force 0).
func get_camera_shake_mult() -> float:
	if _settings == null:
		return 1.0
	if _settings.reduce_motion:
		return clampf(_settings.shake_mult * REDUCE_MOTION_SHAKE_MULT, 0.0, 1.0)
	return clampf(_settings.shake_mult, 0.0, 1.0)


## Enemy `DEATH_TWEEN_DURATION_MS` computed.
## Override Tier 2+ (>0) prime sur derived rule. Sinon 150 ms ou 400 ms si reduce_motion.
func get_enemy_death_tween_ms() -> int:
	if _settings == null:
		return DEFAULT_DEATH_TWEEN_MS
	if _settings.enemy_death_tween_ms_override > 0:
		return _settings.enemy_death_tween_ms_override
	return REDUCE_MOTION_DEATH_TWEEN_MS if _settings.reduce_motion else DEFAULT_DEATH_TWEEN_MS


## Mutation API — Settings Menu Tier 2+ ou QA debug (ADR-0015 D-3/D-10).
## Émet `settings_changed` pour propagation pull-pattern downstream.
func apply_settings(new_settings: AccessibilitySettings) -> void:
	_settings = new_settings
	settings_changed.emit()


## Save trigger explicite (ADR-0015 D-10 — pas de save automatique en _process).
## Délégué helper SettingsResource (ADR-0014).
func save_settings() -> Error:
	if _settings == null:
		return ERR_UNCONFIGURED
	return SettingsResource.save(_settings, "accessibility")
