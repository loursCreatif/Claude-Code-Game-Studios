## Resource typé pour les préférences d'accessibilité.
## ADR-0015 D-2 : persistance déléguée ADR-0014 (helper SettingsResource).
## Path canonique : user://settings/accessibility.tres.
##
## Schema versionné via _settings_version (ADR-0014 D-3 forward-only migration).
## Defaults safe (D-5 invariant) : tous false / 1.0 / 0 (sentinelle "no override")
## → comportement bit-identique MVP non-accessibility.
class_name AccessibilitySettings
extends Resource

const CURRENT_VERSION: int = 1

@export var _settings_version: int = CURRENT_VERSION

## MVP boolean toggle — atténuation globale motion (camera tilt + FOV kick + shake + slow-mo + enemy death tween).
@export var reduce_motion: bool = false

## MVP boolean toggle — atténuation flash VFX (impact futur VFX system + Combat hit feedback).
@export var reduce_flash: bool = false

## Combat story-022 — multiplier slow-mo scale (1.0 = full slow-mo, 3.33 ≈ disabled).
@export_range(1.0, 3.33, 0.01) var slow_mo_scale_mult: float = 1.0

## Combat story-022 — toggle complet désactivation slow-mo (skip Engine.time_scale mutation).
@export var disable_slow_mo: bool = false

## VFX/Combat — atténuation flash alpha (0.0 = no flash, 1.0 = full).
@export_range(0.0, 1.0, 0.01) var flash_mult: float = 1.0

## Camera Rule 14 — tilt multiplier (computed × 0.25 si reduce_motion).
@export_range(0.0, 1.0, 0.01) var tilt_mult: float = 1.0

## Camera Rule 14 — FOV kick multiplier (computed × 0.5 si reduce_motion).
@export_range(0.0, 1.0, 0.01) var fov_kick_mult: float = 1.0

## Camera Rule 14 — shake multiplier (computed × 0.0 si reduce_motion = force 0).
@export_range(0.0, 1.0, 0.01) var shake_mult: float = 1.0

## Enemy `DEATH_TWEEN_DURATION_MS` override (0 = sentinelle "use default", computed
## retombe sur 150 ms ou 400 ms si reduce_motion).
@export_range(0, 600, 10) var enemy_death_tween_ms_override: int = 0


## Factory : Resource avec tous defaults safe (D-5 invariant garanti).
static func create_defaults() -> AccessibilitySettings:
	return AccessibilitySettings.new()


## Migration forward-only ADR-0014 D-3.
## v0 (legacy) → v1 (CURRENT) : remap simple, `_settings_version` rebadgé.
## Si version >= CURRENT, retourne raw inchangé.
static func migrate_from(version: int, raw: AccessibilitySettings) -> AccessibilitySettings:
	if version >= CURRENT_VERSION:
		return raw
	push_warning("[accessibility-settings] migrating v%d → v%d" % [version, CURRENT_VERSION])
	raw._settings_version = CURRENT_VERSION
	return raw
