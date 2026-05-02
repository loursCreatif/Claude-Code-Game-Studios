## Préférences utilisateur Input persistées (TR-inp-009, ADR-0014 D-1/D-7).
##
## Path canonique : user://settings/input.tres (ADR-0014 D-2).
## Schéma flat — 6 Tuning Knobs GDD input-system.md + champ versioning interne.
##
## Lifecycle : chargé par InputManager._ready() via SettingsResource.load_or_default
## (ADR-0014 D-5). Sauvegardé sur trigger explicite (Settings menu apply, flush-on-quit).
class_name InputSettings
extends Resource

## Version courante du schéma. Bumper UNIQUEMENT en ajoutant un nouveau champ
## (forward-only migration, ADR-0014 D-3).
const CURRENT_VERSION: int = 1

## Champ versioning serialisé. Préfixe `_` interne, pas un Tuning Knob.
@export var _settings_version: int = CURRENT_VERSION

## Sensibilité souris en rad/pixel. Doit rester aligné avec CameraSettings.mouse_sensitivity
## (Camera propage au boot via setter — voir CameraSystem._ready). Default identique.
@export_range(0.0005, 0.012, 0.0001) var mouse_sensitivity: float = 0.0022

## Inversion axe Y. Aligné avec CameraSettings.mouse_y_inverted.
@export var mouse_y_inverted: bool = false

## Capture souris automatique au boot. false par défaut — la capture est déclenchée
## par GameStateManager au passage Menu → Playing (ADR-0007). Mettre true uniquement
## pour tests dev / single-scene runs.
@export var mouse_capture_at_boot: bool = false

## Fenêtre d'absorption post-FOCUS_IN en millisecondes. Substitue la constante
## FOCUS_REGAIN_WINDOW_USEC (ms × 1000 → µs côté hot path). ADR-0004 D-6.
@export_range(20, 150, 1) var focus_regain_window_ms: int = 50

## Active l'overlay debug F3 au boot (ne change pas la touche, juste la visibilité initiale).
@export var debug_overlay_default: bool = false

## Seuil ms au-delà duquel un sample latence est flagué « anomalie » côté HUD F3.
## Pas une fenêtre de filtrage — simple seuil de coloration / log.
@export_range(0.05, 1.0, 0.01) var latency_anomaly_threshold_ms: float = 0.1


## Factory defaults canonique (ADR-0014 D-7).
static func create_defaults() -> InputSettings:
	var s: InputSettings = InputSettings.new()
	s._settings_version = CURRENT_VERSION
	return s


## Migration forward-only (ADR-0014 D-3). v0/v1 identiques au MVP.
## Bump futur : ajouter ici les transformations par version.
static func migrate_from(version: int, raw: InputSettings) -> InputSettings:
	if version >= CURRENT_VERSION:
		return raw
	push_warning("[input-settings] migrating v%d → v%d" % [version, CURRENT_VERSION])
	raw._settings_version = CURRENT_VERSION
	return raw
