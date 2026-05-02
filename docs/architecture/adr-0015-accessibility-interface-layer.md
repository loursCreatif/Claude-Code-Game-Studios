# ADR-0015: Accessibility Interface Layer

## Status

Accepted (créée et promue 2026-05-02 par Martin — débloque combat story-022 + couvre TR-mov-008 G-4 + TR-cmb-016 ; phase Polish P3 hors Sprint 1 critical path, MVP `reduce_motion` boolean obligatoire — floor accessibility évite exclusion 15-25 % public motion-sensitive).

## Date

2026-05-02

## Last Verified

2026-05-02

## Decision Makers

- Architecture authority (technical-director équivalent)
- godot-specialist (Engine Compatibility validation Godot 4.6 + AccessKit 4.5+)
- accessibility-specialist (mapping WCAG 2.3.1/2.3.3, défauts safe ranges)

## Summary

Cette ADR ratifie l'architecture de propagation des préférences d'accessibilité (`reduce_motion`, `reduce_flash`, dérivés per-system) entre Movement / Camera / Combat / VFX / Enemy / HUD. Décision : **autoload `AccessibilityService`** (single-source-of-truth, pub-sub via signal `settings_changed`), **persistance déléguée à ADR-0014** (`accessibility_settings.tres` typé Resource), **API pull-pattern** consommée au `_ready()` de chaque consumer + reconnect via signal pour live update, **bridge OS** via `OS.is_reduce_motion_enabled()` (Godot 4.5+ AccessKit) OR-mergé avec toggle utilisateur, **defaults invariant** garantissant comportement identique MVP non-accessibility quand toutes les toggles sont OFF.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core (autoload service + UI accessibility bridge) |
| **Knowledge Risk** | MEDIUM — `OS.is_reduce_motion_enabled()` (4.5+ AccessKit, post-cutoff May 2025). Vérification : `docs/engine-reference/godot/breaking-changes.md` + `current-best-practices.md` confirment Control nodes intègrent AccessKit 4.5+. Fallback gracieux si l'OS ne supporte pas le flag (méthode retourne `false` par défaut hors Windows/macOS récent — comportement documenté Godot). |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md` (4.6 baseline, 4.5 Accessibility AccessKit), `docs/engine-reference/godot/breaking-changes.md` (4.5 accessibility note), `docs/engine-reference/godot/current-best-practices.md` §54 (Control + AccessKit), ADR-0014 (settings persistence pattern délégué), ADR-0005 D-10 (outbound-only pattern Movement applicable services), GDD camera-system.md Rule 14 + AC-CAM-70/71/72, GDD player-combat-system.md AC-CMB-19 r6 + Section G accessibility, GDD player-movement-system.md §accessibility (`reduce_motion`/`reduce_flash`), GDD enemy-system.md `DEATH_TWEEN_DURATION_MS` reduce_motion variant, GDD hud-system.md OQ-HUD-6, GDD menu-system.md §AccessibilityManager Tier 2+. |
| **Post-Cutoff APIs Used** | `OS.is_reduce_motion_enabled()` (4.5+) — utilisée en lecture only, jamais write. Fallback : si la méthode retourne `false` par construction (OS non supporté), MVP reste fonctionnel via toggle utilisateur user-driven. Aucune dépendance `@abstract`, variadic args, shader baker, SMAA — tous indépendants. |
| **Verification Required** | (1) AC-CAM-70/71/72 camera reduce_motion (tilt × 0.25, FOV kick × 0.5, shake × 0). (2) AC-CMB-19 r6 + story-022 ACs combat (disable_slow_mo, slow_mo_scale_mult [1.0, 3.33], flash_mult [0.0, 1.0]). (3) `OS.is_reduce_motion_enabled()` OR-merge avec toggle utilisateur (test : OS=on + user=off → reduce_motion effective true). (4) Defaults invariant : toutes flags OFF → comportement identique MVP non-accessibility (cross-system test). (5) Live update : `settings_changed` signal reçu mid-game change comportement next-tick (prochaine entrée WallRunning/dash/kill). |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0014 (persistance `.tres` typé via helper `SettingsResource` — accessibility settings réutilisent ce pattern, pas de divergence). ADR-0007 (autoload ordering — `AccessibilityService` ajouté position #5, après InputManager/GSM/SaveLoad/Logger ; lu par Camera + Combat + Movement + VFX consumers downstream). |
| **Enables** | Combat story-022 (`reduce_motion` impact Combat — slow-mo + flash) ; Camera AC-CAM-70/71/72 (déjà présents GDD r2, branche `if reduce_motion:` finalement câblée à `AccessibilityService`) ; Enemy `DEATH_TWEEN_DURATION_MS` reduce_motion variant ; Future VFX flash mult ; Future HUD pulse disable Tier 3 (OQ-HUD-6) ; Menu Settings UI Tier 2+ accessibility section. |
| **Blocks** | Combat story-022 (Status Blocked → Ready une fois Accepted). Combat stories 010-012 + 019-022 RESTENT Blocked uniquement par leurs blockers respectifs (Gap 1 MockEnemy / Gap 2 ShapeCast empirical / Gap 5 playtest protocol / Audio System GDD / VFX System GDD) — cette ADR débloque uniquement le sous-ensemble accessibility (story-022). Camera Rule 14 ACs déjà présents GDD r2 — implémentation gameplay déjà câble `if reduce_motion:` via flag local ; ADR ratifie comment `reduce_motion` traverse depuis settings jusqu'au consumer. |
| **Ordering Note** | Cette ADR est **Polish P3** non-MVP (toggles MVP minimal `reduce_motion` boolean obligatoire — accessibility floor — déployable en parallèle Sprint 1 sans bloquer combat/level/menu). N'affecte PAS critical path Sprint 1 (combat 001-009 + 013-018). Débloque uniquement les ACs accessibility-spécifiques. |

## Context

### Problem Statement

Les GDDs Movement / Camera / Combat / Enemy / HUD référencent **chacun** une variable `reduce_motion` (et `reduce_flash` pour VFX/Combat) sans qu'aucun ADR ne formalise :

1. **Ownership** : où vit la valeur source-of-truth ? `InputManager.reduce_motion` (camera GDD r2 le suggère provisoirement) ou un service dédié ? Camera + Combat + Movement + VFX référencent tous différemment dans leurs GDDs.
2. **Persistance** : 1 seul fichier `accessibility_settings.tres` ou éparpillé entre `camera_settings.tres` / `input_settings.tres` ? Si éparpillé, comment garder la cohérence (toggle global qui touche 4 fichiers à la fois) ?
3. **Propagation** : push (service notifie consumers via signal) ou pull (consumer lit au boot + reconnect signal) ? Live update mid-game requis (story-022 AC-4) ou seulement au boot ?
4. **Bridge OS** : `OS.is_reduce_motion_enabled()` (Godot 4.5+ AccessKit) — utilisé ? Quelle priorité face au toggle utilisateur (OR-merge / override / ignore) ?
5. **Defaults invariant** : quand toutes les toggles sont OFF (default), le code accessibility-aware doit produire **exactement** le même comportement que le MVP non-accessibility — comment garantir cette invariance par construction (vs en bricolage par tests) ?
6. **Bornes/clamping** : story-022 AC-5 demande clamp `reduce_motion_slow_mo_scale_mult ∈ [1.0, 3.33]`. Service-level clamp ou consumer-level ? Si service-level, consumers n'ont pas à se défendre.

Sans cette ADR, chaque story (combat-022, camera Rule 14, future VFX flash) trancherait indépendamment ces 6 décisions, créant 4 implémentations divergentes (camera lit `InputManager.reduce_motion`, combat instancie son propre `_reduce_motion_disable_slow_mo` flag, enemy hardcoderait), incohérence cross-system, et coût refactor élevé Tier 2+ quand le Settings Menu sera branché. L'ADR fixe le pattern une seule fois et le rend opposable cross-system via forbidden patterns registry.

### Current State

- ADR-0014 ratifie persistance settings via Resource (.tres) typé + helper `SettingsResource` zero-autoload. Pattern réutilisable mais ne couvre pas la propagation cross-system live (settings sont "passifs" : lus 1 fois au boot par leur owner).
- TR-mov-008 (G-4) `covered_by: []` — gap traçable. TR-cmb-016 même statut.
- Camera GDD r2 Rule 14 déjà câble `tilt_mult = 0.25 if reduce_motion else 1.0` (Logic, MVP-required) avec ACs AC-CAM-70/71/72 BLOCKING — l'implémentation câble vers un flag local `_reduce_motion_active` qui doit être source-d'un canonical `AccessibilityService.reduce_motion` enabled.
- Combat story-022 Status `Blocked` jusqu'à création de cette ADR. Story-013 (Slow-mo Callable injection) déjà mergée et inclut localement `_reduce_motion_disable_slow_mo: bool` flag — il sera **câblé** à `AccessibilityService.disable_slow_mo` (pas réimplémenté).
- Movement GDD §accessibility énumère `reduce_motion` (Camera-multiplied) + `reduce_flash` (VFX-multiplied) comme MVP-required. Le toggle DOIT être accessible **dès le premier lancement, avant tout gameplay** (Movement GDD §accessibility) → exige boot-time pre-gameplay disponibilité, donc autoload `_ready()`.
- Enemy GDD documente `DEATH_TWEEN_DURATION_MS` 150 → 400 ms variant `reduce_motion=true` comme contrat futur (PAS activable au MVP — pas d'API `reduce_motion`). Cette ADR fournit l'API.
- HUD GDD OQ-HUD-6 (Tier 3) + Menu GDD AccessibilityManager Tier 2+ — cette ADR pose les bases pour ces extensions sans les implémenter.

### Constraints

- **Engine** : Godot 4.6 + GDScript. `OS.is_reduce_motion_enabled()` (4.5+) en lecture-only, fallback gracieux si OS ne supporte pas (méthode retourne `false`). Cohérent avec `.claude/docs/technical-preferences.md` (godot-gdscript-specialist + godot-specialist).
- **Plateforme** : PC desktop (Windows/macOS/Linux). Comportement spécifique OS pour `OS.is_reduce_motion_enabled()` documenté Godot — nous ne reposons PAS sur cette méthode comme source unique (toggle utilisateur user-driven reste master).
- **Pillar 1 latency** : lecture `AccessibilityService.reduce_motion` est une simple property read O(1). Hot path safe (Camera _process lit chaque frame Rule 14 — invariant testé). Aucun `ResourceLoader.load` dans hot path (load fait au boot + sur signal `settings_changed`).
- **Pillar 1 anti-friction** : accessibility doit **toujours fonctionner** — corruption settings file ne doit jamais bloquer boot. Délégué à ADR-0014 D-4 (defaults + warning + rewrite-on-next-save).
- **Pre-gameplay mandate** : Movement GDD §accessibility "MUST be accessible dès le premier lancement, avant tout gameplay" → autoload `_ready()` est l'unique entry point garanti pre-gameplay (avant SceneTree main scene).
- **Multi-consumer** : Movement / Camera / Combat / Enemy / VFX / HUD lisent. Single-source-of-truth requis sinon désynchronisation (un toggle UI doit propager à 6 systèmes simultanément, pas 6 fichiers `.tres` à mettre à jour).
- **Single-player** : 1 fichier par profil. Cohérent avec ADR-0014 (multi-profile déféré Tier 2+ OQ-SAV-6).
- **Outbound-zero** : `AccessibilityService` ne référence aucun consumer (cohérent ADR-0005 D-10 outbound-only Movement, ADR-0011 D-7 outbound LevelSystem). Consumers se connectent depuis leur `_ready()`.
- **Defaults invariant CRITICAL** : toutes flags OFF → comportement bit-identical au MVP non-accessibility. Test invariant cross-system requis.

### Requirements

- **REQ-1** : ratifier un **autoload `AccessibilityService`** (position #5, après `Logger/InputManager/GameStateManager/SaveLoadSystem`) comme single-source-of-truth des préférences accessibility. Justification vs ADR-0014 zero-autoload détaillée dans D-1.
- **REQ-2** : déléguer la persistance à ADR-0014 — `accessibility_settings.tres` typé Resource, chargé au boot via `SettingsResource.load_or_default("accessibility", AccessibilitySettings.create_defaults, AccessibilitySettings.migrate_from)`.
- **REQ-3** : exposer **API pull-pattern** : (a) typed properties read-only (`reduce_motion: bool`, `reduce_flash: bool`, méthodes `get_*` typées) + (b) signal `settings_changed` émis sur toute mutation (toggle, reload, OS-change-detect post-MVP).
- **REQ-4** : MVP minimal = boolean toggle unique `reduce_motion` (single click "atténuer toute la motion") + dérivés per-system computed via constants ADR — Tier 2+ exposera multipliers individuels via Settings Menu (extension hooks réservés).
- **REQ-5** : bridge `OS.is_reduce_motion_enabled()` (4.5+) en lecture au `_ready()` — OR-merge avec toggle utilisateur (`effective_reduce_motion = user_toggle OR os_flag`). Si OS retourne `false` par construction (non supporté), comportement = toggle utilisateur seul.
- **REQ-6** : defaults invariant garanti par construction — quand `reduce_motion = false` ET `reduce_flash = false`, **toutes** les méthodes `get_*_mult` retournent `1.0`, `get_disable_slow_mo()` retourne `false`. Test invariant : iso-comportement avec MVP non-accessibility (5 kills consécutifs cross-system test).
- **REQ-7** : bornes clamping **service-level** (consumers n'ont pas à se défendre). `clampf(slow_mo_scale_mult, 1.0, 3.33)`, `clampf(flash_mult, 0.0, 1.0)`, `clampf(tilt_mult, 0.0, 1.0)`. Bornes documentées dans D-7.
- **REQ-8** : empêcher `OS.is_reduce_motion_enabled()` direct hors `AccessibilityService` (forbidden pattern registry). Empêcher `@export var reduce_motion: bool` ad-hoc dans systèmes consumers (forbidden pattern — utiliser interface centralisée).
- **REQ-9** : `process_mode = PROCESS_MODE_ALWAYS` non-applicable au service (settings logic, pas de tick) ; `process_mode = PROCESS_MODE_DISABLED` au `_ready()` (autoload sans `_process` ni `_physics_process`).
- **REQ-10** : laisser explicitement à des ADRs/stories futurs : (a) Settings Menu UI accessibility section (Tier 2+) ; (b) colorblind filter shader (Tier 3 ADR-0016 VFX) ; (c) font scaling (Tier 2+ Menu) ; (d) screen reader integration AccessKit (Tier 3 — Godot Control nodes natifs déjà supportent partiellement) ; (e) sticky keys / hold-to-press input remap (Tier 2+ Input remap epic).

## Decision

### D-1 — Autoload `AccessibilityService` (single-source-of-truth, justified vs ADR-0014 zero-autoload)

Cette ADR retient un **autoload** Godot pour le service accessibility (position #5 dans `project.godot [autoload]`) :

```
[autoload]
Logger="*res://src/core/logger.gd"
InputManager="*res://src/core/input_manager.gd"
GameStateManager="*res://src/core/game_state_manager.gd"
SaveLoadSystem="*res://src/core/save_load_system.gd"
AccessibilityService="*res://src/core/accessibility_service.gd"  # ADR-0015 D-1
```

**Justification vs ADR-0014 D-5 (zero autoload)** : ADR-0014 traite les settings comme **données passives** lues 1 fois au boot par **leur unique owner** (CameraSystem lit camera.tres, InputManager lit input.tres). Pour accessibility, **6 consumers** (Movement, Camera, Combat, Enemy, VFX, HUD) lisent les **mêmes** valeurs et veulent **réagir aux changements live** — pattern qui justifie un central pub-sub :

| Critère | ADR-0014 settings | ADR-0015 accessibility | Impact |
|---------|-------------------|------------------------|--------|
| Nombre de consumers | 1 (owner-only) | 6+ (Movement, Camera, Combat, Enemy, VFX, HUD) | Helper static suffit pour 1 ; pour 6 → coordination |
| Live update mid-game | Non requis MVP | **Requis** (story-022 AC-4) — toggle UI Tier 2+ propage immédiatement | Helper static ne peut pas émettre signal global |
| Pre-gameplay disponibilité | Boot-time owner `_ready()` | **MUST be accessible dès le premier lancement** (Movement GDD §accessibility) | Autoload `_ready()` = seul entry point garanti pre-gameplay |
| Bridge OS-level | Non requis | Requis (`OS.is_reduce_motion_enabled()` 4.5+ AccessKit) | Service centralise call OS, évite N appels redondants |
| Source-of-truth conflict | N/A (1 owner) | Multi-source possible (OS flag vs user toggle) — OR-merge needed | Service implémente OR-merge en 1 endroit |

Helper static (ADR-0014 pattern) ne peut PAS supporter ces 5 contraintes simultanément. Autoload est la décision idiomatique Godot pour pub-sub cross-system, cohérent avec ADR-0007 D-1 (GameStateManager autoload pour pub-sub cross-system) et ADR-0004 D-1 (InputManager autoload pour single-point d'accès Input).

**Persistance** déléguée à ADR-0014 — `AccessibilityService` consomme `SettingsResource.load_or_default("accessibility", ...)` au `_ready()`, ne ré-implémente PAS la couche I/O. Cohérence : ADR-0014 = comment persister, ADR-0015 = comment propager.

### D-2 — Persistance déléguée à ADR-0014 : `accessibility_settings.tres` typé Resource

```gdscript
# src/core/settings/accessibility_settings.gd
class_name AccessibilitySettings extends Resource

const CURRENT_VERSION: int = 1

@export var _settings_version: int = CURRENT_VERSION

# MVP boolean toggle — atténuation globale motion (camera tilt + FOV kick + shake + slow-mo + enemy death tween).
@export var reduce_motion: bool = false

# MVP boolean toggle — atténuation flash VFX (impact futur VFX system + Combat hit feedback).
@export var reduce_flash: bool = false

# Tier 2+ override hooks — exposés API mais defaults safe MVP.
# Justification : permet au Settings Menu Tier 2+ d'ajuster sans bumper version Resource.
@export_range(1.0, 3.33, 0.01) var slow_mo_scale_mult: float = 1.0  # combat story-022 — 1.0 = full slow-mo, 3.33 ≈ disabled
@export var disable_slow_mo: bool = false  # combat story-022 — toggle complet
@export_range(0.0, 1.0, 0.01) var flash_mult: float = 1.0  # VFX/combat — atténuation flash alpha
@export_range(0.0, 1.0, 0.01) var tilt_mult: float = 1.0  # camera Rule 14 — 0.25 si reduce_motion (computed) ou override Tier 2+
@export_range(0.0, 1.0, 0.01) var fov_kick_mult: float = 1.0  # camera Rule 14 — 0.5 si reduce_motion
@export_range(0.0, 1.0, 0.01) var shake_mult: float = 1.0  # camera Rule 14 — 0.0 si reduce_motion
@export_range(100, 600, 10) var enemy_death_tween_ms_override: int = 0  # 0 = use default (150 ou 400 si reduce_motion)

static func create_defaults() -> AccessibilitySettings:
    return AccessibilitySettings.new()

static func migrate_from(version: int, raw: AccessibilitySettings) -> AccessibilitySettings:
    if version >= CURRENT_VERSION:
        return raw
    push_warning("[accessibility-settings] migrating v%d → v%d" % [version, CURRENT_VERSION])
    raw._settings_version = CURRENT_VERSION
    return raw
```

Path canonique : `user://settings/accessibility.tres` (cohérent ADR-0014 D-2 sub-folder).

**Defaults safe** : tous defaults = `false` / `1.0` / `0` (sentinelle "no override") → invariant D-7 (comportement identique MVP non-accessibility).

### D-3 — API publique service : pull-pattern + signal `settings_changed`

```gdscript
# src/core/accessibility_service.gd
extends Node
class_name AccessibilityServiceScript  # éviter collision class_name vs autoload

signal settings_changed  # émis sur toute mutation (toggle, reload, OS-change post-MVP)

const SLOW_MO_SCALE_MULT_MIN: float = 1.0
const SLOW_MO_SCALE_MULT_MAX: float = 3.33
const FLASH_MULT_MIN: float = 0.0
const FLASH_MULT_MAX: float = 1.0
const REDUCE_MOTION_TILT_MULT: float = 0.25  # Camera GDD Rule 14
const REDUCE_MOTION_FOV_KICK_MULT: float = 0.5
const REDUCE_MOTION_SHAKE_MULT: float = 0.0
const REDUCE_MOTION_DEATH_TWEEN_MS: int = 400  # Enemy GDD reduce_motion variant

var _settings: AccessibilitySettings = null

func _ready() -> void:
    _settings = SettingsResource.load_or_default(
        "accessibility",
        Callable(AccessibilitySettings, "create_defaults"),
        Callable(AccessibilitySettings, "migrate_from"),
    ) as AccessibilitySettings
    # Bridge OS (4.5+ AccessKit) — OR-merge user toggle.
    if OS.has_method("is_reduce_motion_enabled") and OS.is_reduce_motion_enabled():
        _settings.reduce_motion = true  # OR-merge — ne décrémente jamais user choice

# Read-only typed accessors. Pas de setters publics — mutation via apply_settings() uniquement.
func is_reduce_motion_enabled() -> bool:
    return _settings.reduce_motion if _settings != null else false

func is_reduce_flash_enabled() -> bool:
    return _settings.reduce_flash if _settings != null else false

func get_disable_slow_mo() -> bool:
    return _settings.disable_slow_mo if _settings != null else false

func get_slow_mo_scale_mult() -> float:
    if _settings == null:
        return 1.0
    return clampf(_settings.slow_mo_scale_mult, SLOW_MO_SCALE_MULT_MIN, SLOW_MO_SCALE_MULT_MAX)

func get_flash_mult() -> float:
    if _settings == null:
        return 1.0
    return clampf(_settings.flash_mult, FLASH_MULT_MIN, FLASH_MULT_MAX)

# Camera Rule 14 — derived from reduce_motion + per-system override.
func get_camera_tilt_mult() -> float:
    if _settings == null:
        return 1.0
    if _settings.reduce_motion:
        return clampf(_settings.tilt_mult * REDUCE_MOTION_TILT_MULT, 0.0, 1.0)
    return clampf(_settings.tilt_mult, 0.0, 1.0)

func get_camera_fov_kick_mult() -> float:
    if _settings == null:
        return 1.0
    if _settings.reduce_motion:
        return clampf(_settings.fov_kick_mult * REDUCE_MOTION_FOV_KICK_MULT, 0.0, 1.0)
    return clampf(_settings.fov_kick_mult, 0.0, 1.0)

func get_camera_shake_mult() -> float:
    if _settings == null:
        return 1.0
    if _settings.reduce_motion:
        return clampf(_settings.shake_mult * REDUCE_MOTION_SHAKE_MULT, 0.0, 1.0)  # 0.0 force
    return clampf(_settings.shake_mult, 0.0, 1.0)

func get_enemy_death_tween_ms() -> int:
    if _settings == null:
        return 150  # MVP default
    if _settings.enemy_death_tween_ms_override > 0:
        return _settings.enemy_death_tween_ms_override
    return REDUCE_MOTION_DEATH_TWEEN_MS if _settings.reduce_motion else 150

# Mutation API — appelé par Settings Menu Tier 2+ ou QA debug command.
func apply_settings(new_settings: AccessibilitySettings) -> void:
    _settings = new_settings
    settings_changed.emit()

func save_settings() -> Error:
    if _settings == null:
        return ERR_UNCONFIGURED
    return SettingsResource.save(_settings, "accessibility")
```

**Pas de variables publiques exposées** (`var _settings` privé), getters typés. Cohérent ADR-0004 D-1 (InputManager `_pressed` privé, `was_pressed_this_tick` API publique).

### D-4 — Cross-system contract (consumer integration table)

| Consumer | Service API consommée | Defaults service-side | Effet computed | GDD ref |
|----------|----------------------|----------------------|----------------|---------|
| `CameraSystem` (Rule 14) | `get_camera_tilt_mult()`, `get_camera_fov_kick_mult()`, `get_camera_shake_mult()` | 1.0, 1.0, 1.0 | tilt × 0.25 si reduce_motion, FOV kick × 0.5, shake × 0.0 | camera-system.md AC-CAM-70/71/72 |
| `CombatSystem` story-022 | `get_disable_slow_mo()`, `get_slow_mo_scale_mult()`, `get_flash_mult()` | false, 1.0, 1.0 | branch `if disable_slow_mo:` skip slow-mo ; `Engine.time_scale = clampf(SLOW_MO_SCALE * mult, 0.0, 1.0)` ; flash alpha × mult émis dans metadata `enemy_killed` | player-combat-system.md AC-CMB-19 r6 + Section G |
| `EnemySystem` (futur) | `get_enemy_death_tween_ms()` | 150 ms | 400 ms si reduce_motion (sauf override Tier 2+) | enemy-system.md `DEATH_TWEEN_DURATION_MS` |
| `VFXManager` (futur ADR-0016) | `get_flash_mult()`, `is_reduce_flash_enabled()` | 1.0, false | flash particle alpha × mult ; disable bloom flash si reduce_flash | (différé ADR-0016) |
| `HUDController` (Tier 3) | `is_reduce_motion_enabled()` | false | disable HUD pulse animation (OQ-HUD-6) | hud-system.md OQ-HUD-6 |
| `MovementController` | (aucun direct — Camera owns visual effets) | — | — | movement GDD délègue à Camera Rule 14 |
| `MenuController` (Tier 2+) | `apply_settings(...)`, `save_settings()` | — | UI Settings Menu écrit | menu GDD §AccessibilityManager Tier 2+ |

**Pattern consumer canonical** :

```gdscript
# Dans CameraSystem._ready()
AccessibilityService.settings_changed.connect(_on_accessibility_changed)
_apply_accessibility()

func _apply_accessibility() -> void:
    _tilt_mult = AccessibilityService.get_camera_tilt_mult()
    _fov_kick_mult = AccessibilityService.get_camera_fov_kick_mult()
    _shake_mult = AccessibilityService.get_camera_shake_mult()

func _on_accessibility_changed() -> void:
    _apply_accessibility()
```

Consumer **cache** les valeurs au boot + sur signal — pas de read service-call dans `_process` (hot path safety, lecture O(1) certes mais pattern uniforme cross-system).

### D-5 — Defaults invariant : tous flags OFF → comportement identique MVP non-accessibility

Quand `accessibility_settings.tres` est absent (first launch) ou contient defaults factory (`reduce_motion=false`, `reduce_flash=false`, multipliers=1.0, override=0) :

- `get_camera_tilt_mult()` retourne `1.0` (Camera tilt full intensity).
- `get_camera_fov_kick_mult()` retourne `1.0` (FOV peak 100°).
- `get_camera_shake_mult()` retourne `1.0` (shake full).
- `get_disable_slow_mo()` retourne `false`.
- `get_slow_mo_scale_mult()` retourne `1.0` → Combat applique `SLOW_MO_SCALE * 1.0 = 0.3` (full slow-mo).
- `get_flash_mult()` retourne `1.0` (flash full).
- `get_enemy_death_tween_ms()` retourne `150` (MVP default).

**Test invariant cross-system** : 5 kills consécutifs avec defaults → comportement bit-identique avec `AccessibilityService` détaché (singleton mock returning defaults). Cohérent avec story-022 AC-3.

**Sentinelle `enemy_death_tween_ms_override = 0`** : 0 signifie "pas d'override Tier 2+", computed retombe sur derived rule.

### D-6 — OS bridge : `OS.is_reduce_motion_enabled()` OR-merge

Au `_ready()` de `AccessibilityService` :

```gdscript
if OS.has_method("is_reduce_motion_enabled") and OS.is_reduce_motion_enabled():
    _settings.reduce_motion = true  # OR-merge — n'efface jamais user opt-in
```

**Sémantique OR-merge** : OS flag = `true` ET user toggle = `false` → effective `reduce_motion = true` (utilisateur a opt-in OS-level, on respecte). OS flag = `false` ET user toggle = `true` → effective `reduce_motion = true` (user a opt-in app-level, on respecte). Jamais downgrade.

**Fallback gracieux** : `OS.has_method("is_reduce_motion_enabled")` guard évite crash sur Godot < 4.5 (théorique, projet pinné 4.6) ou OS qui retourne `false` par construction (Linux non-AccessKit, OS non supporté). MVP fonctionne via toggle utilisateur user-driven seul.

**Pas de polling continu OS** au MVP. Tier 3 pourra ajouter `_process` poll ou OS notification pour détecter changement OS-level live (rare — utilisateur toggle macOS Reduce Motion mid-game). MVP : OS flag lu 1 fois au `_ready()`.

### D-7 — Bornes/clamping service-level

Toutes les bornes sont appliquées **dans le service** (consumers reçoivent valeurs déjà clampées) :

| Property | Range | Clamp | Source |
|----------|-------|-------|--------|
| `slow_mo_scale_mult` | [1.0, 3.33] | `clampf(v, 1.0, 3.33)` | story-022 AC-5 |
| `flash_mult` | [0.0, 1.0] | `clampf(v, 0.0, 1.0)` | story-022 AC-3 |
| `tilt_mult` | [0.0, 1.0] | `clampf(v * 0.25 si reduce_motion, 0.0, 1.0)` | camera GDD Rule 14 |
| `fov_kick_mult` | [0.0, 1.0] | `clampf(v * 0.5 si reduce_motion, 0.0, 1.0)` | camera GDD Rule 14 |
| `shake_mult` | [0.0, 1.0] | `clampf(v * 0.0 si reduce_motion, 0.0, 1.0)` (= 0.0 force) | camera GDD Rule 14 |
| `enemy_death_tween_ms` | [100, 600] | computed (150 ou 400 ou override) | enemy GDD |

**Justification clamp service-level** : un seul lieu de défense, consumer code reste simple (pas de `clampf` répétés). Si Settings Menu Tier 2+ écrit valeur out-of-range (bug UI), service la clampe avant de la servir.

### D-8 — Outbound-zero : service ne référence aucun consumer

`AccessibilityService` ne contient aucune référence (preload, get_node, autoload name) vers Movement / Camera / Combat / Enemy / VFX / HUD. Cohérent ADR-0005 D-10 (Movement outbound-only), ADR-0011 D-7 (Level outbound-only), ADR-0014 D-10 (Settings Resources outbound-zero).

Consumers se **self-connectent** depuis leur `_ready()` :

```gdscript
# Dans CameraSystem._ready() — pattern consumer
AccessibilityService.settings_changed.connect(_on_accessibility_changed)
```

Le service publie ; les consumers s'abonnent. Aucun couplage descendant.

### D-9 — Forbidden patterns enregistrés au control manifest

Cette ADR ajoute 3 forbidden patterns à `docs/architecture/control-manifest.md` :

| Pattern | Layer | Niveau |
|---------|-------|--------|
| `OS.is_reduce_motion_enabled\(\)` hors `src/core/accessibility_service.gd` | All | BLOCKING |
| `@export var reduce_motion: bool` ou `@export var reduce_flash: bool` dans systèmes consumers (Camera, Combat, Movement, Enemy, VFX, HUD) — utiliser `AccessibilityService.get_*` | Foundation+Gameplay+UI | BLOCKING |
| Hardcoded multipliers accessibility (`* 0.25`, `* 0.5`, `* 0.0` ou `400 ms`) dans gameplay code non issu de `AccessibilityService.get_*_mult()` | Foundation+Gameplay | ADVISORY (lint suggère mais ne casse pas — rationale : certaines constantes Camera Rule 14 sont définies inline GDD) |

Lint statique cover-all : grep `\bOS\.is_reduce_motion_enabled\b` filtré sauf `accessibility_service.gd` ; grep `@export\s+var\s+(reduce_motion|reduce_flash)` filtré sauf `accessibility_settings.gd`.

### D-10 — Save trigger : explicit (cohérent ADR-0014 D-6)

Settings sauvegardés **uniquement** sur trigger explicite :

- Menu Settings UI Tier 2+ : "Apply" button → `AccessibilityService.apply_settings(new) ; AccessibilityService.save_settings()`.
- QA debug : commande console.

**Pas de save() automatique en `_process`**. Pas de batched coordinator. Cohérent avec ADR-0014 D-6.

### D-11 — Process mode : autoload sans `_process` ni `_physics_process`

`AccessibilityService` n'a PAS de `_process` ni `_physics_process` (service stateful, pas de tick). `process_mode` reste default. Aucun impact pause via GSM (le service reste actif mais inert).

**Justification** : pas de polling OS continu au MVP (D-6). Pas d'orchestration tick-based. Consumer-driven via signal pull → service réagit aux mutations API uniquement.

### Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                      user:// filesystem                          │
│   savegame.cfg              settings/                            │
│   (ADR-0010 ConfigFile)     ├── camera.tres                      │
│                             ├── input.tres                       │
│                             ├── audio.tres (future)              │
│                             └── accessibility.tres ← ADR-0015    │
└──────────────────────────────────────────────────────────────────┘
                                            │
                                            │ SettingsResource.load_or_default
                                            │ (ADR-0014 helper)
                                            ▼
                                   ┌────────────────────────┐
                                   │ AccessibilityService   │
                                   │ (autoload #5)          │
                                   │  - _settings: AccS     │
                                   │  - signal settings_chgd│
                                   │  - get_*_mult()        │
                                   └────────────────────────┘
                                            │
                                signal: settings_changed
                ┌───────────────────┬───────┼───────┬───────────────┐
                │                   │       │       │               │
                ▼                   ▼       ▼       ▼               ▼
         CameraSystem        CombatSystem  Enemy   VFX(future)   HUD(Tier 3)
         (Rule 14)           (story-022)   (death) (flash)       (pulse)
```

Service publish ; consumers self-connect au `_ready()` ; aucun couplage descendant.

## Consequences

### Positive

- **Single-source-of-truth accessibility cross-system** : 1 fichier `.tres`, 1 service, 6 consumers. Toggle UI Tier 2+ propage en 1 emit signal.
- **Pre-gameplay disponibilité garantie** : autoload `_ready()` avant SceneTree main scene = entry point earliest possible. Movement GDD §accessibility "MUST be accessible dès le premier lancement" satisfait par construction.
- **Defaults invariant testable** : test cross-system 1 ligne (instancier service avec `AccessibilitySettings.create_defaults()`) → comportement identique MVP non-accessibility.
- **Persistance déléguée ADR-0014** : aucun code I/O dupliqué, cohérence pattern Settings.
- **OS bridge gracieux** : `OS.is_reduce_motion_enabled()` (4.5+ AccessKit) lu mais OR-merge avec user toggle → respect double opt-in.
- **Bornes service-level** : consumers reçoivent valeurs déjà clampées, code consumer reste simple.
- **Outbound-zero** : aucun couplage descendant, suit pattern ADR-0005/0011/0014.
- **Forbidden patterns enforce cohérence** : impossible de hardcoder `OS.is_reduce_motion_enabled()` dans Camera ou Combat — lint CI casse.
- **Extension Tier 2+/3 ready** : per-system override hooks (`tilt_mult`, `flash_mult`, etc.) déjà exposés via Resource — Settings Menu Tier 2+ branche directement, pas de bump version.

### Negative

- **Autoload supplémentaire (position #5)** : ajoute coordination boot vs ADR-0007 D-1 (4 autoloads canoniques). Justifié par D-1 (multi-consumer + live update + pre-gameplay mandate).
- **OS bridge MEDIUM risk** : `OS.is_reduce_motion_enabled()` post-cutoff Godot 4.5+ AccessKit. Comportement OS-spécifique (Linux non-AccessKit retourne `false` par construction) — fallback gracieux mais doc OS-by-OS à ajouter Tier 2+.
- **Test cross-system requis** : defaults invariant exige 1 test par consumer (Camera + Combat + Enemy + VFX + HUD = 5 tests) ou 1 test E2E qui exerce les 5. Coût ≈ 2-3 h test additionnel.
- **Migration version Resource** : si Tier 2+ ajoute champs (`colorblind_filter`, `font_scale`), `migrate_from` doit être complétée. Cohérent ADR-0014 D-3, mais 1 décision per-bump.
- **Live update mid-game pattern requires reconnect signal partout** : 6 consumers doivent connecter `settings_changed` à leur `_apply_accessibility()` — boilerplate répété ~3 lignes par consumer.

### Neutral

- **Cohérence ADR-0014 délégation** : la persistance n'est pas dupliquée, l'autoload service consomme le helper. Symétrie attendue.
- **API getter typés** : pattern cohérent avec ADR-0004 D-1 (InputManager getters) et ADR-0007 (GSM getters) — pas une nouveauté pour le projet.
- **Pas de chiffrement / signature** : settings éditable manuellement par utilisateur (modder/QA debug). Cohérent ADR-0010 + ADR-0014 — niveau Tier 1 audience solo.

### Mitigations

- **Boot ordering** : tester explicitement que `AccessibilityService._ready()` complète AVANT SceneTree main scene (CameraSystem + CombatSystem `_ready()` consumers) — invariant testé au story d'implémentation. ADR-0007 D-1 amendé pour documenter position #5 si nécessaire (sinon documentation inline `accessibility_service.gd` header).
- **OS bridge fallback** : test `OS.has_method("is_reduce_motion_enabled")` guard couvre Godot < 4.5 (improbable) ET OS non supporté (Linux sans AccessKit). MVP accepte fonctionnement uniquement via user toggle si OS pas supporté.
- **Defaults invariant test cross-system** : 1 test E2E (5 kills consécutifs + walls runs + dashes) avec `AccessibilityService` factory defaults → asserts iso-comportement. Coût 2-3 h amorti sur 6 consumers (vs 6 tests indépendants).
- **Migration `migrate_from` v1 → v2** : documenter la procédure dans `accessibility_settings.gd` header — chaque bump = 1 entrée dans `migrate_from`. Cohérent ADR-0014.
- **Reconnect signal boilerplate** : pattern documenté dans ADR D-4 + control manifest exemple canonical. Refactor possible Tier 2+ via base class consumer si répétition devient pénible (over-engineering MVP).

## Alternatives Considered

### Alt 1 — Helper static class `AccessibilityResource` (zero autoload, cohérent ADR-0014)

**Rejet justifié D-1** : helper static ne supporte pas (a) live update mid-game (pas d'émission signal global), (b) bridge OS (call `OS.is_reduce_motion_enabled()` redondant si N consumers le font chacun), (c) source-of-truth conflict resolution (OR-merge OS flag vs user toggle), (d) pre-gameplay mandate (helper static est lazy — premier consumer call déclenche load, mais ordre d'appel cross-system non garanti). 5/5 contraintes échouent.

### Alt 2 — Étendre InputManager (Camera GDD r2 suggérait `InputManager.reduce_motion`)

**Rejet** : Input Layer = Foundation, Accessibility = transversal multi-system. Coupling Foundation→Accessibility violerait ADR-0004 D-5 (Input outbound focus signal one-way Foundation discipline). Mélange responsabilités (Input gère polling actions + remap ; Accessibility gère préférences UI + multipliers visuels) — coût refactor élevé Tier 2+ quand Accessibility prendra de l'ampleur (font scaling, colorblind, screen reader).

### Alt 3 — Singleton sans autoload (script avec methods static + state global)

**Rejet** : Godot pattern idiomatique pour pub-sub cross-system = autoload (Node lifecycle, signal natif, ordre boot garanti). Singleton custom recompose ces features manuellement, casse la cohérence avec InputManager / GSM / SaveLoadSystem / Logger qui sont tous autoloads.

### Alt 4 — Per-system Resource (chaque consumer charge ses propres flags accessibility)

**Rejet** : duplique data (un toggle UI doit écrire 6 fichiers `.tres`), désynchronisation prévisible (camera updated, combat pas updated → comportement incohérent), violations Pillar 1 anti-friction (utilisateur toggle "reduce motion" et 50% des effets s'atténuent, 50% pas — pire que pas d'option).

### Alt 5 — Push pattern (service appelle `consumer.set_reduce_motion(true)` directement)

**Rejet** : viole outbound-zero (D-8). Service connaîtrait les consumers (Camera/Combat/...) → coupling descendant. Pull pattern (consumer self-connect au signal) maintient outbound-zero et est cohérent avec ADR-0005 D-10 + ADR-0011 D-7.

### Alt 6 — Reposer entièrement sur `OS.is_reduce_motion_enabled()` (pas de toggle in-game)

**Rejet** : (a) Linux non-AccessKit retourne `false` par construction → utilisateur Linux exclu, (b) Movement GDD §accessibility "toggle MUST be accessible dès le premier lancement" exige opt-in app-level (pas seulement OS), (c) WCAG 2.3.3 demande choix utilisateur granulaire (slow-mo scale différent de tilt mult). User toggle in-app reste obligatoire ; OS bridge est ADDITIVE.

## Implementation Guidelines

### Boot order requirement

`project.godot [autoload]` :
```
Logger="*res://src/core/logger.gd"
InputManager="*res://src/core/input_manager.gd"
GameStateManager="*res://src/core/game_state_manager.gd"
SaveLoadSystem="*res://src/core/save_load_system.gd"
AccessibilityService="*res://src/core/accessibility_service.gd"
```

Position #5 : APRÈS `SaveLoadSystem` (qui owns ConfigFile savegame, indépendant) et AVANT scene main (consumers `_ready()`). `SettingsResource.load_or_default` est synchrone et bloquant — boot cost ≤ 5 ms (file < 1 KB, ResourceLoader cached path).

### Forbidden grep patterns CI

```bash
# Forbidden #1 : OS.is_reduce_motion_enabled() hors AccessibilityService
grep -rn "OS\.is_reduce_motion_enabled" src/ --include="*.gd" \
  | grep -v "src/core/accessibility_service.gd" \
  || echo "PASS"

# Forbidden #2 : @export var reduce_motion / reduce_flash hors AccessibilitySettings
grep -rnE "@export\s+var\s+(reduce_motion|reduce_flash)\s*:" src/ --include="*.gd" \
  | grep -v "src/core/settings/accessibility_settings.gd" \
  || echo "PASS"
```

### Test cross-system (defaults invariant)

```gdscript
# tests/integration/accessibility/defaults_invariant_test.gd
extends GdUnitTestSuite

func test_defaults_invariant_camera_combat_enemy() -> void:
    # Setup : factory defaults
    var settings := AccessibilitySettings.create_defaults()
    AccessibilityService.apply_settings(settings)
    # Camera : tilt full, FOV full, shake full
    assert_float(AccessibilityService.get_camera_tilt_mult()).is_equal(1.0)
    assert_float(AccessibilityService.get_camera_fov_kick_mult()).is_equal(1.0)
    assert_float(AccessibilityService.get_camera_shake_mult()).is_equal(1.0)
    # Combat : slow-mo full, flash full, no disable
    assert_bool(AccessibilityService.get_disable_slow_mo()).is_false()
    assert_float(AccessibilityService.get_slow_mo_scale_mult()).is_equal(1.0)
    assert_float(AccessibilityService.get_flash_mult()).is_equal(1.0)
    # Enemy : 150 ms (MVP default)
    assert_int(AccessibilityService.get_enemy_death_tween_ms()).is_equal(150)
```

### Test reduce_motion ON cross-system

```gdscript
func test_reduce_motion_on_propagates_camera_combat_enemy() -> void:
    var settings := AccessibilitySettings.create_defaults()
    settings.reduce_motion = true
    AccessibilityService.apply_settings(settings)
    # Camera Rule 14
    assert_float(AccessibilityService.get_camera_tilt_mult()).is_equal(0.25)
    assert_float(AccessibilityService.get_camera_fov_kick_mult()).is_equal(0.5)
    assert_float(AccessibilityService.get_camera_shake_mult()).is_equal(0.0)
    # Enemy
    assert_int(AccessibilityService.get_enemy_death_tween_ms()).is_equal(400)
    # Combat slow-mo unchanged (separate toggle disable_slow_mo)
    assert_bool(AccessibilityService.get_disable_slow_mo()).is_false()
```

### Settings Menu Tier 2+ integration hook

```gdscript
# Pattern futur Settings Menu (Tier 2+) — pas implémenté MVP
func _on_apply_button_pressed() -> void:
    var new_settings := AccessibilitySettings.create_defaults()
    new_settings.reduce_motion = $ReduceMotionCheckbox.button_pressed
    new_settings.reduce_flash = $ReduceFlashCheckbox.button_pressed
    new_settings.slow_mo_scale_mult = $SlowMoSlider.value
    AccessibilityService.apply_settings(new_settings)
    var err := AccessibilityService.save_settings()
    if err != OK:
        push_warning("[settings] accessibility save failed : %s" % err)
```

## Verification Criteria

| ID | Description | Severity | Test/Method |
|----|-------------|----------|-------------|
| **VC-1** | `AccessibilityService` autoload position #5, charge `accessibility.tres` au `_ready()` ≤ 5 ms | BLOCKING | Test boot timing + `Engine.has_singleton("AccessibilityService")` |
| **VC-2** | Defaults invariant : factory defaults → `get_*_mult` retournent 1.0, `get_disable_slow_mo` false, `get_enemy_death_tween_ms` 150 | BLOCKING | `tests/integration/accessibility/defaults_invariant_test.gd` |
| **VC-3** | reduce_motion=true → camera tilt 0.25, FOV kick 0.5, shake 0.0, enemy death tween 400 | BLOCKING | `tests/integration/accessibility/reduce_motion_propagation_test.gd` |
| **VC-4** | Bornes clamping : `slow_mo_scale_mult=5.0` → clampé 3.33 ; `flash_mult=-0.5` → clampé 0.0 ; `slow_mo_scale_mult=0.5` → clampé 1.0 | BLOCKING | unit test `accessibility_service_clamping_test.gd` |
| **VC-5** | Live update : `apply_settings(new)` → `settings_changed` émis 1 fois, consumers reçoivent et re-cache | BLOCKING | Integration test connect signal + verify cache |
| **VC-6** | OS bridge OR-merge : OS=true + user=false → effective true ; OS=false + user=true → effective true ; OS=false + user=false → false | ADVISORY | Mock `OS.is_reduce_motion_enabled` via injection (Tier 2+) ou test manuel macOS |
| **VC-7** | Outbound-zero : grep `\b(MovementController\|CameraSystem\|CombatSystem\|EnemySystem\|VFXManager\|HUDController)\b` dans `src/core/accessibility_service.gd` retourne 0 match | BLOCKING | `tests/static/accessibility_service_outbound_zero_test.gd` |
| **VC-8** | Forbidden #1 : `OS.is_reduce_motion_enabled` hors `accessibility_service.gd` retourne 0 match | BLOCKING | Lint CI grep |
| **VC-9** | Forbidden #2 : `@export var reduce_motion\|reduce_flash` hors `accessibility_settings.gd` retourne 0 match | BLOCKING | Lint CI grep |
| **VC-10** | Persistance : `apply_settings` + `save_settings` → fichier `user://settings/accessibility.tres` écrit, reload preserve toutes properties | BLOCKING | Integration test round-trip (cohérent ADR-0014 D-3) |

## GDD Requirements Addressed

| TR-ID | GDD | Coverage |
|-------|-----|----------|
| **TR-mov-008** (G-4) | `design/gdd/player-movement-system.md` §accessibility | ✅ Covered — `reduce_motion` + `reduce_flash` propagation cross-system via service. Movement délègue à Camera (Rule 14) pour effets visuels. |
| **TR-cmb-016** (G-4 ext) | `design/gdd/player-combat-system.md` AC-CMB-19 r6 + Section G | ✅ Covered — `disable_slow_mo`, `slow_mo_scale_mult` [1.0, 3.33], `flash_mult` [0.0, 1.0]. Story-022 unblocked. |
| AC-CAM-70/71/72 | `design/gdd/camera-system.md` Rule 14 | ✅ Covered — `get_camera_tilt_mult`/`get_camera_fov_kick_mult`/`get_camera_shake_mult`. |
| `DEATH_TWEEN_DURATION_MS` reduce_motion variant | `design/gdd/enemy-system.md` §entities.yaml:69 | ✅ Covered — `get_enemy_death_tween_ms()` retourne 400 si reduce_motion. |
| OQ-HUD-6 (Tier 3) | `design/gdd/hud-system.md` | 🔵 API ready — `is_reduce_motion_enabled()` exposé. Implémentation HUD différée Tier 3 mais l'interface est en place. |
| §AccessibilityManager Tier 2+ | `design/gdd/menu-system.md` | 🔵 API ready — `apply_settings` / `save_settings` exposés. Settings Menu UI différé Tier 2+. |
| OS `prefers-reduced-motion` | `design/gdd/menu-system.md` U-8 | ✅ Covered — bridge `OS.is_reduce_motion_enabled()` (4.5+ AccessKit) OR-merge user toggle. |

## Open Questions

| ID | Question | Owner | Resolution |
|----|----------|-------|------------|
| OQ-ACC-1 | Multi-profile (Tier 2+) — chaque profil a ses propres `accessibility.tres` ou shared cross-profile ? | accessibility-specialist + ADR-0010 OQ-SAV-6 | Tier 2+ — cohérent ADR-0014 OQ-SET-2. MVP single-profile. |
| OQ-ACC-2 | Cloud sync accessibility settings (Steam Cloud) ? | accessibility-specialist | Tier 3 — cohérent ADR-0014 OQ-SET-3. MVP local only. |
| OQ-ACC-3 | Colorblind filter (Tier 3) — service expose `get_colorblind_filter() -> StringName` ou shader-side ? | accessibility-specialist + ADR-0016 VFX | Tier 3 — ADR séparée. API hook réservé via `@export var colorblind_filter: StringName = &""` champ futur dans AccessibilitySettings (bump version). |
| OQ-ACC-4 | Font scaling (Tier 2+) — service expose ou Menu autoload sépare ? | accessibility-specialist + Menu GDD | Tier 2+ — cohérent menu-system.md §K.7. Probable extension service via `get_font_scale() -> float` (bump Resource version). |
| OQ-ACC-5 | Screen reader integration (Tier 3) — Godot 4.5+ AccessKit Control nodes natifs supportent partiellement. Service responsable ou laissé à Godot ? | accessibility-specialist | Tier 3 — natif Godot. Service expose éventuel `is_screen_reader_active() -> bool` mais Godot Control nodes auto-instrumentés. |
| OQ-ACC-6 | Sticky keys / hold-to-toggle (Tier 2+) — Input remap epic (ADR-0004 OQ-INP-X) ou ici ? | input-specialist + accessibility-specialist | Tier 2+ Input remap — cohérent ADR-0004. Pas dans ce service (responsabilité Input). |
| OQ-ACC-7 | Test cross-system defaults invariant — 1 E2E test ou 6 unit tests par consumer ? | qa-lead | Recommandation : 1 E2E intégration `defaults_invariant_test.gd` exerçant 6 consumers via mocks + 1 unit test par consumer assertant `get_*_mult` defaults. ~3 h impl. |

## Source

- Architecture review : `docs/architecture/architecture.md` §8.4 (ADR-0015 planifiée Polish phase).
- TR registry : `docs/architecture/tr-registry.yaml` TR-mov-008 (G-4) + TR-cmb-016 (G-4 ext).
- GDDs : `design/gdd/camera-system.md` Rule 14 + AC-CAM-70/71/72, `design/gdd/player-combat-system.md` AC-CMB-19 r6 + Section G, `design/gdd/player-movement-system.md` §accessibility, `design/gdd/enemy-system.md` `DEATH_TWEEN_DURATION_MS`, `design/gdd/hud-system.md` OQ-HUD-6, `design/gdd/menu-system.md` §AccessibilityManager Tier 2+ + U-8.
- ADR dépendances : `docs/architecture/adr-0014-save-load-settings-infrastructure.md` (persistance déléguée), `docs/architecture/adr-0007-game-state-manager.md` D-1 (autoload ordering), `docs/architecture/adr-0005-movement-signals-architecture.md` D-10 (outbound-only pattern), `docs/architecture/adr-0011-level-scene-architecture.md` D-7 (outbound LevelSystem).
- Engine reference : `docs/engine-reference/godot/breaking-changes.md` (4.5 AccessKit), `docs/engine-reference/godot/current-best-practices.md` §54 (Control + AccessKit).
- Stories débloquées : `production/epics/combat-system/story-022-accessibility-reduce-motion-combat.md` (Status Blocked → Ready).
