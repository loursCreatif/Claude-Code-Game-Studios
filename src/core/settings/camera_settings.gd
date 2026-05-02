## Préférences utilisateur Camera persistées (TR-cam-006, ADR-0014 D-1/D-7).
##
## Path canonique : user://settings/camera.tres (ADR-0014 D-2).
## Schéma flat — 3 Tuning Knobs GDD camera-system.md + champ versioning interne.
##
## Lifecycle : chargé par CameraSystem._ready() via SettingsResource.load_or_default
## (ADR-0014 D-5). Sauvegardé sur trigger explicite (Settings menu apply, flush-on-quit).
class_name CameraSettings
extends Resource

## Version courante du schéma. Bumper UNIQUEMENT en ajoutant un nouveau champ
## (forward-only migration, ADR-0014 D-3). Lors du bump, étendre `migrate_from`
## pour remplir le nouveau champ avec son default lors du chargement d'une v ancienne.
const CURRENT_VERSION: int = 1

## Champ versioning serialisé. Préfixe `_` cohérent avec ADR-0010 R-SAV-version
## (interne, pas un Tuning Knob). Lu par SettingsResource.load_or_default pour migration.
@export var _settings_version: int = CURRENT_VERSION

## Sensibilité souris en rad/pixel. Plage ADR-0014 / GDD camera-system Tuning Knobs.
## Hot-reload runtime via CameraSystem (Camera propage à InputManager au boot).
@export_range(0.0005, 0.012, 0.0001) var mouse_sensitivity: float = 0.0022

## Inversion axe Y. false = pousser souris vers le haut → caméra monte.
@export var mouse_y_inverted: bool = false

## Offset utilisateur appliqué à BASE_FOV (degrés). Range +/- 15° autour de 90°.
## Camera applique au boot (CameraSystem._ready()).
@export_range(-15.0, 15.0, 0.1) var fov_user_offset: float = 0.0


## Factory defaults canonique (ADR-0014 D-7). Source unique de vérité pour les
## valeurs par défaut — utilisé par SettingsResource.load_or_default + tests.
static func create_defaults() -> CameraSettings:
	var s: CameraSettings = CameraSettings.new()
	s._settings_version = CURRENT_VERSION
	return s


## Migration forward-only (ADR-0014 D-3). v0/v1 sont identiques au MVP — la table
## ne fait que stamper `_settings_version` au CURRENT_VERSION.
##
## Lors d'un futur bump (ex : v2 ajoute `look_smoothing`), ajouter ici :
##     if version == 1:
##         raw.look_smoothing = 0.0  # default v2
##         raw._settings_version = 2
##         push_warning("[camera-settings] migrating v1 → v2")
##
## Retourner null pour signaler une migration impossible (helper retombera sur defaults).
static func migrate_from(version: int, raw: CameraSettings) -> CameraSettings:
	if version >= CURRENT_VERSION:
		return raw
	push_warning("[camera-settings] migrating v%d → v%d" % [version, CURRENT_VERSION])
	raw._settings_version = CURRENT_VERSION
	return raw
