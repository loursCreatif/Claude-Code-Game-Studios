# ADR-0014: Save/Load Settings Infrastructure (Resource Ratification)

## Status

Accepted (créée et promue 2026-05-02 par Martin — débloque story camera-013 + input-010 + futures Audio settings — phase Polish P3 hors MVP, peut entrer backlog post-Sprint 1)

## Date

2026-05-02

## Last Verified

2026-05-02

## Decision Makers

- Architecture authority (technical-director équivalent)
- godot-specialist (Engine Compatibility validation Godot 4.6 Resource API)
- godot-gdscript-specialist (Implementation Guidelines GDScript Resource patterns)

## Summary

Cette ADR ratifie l'architecture de persistance des **préférences utilisateur** (settings) — distincte de la persistance d'**état runtime** (savegame, gouvernée par ADR-0010 ConfigFile). Settings = schémas typés stables, edition manuelle utile QA, multi-systèmes consommateurs (Camera, Input, Audio futur). Décision : **Resource (.tres) typé** par système, chargé via helper static class `SettingsResource` (zero autoload supplémentaire), sub-folder `user://settings/<system>.tres`, versioning par champ `_settings_version: int`, migration table par schéma, corruption fallback sur factory defaults + push_warning + réécriture au prochain save explicite.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core (file I/O, Resource serialization) |
| **Knowledge Risk** | LOW — `Resource` + `ResourceSaver.save` + `ResourceLoader.load` API stables depuis Godot 3.x. Aucune API post-cutoff (4.4/4.5/4.6) requise pour MVP Settings. `duplicate_deep()` (Godot 4.5+) NON utilisé : `duplicate(true)` sub-resource flag couvre les besoins MVP (nested resources rares dans settings flat). |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md` (4.6 baseline), ADR-0010 §D-1 (rejet Resource pour savegame, justifié schema lock-in pour state runtime fluide ; ne s'applique pas à settings stables), GDD `design/gdd/camera-system.md` Tuning Knobs (mouse_sensitivity/y_inverted/fov_user_offset), GDD `design/gdd/input-system.md` Tuning Knobs (sensitivity, focus_regain_window_ms, debug_overlay_default). |
| **Post-Cutoff APIs Used** | Aucune. `Resource.@export` + `ResourceSaver.save(resource, path)` + `ResourceLoader.load(path) as <Type>` + `OS.has_feature("debug")` + `DirAccess.make_dir_recursive_absolute()` — toutes stables depuis 3.x. |
| **Verification Required** | 4 ACs camera (AC-CAM-SAVE-1/2/3/4) + 7 ACs input (TR-inp-009 covered) + 3 ACs cross-system (corruption fallback rewrite, version migration, factory defaults bootstrap). Tests prioritaires : corruption byte-flip → fallback ; first-launch no-file → defaults silencieux ; load v1 → migrate v2 (schema bump). |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0010 (Save/Load ConfigFile pour savegame) — par contraste explicite, **pas par couplage** : cette ADR justifie pourquoi settings DIVERGE de la décision savegame. ADR-0007 (GameStateManager) — settings load se produit avant `_ready()` consumer (read at `_ready()` boot), pas d'interaction GSM. |
| **Enables** | Camera story-013 (camera_settings.tres lifecycle, AC-CAM-SAVE-1 à 4) ; Input story-010 (input_settings.tres lifecycle, TR-inp-009) ; future Audio settings (volume sliders, audio_settings.tres) ; future Accessibility settings (reduce_motion, reduce_flash — pourrait s'auto-héberger ou suivre ADR-0015 Accessibility Interface Layer). |
| **Blocks** | Camera story-013 (Status Blocked → Ready une fois Accepted) ; Input story-010 (Status Blocked → Ready) ; Menu/Settings UI (post-MVP polish). |
| **Ordering Note** | Cette ADR est **Polish P3** non-MVP. Elle peut être Accepted en parallèle des sprints MVP — son acceptation débloque uniquement les stories Polish (camera-013, input-010). N'affecte pas le critical path Sprint 1 (combat / level / menu / shop / save-load gameplay). |

## Context

### Problem Statement

Deux TRs distincts du registre — **TR-cam-006** (`camera_settings.tres`) et **TR-inp-009** (`input_settings.tres`) — déclarent un besoin de persistance pour les **préférences utilisateur** (sensitivité souris, inversion Y, FOV offset, focus regain window, etc.). Aucun ADR ne formalise actuellement le pattern de persistance settings, et le GDD save-load-system r1 R-SAV-2 a explicitement REJETÉ Resource (.tres) **pour savegame** (state runtime) — laissant les settings sans architecture validée.

Sans ADR, 4 décisions structurelles risquent de diverger entre systèmes consommateurs :

1. **Format** : Resource (.tres) ou ConfigFile partagée avec savegame ? Le GDD r1 R-SAV-2 rejette Resource pour savegame mais la justification (schema lock-in casse migration MVP→Tier2+) ne s'applique pas aux settings (schémas stables, peu de migration).
2. **Versioning** : champ `_settings_version` ou nom de fichier suffixé `_v1.tres` ? Migration table inline dans la resource ou helper externe ?
3. **Corruption fallback** : que faire si `ResourceLoader.load()` retourne null (parse fail, file truncated, byte-flipped) ? Restore from backup, defaults silencieux, defaults + warning, abort boot ?
4. **Ownership lifecycle** : autoload `SettingsManager` central ? Verbs absorbés par SaveLoadSystem (load_resource/save_resource) ? Helper static class chargé à la demande par chaque consumer ?

Sans cette ADR, chaque story (camera-013, input-010) trancherait indépendamment ces 4 décisions, créant divergence prévisible et coût refactor cross-system futur. L'ADR fixe le pattern une seule fois et le rend opposable cross-ADR via les forbidden patterns registry.

### Current State

- ADR-0010 ratifie ConfigFile pour savegame (`user://savegame.cfg`, R-SAV-2). Décision **explicitement scopée à savegame state runtime** — n'aborde pas settings.
- Camera story-013 (`production/epics/camera-system/story-013-camera-settings-save-load.md`) Status `Blocked` jusqu'à création de cette ADR. ACs provisoires AC-CAM-SAVE-1/2/3/4 référencent déjà `camera_settings.tres` (Resource format engagé par GDD Tuning Knobs).
- Input story-010 (`production/epics/input-system/story-010-settings-persistence.md`) Status `Blocked` même cause. ACs provisoires énumèrent 6 properties `@export` typées (mouse_sensitivity, mouse_y_inverted, mouse_capture_at_boot, focus_regain_window_ms, debug_overlay_default, latency_anomaly_threshold_ms).
- TR-registry `TR-cam-006` et `TR-inp-009` : `covered_by: []` — gap traçable. `architecture.md §8.5` note ADR-0014 planifiée phase Polish.

### Constraints

- **Engine** : Godot 4.6 + GDScript. Pas de bibliothèque tierce. Cohérent avec `.claude/docs/technical-preferences.md` (godot-gdscript-specialist + godot-specialist). Pas de `duplicate_deep()` (Godot 4.5+ post-cutoff API non requise pour MVP Settings — `duplicate(true)` couvre flat schemas).
- **Plateforme** : PC desktop (Windows/macOS/Linux). `user://` résolu par Godot vers location système locale, identique ADR-0010. Sub-dossier `user://settings/` créé via `DirAccess.make_dir_recursive_absolute()` au boot si absent.
- **Pillar 1 latency** : settings load est une opération **boot-time one-shot** par consumer (`_ready()`), hors hot path gameplay. Save settings est une opération **rare** (changement utilisateur via menu Settings — Tier 2+/Polish), debounce ou flush-on-quit acceptables. Aucun budget frame applicable.
- **Pillar 1 anti-friction** : settings doivent **toujours fonctionner** — corruption ou absence du fichier ne doit jamais bloquer le boot. Fallback defaults silencieux si first-launch (no-file), warning loggé mais boot poursuit si corruption.
- **Single-player** : 1 fichier par système consumer. Pas de cloud sync, pas de multi-profil MVP. Multi-profile déféré Tier 2+/3 (cohérent avec ADR-0010 OQ-SAV-6).
- **Anti-cheat** : niveau naïf accepté Tier 1 (audience solo). Settings éditable manuellement par utilisateur (modder/QA debug). Pas de signature, pas de chiffrement.
- **Thread** : main thread only. Cohérent avec `.claude/rules/input-singleton-main-thread-only.md`. Aucune raison d'autoriser thread non-main pour settings (boot-time + rare save).
- **Couplage** : chaque resource settings est outbound-zero — `CameraSettings extends Resource` ne référence aucun consumer. Helper static class `SettingsResource` est une utility (pas un autoload, pas un singleton stateful).

### Requirements

- **REQ-1** : ratifier le format **Resource (.tres) typé par système** — distinct de ConfigFile savegame (ADR-0010), justifié par schémas settings stables vs state runtime fluide.
- **REQ-2** : exposer un **helper static class `SettingsResource`** avec 3 verbes : `load_or_default(path: String, default_factory: Callable) -> Resource`, `save(resource: Resource, path: String) -> Error`, `_resolve_settings_path(system: String) -> String`. Aucun autoload supplémentaire.
- **REQ-3** : chaque resource concrète DOIT exposer un champ `_settings_version: int` exporté (defaults `1`) et une factory function `static create_defaults() -> <Type>`.
- **REQ-4** : sub-folder `user://settings/` créé via `DirAccess.make_dir_recursive_absolute()` au premier accès (helper SettingsResource gère).
- **REQ-5** : corruption fallback **uniforme** : si `ResourceLoader.load(path) as <Type>` retourne null → instancier `<Type>.create_defaults()` + `push_warning("[settings] %s corrupted, using defaults" % path)` + réécrire au prochain `save()` explicite (pas de réécriture automatique boot — risque de masquer un bug récurrent).
- **REQ-6** : version migration **par schéma** : si `loaded._settings_version < <Type>.CURRENT_VERSION`, helper `<Type>._migrate_from(version: int, raw: <Type>) -> <Type>` appelé. Migration **forward-only** (pas de downgrade). Fallback defaults si migration impossible.
- **REQ-7** : empêcher tout I/O direct `FileAccess.store_*` pour settings — toujours via `ResourceSaver.save` (forbidden pattern registry, échappe au breaking change Godot 4.4 `FileAccess.store_*` retour bool).
- **REQ-8** : empêcher tout hardcoded settings value dans gameplay code (forbidden pattern : si une variable touche un Tuning Knob settings, elle DOIT venir d'une instance Resource lue au boot).
- **REQ-9** : `process_mode` non-applicable (settings = boot-time + rare save, pas un autoload).
- **REQ-10** : laisser explicitement à des ADRs futurs : (a) Settings menu UI (Menu/Settings epic) ; (b) cloud sync (Tier 3) ; (c) chiffrement (Tier 3 anti-cheat) ; (d) multi-profile (Tier 2+) ; (e) Accessibility settings (potentiellement ADR-0015 Accessibility Interface Layer).

## Decision

### D-1 — Format ratifié : Resource (.tres) typé par système

Cette ADR retient `Resource` Godot natif typé pour settings :

- **Format** : `Resource` extends class typed avec `@export` properties.
- **Path canonique** : `user://settings/<system>.tres` (e.g. `user://settings/camera.tres`, `user://settings/input.tres`).
- **Engine API** : `ResourceSaver.save(resource, path)` + `ResourceLoader.load(path) as <Type>`. Stables depuis Godot 3.x.

**Rejet ConfigFile partagé avec savegame** : ConfigFile flat key-value perd le typage natif Resource (`@export` enforce types Godot, validation IDE, autocompletion). Pour settings stables avec schémas typés (`mouse_sensitivity: float`, `mouse_y_inverted: bool`), Resource est le format idiomatique Godot. ADR-0010 R-SAV-2 rejette Resource pour **savegame** car schema lock-in bloque migration MVP→Tier2+ (ajout dynamique de clés inventory/upgrade) — cette contrainte ne s'applique PAS à settings (schémas stables figés par GDD Tuning Knobs).

**Rejet ConfigFile dédié settings** : ConfigFile = section + key + variant. Settings veulent du typage exporté + factory defaults + migration par version. Resource résout les 3 nativement, ConfigFile demande wrappers manuels.

**Rejet binary FileAccess** : breaking change Godot 4.4 (`FileAccess.store_*` retour bool) — Resource abstrait l'API stable.

### D-2 — Layout fichier : sub-folder `user://settings/<system>.tres`

```
user://
├── savegame.cfg          # ADR-0010 (state runtime)
└── settings/             # ADR-0014 (préférences user)
    ├── camera.tres
    ├── input.tres
    └── audio.tres        # future
```

Sub-folder isolated évite collision noms de fichiers, scalable (audio, accessibility, graphics futurs), simplifie wipe-settings (reset folder entier vs delete N fichiers à la racine).

`DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://settings/"))` appelé par helper `SettingsResource._ensure_dir()` la première fois qu'un load/save est demandé. Idempotent. Erreur ignorée si dossier existe déjà.

### D-3 — Schema versioning : champ `_settings_version: int` + migration forward-only

Chaque Resource concrète DOIT déclarer :

```gdscript
class_name CameraSettings extends Resource

const CURRENT_VERSION: int = 1

@export var _settings_version: int = CURRENT_VERSION
@export_range(0.0005, 0.012) var mouse_sensitivity: float = 0.0022
@export var mouse_y_inverted: bool = false
@export_range(-15.0, 15.0) var fov_user_offset: float = 0.0

static func create_defaults() -> CameraSettings:
    var s := CameraSettings.new()
    s._settings_version = CURRENT_VERSION
    return s

static func migrate_from(version: int, raw: CameraSettings) -> CameraSettings:
    # Forward-only migration. v0 → v1 : aucune (initial). Futur v1 → v2 : ajouter champ ici.
    if version >= CURRENT_VERSION:
        return raw
    push_warning("[camera-settings] migrating v%d → v%d" % [version, CURRENT_VERSION])
    raw._settings_version = CURRENT_VERSION
    return raw
```

Helper `SettingsResource.load_or_default()` détecte `loaded._settings_version < CURRENT_VERSION` et appelle `<Type>.migrate_from(loaded._settings_version, loaded)`. Fallback defaults si migration retourne null (impossibilité).

**Rejet de versioning par filename** (`camera_settings_v1.tres` → `camera_settings_v2.tres`) : casse path canonique, complique purge, force scan dossier à chaque boot.

### D-4 — Corruption fallback : defaults + warning + rewrite-on-next-save

Si `ResourceLoader.load(path) as <Type>` retourne `null` (file truncated, byte-flipped, schema mismatch radical, ResourceFormatLoader rejection), helper procède **uniformément** :

1. `var fresh := <Type>.create_defaults()` — instance defaults via factory.
2. `push_warning("[settings] %s corrupted or unreadable, using defaults" % path)` — log explicite.
3. **Pas de réécriture automatique au boot** — laisse le fichier corrompu en place. Réécriture seulement au prochain `save()` explicite (déclenché par utilisateur via menu Settings, ou flush-on-quit). Justification : si le fichier est corrompu par bug récurrent (write race, disk error, OS crash mid-write), réécrire silencieusement masque le pattern et empêche QA/utilisateur de voir le warning à chaque boot. Lever silencieux = anti-debug.
4. Retourner `fresh` au caller.

**Rejet defaults silencieux** : masque les corruptions persistantes. **Rejet abort boot** : viole Pillar 1 anti-friction (player ne peut jamais être bloqué par un settings). **Rejet restore-from-backup** : pas de backup MVP (multi-fichier déféré Tier 2+ OQ-SET-2).

### D-5 — Ownership lifecycle : helper static class `SettingsResource` (zero autoload)

Décision : **pas d'autoload SettingsManager**. Pattern :

```gdscript
class_name SettingsResource extends RefCounted

static func _resolve_path(system: String) -> String:
    return "user://settings/%s.tres" % system

static func _ensure_dir() -> void:
    var abs := ProjectSettings.globalize_path("user://settings/")
    if not DirAccess.dir_exists_absolute(abs):
        DirAccess.make_dir_recursive_absolute(abs)

static func load_or_default(system: String, default_factory: Callable, migrate: Callable) -> Resource:
    _ensure_dir()
    var path := _resolve_path(system)
    var loaded: Resource = null
    if FileAccess.file_exists(path):
        loaded = ResourceLoader.load(path)
    if loaded == null:
        if FileAccess.file_exists(path):
            push_warning("[settings] %s corrupted, using defaults" % path)
        return default_factory.call()
    var current_version: int = loaded.get("_settings_version") if loaded.get("_settings_version") != null else 0
    var migrated: Resource = migrate.call(current_version, loaded)
    if migrated == null:
        push_warning("[settings] %s migration failed, using defaults" % path)
        return default_factory.call()
    return migrated

static func save(resource: Resource, system: String) -> Error:
    _ensure_dir()
    var path := _resolve_path(system)
    return ResourceSaver.save(resource, path)
```

**Justification zero autoload** : settings consumer (CameraSystem, InputManager, AudioSystem) charge SES propres settings au `_ready()` via 1 ligne :

```gdscript
# Dans CameraSystem._ready()
_settings = SettingsResource.load_or_default(
    "camera",
    Callable(CameraSettings, "create_defaults"),
    Callable(CameraSettings, "migrate_from"),
) as CameraSettings
```

Aucun coupling cross-system. Aucun autoload supplémentaire à orchestrer (cohérent avec ADR-0007 D-1 fixe l'ordre autoload à 4 entries — settings ne s'y ajoute pas). RefCounted helper, pas de state global.

**Rejet autoload SettingsManager** : ajouterait position autoload #5, complexifierait ADR-0007 D-1, créerait single-point-of-failure pour boot, pas justifié par le pattern (chaque consumer connaît ses settings sans coordination).

**Rejet absorption par SaveLoadSystem** : viole sa responsabilité (savegame state runtime) et re-litigerait son format (ConfigFile vs Resource). SaveLoadSystem reste outbound-zero focus savegame.

### D-6 — Save trigger : explicit owner-driven (no auto-save MVP)

Settings sont sauvegardés **uniquement** sur trigger explicite du système owner :

- Menu/Settings UI Tier 2+ : `apply` button → owner system reçoit changement → `SettingsResource.save(resource, "camera")`.
- Flush-on-quit : owner connecte `NOTIFICATION_WM_CLOSE_REQUEST` (R-SAV-9 pattern, mais owner-side, pas SaveLoadSystem).
- Debug/QA : commande console ou hot-reload editor.

**Pas de save() automatique en `_process`** (forbidden pattern hot path). **Pas de batched save coordinator** (over-engineering MVP, debounce inutile vu rare).

### D-7 — Defaults : factory function obligatoire

Chaque Resource concrète DOIT exposer `static func create_defaults() -> <Type>` retournant une instance avec valeurs par défaut hardcodées. Justification :

- Source canonique des valeurs par défaut visible 1 endroit (vs `@export var x: float = 0.0022` éparpillé).
- Permet tests unitaires d'asserter defaults sans ResourceLoader.
- Permet helper `load_or_default()` d'instancier sans coupling au type concret (Callable injection).

### D-8 — Engine compat : `duplicate(true)` only (pas `duplicate_deep()`)

`duplicate_deep()` (Godot 4.5+, post-cutoff) NON utilisé pour MVP Settings. Schémas settings sont **flat** par GDD Tuning Knobs (camera/input : 3-6 primitives par resource). `duplicate(true)` (avec sub-resource flag, stable depuis 3.x) couvre le cas si une settings veut référencer une autre resource (rare, pas de cas MVP).

Si un futur settings nécessite nested resources non-trivial (e.g. `accessibility_profile.tres` → list of `colorblind_filter.tres`), évaluer migration vers `duplicate_deep()` (et bumper engine compat HIGH risk dans cette ADR).

### D-9 — Forbidden patterns enregistrés au registry

Cette ADR ajoute 2 forbidden patterns à `docs/architecture/control-manifest.md` (ou `docs/registry/architecture.yaml` si format YAML adopté) :

| Pattern | Layer | Niveau |
|---------|-------|--------|
| `FileAccess.store_*\|FileAccess.get_*` dans path référençant `user://settings/` | All | BLOCKING |
| Hardcoded settings value (mouse_sensitivity, fov_user_offset, focus_regain_window_ms, etc.) dans `src/gameplay/**/*.gd` ou `src/core/**/*.gd` non issu d'une instance Resource lue au boot | Foundation+Gameplay | BLOCKING |

Lint statique cover-all : grep `\bFileAccess\.\(store\|get\)_` croisé avec mention `user://settings`. Rejected.

### D-10 — Outbound-only : settings resources zero references consumers

Chaque `<System>Settings extends Resource` est outbound-zero — aucune référence (preload, get_node, autoload name) vers consumer system. Cohérent avec ADR-0005 D-10 (MovementController), ADR-0011 D-7 (LevelSystem). Une settings resource est une **donnée passive**, le consumer la lit.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    user:// filesystem                       │
│                                                             │
│   savegame.cfg              settings/                       │
│   (ADR-0010 ConfigFile)     ├── camera.tres                 │
│                             ├── input.tres                  │
│                             └── audio.tres (future)         │
└─────────────────────────────────────────────────────────────┘
            │                              │
            │ SaveLoadSystem               │ SettingsResource
            │ (autoload, ADR-0010)         │ (helper static, ADR-0014)
            │                              │
            ▼                              ▼
   ┌────────────────────┐       ┌──────────────────────┐
   │ Credit / Shop /    │       │ CameraSystem._ready  │
   │ Upgrade savegame   │       │ InputManager._ready  │
   │ state              │       │ AudioSystem._ready   │
   └────────────────────┘       └──────────────────────┘
```

### Key Interfaces

```gdscript
# Helper static class (zero state, zero autoload)
class_name SettingsResource extends RefCounted

static func load_or_default(
    system: String,
    default_factory: Callable,  # () -> Resource
    migrate: Callable,           # (int, Resource) -> Resource
) -> Resource

static func save(resource: Resource, system: String) -> Error

# Per-system Resource contract
class_name <System>Settings extends Resource

const CURRENT_VERSION: int = <int>

@export var _settings_version: int = CURRENT_VERSION
# ... domain-specific @export properties ...

static func create_defaults() -> <System>Settings
static func migrate_from(version: int, raw: <System>Settings) -> <System>Settings
```

### Implementation Guidelines

1. **Création d'un nouveau settings type** : créer `src/core/settings/<system>_settings.gd` extends `Resource` ; déclarer `CURRENT_VERSION`, `_settings_version` exporté, properties `@export`-typées avec defaults inline ; implémenter `create_defaults()` et `migrate_from()`.
2. **Consumer lifecycle** : dans `<Consumer>._ready()`, charger via `SettingsResource.load_or_default("<system>", Callable(<Type>, "create_defaults"), Callable(<Type>, "migrate_from"))`. Cast `as <Type>`. Stocker dans `var _settings: <Type>` member (cache, pas re-load).
3. **Save trigger** : exposer méthode publique `save_settings()` sur consumer (appelée par Menu/Settings UI ou flush-on-quit). Implémentation : `SettingsResource.save(_settings, "<system>")`. Logger l'Error retournée.
4. **Migration** : `migrate_from()` doit gérer `version < CURRENT_VERSION` (forward-only). Retourner `null` si impossible (force fallback defaults). Logger `push_warning()` à chaque migration appliquée.
5. **Tests** : 1 unit test par Resource type (defaults assertion + migration round-trip) + 1 integration test par consumer (load → assert → save → reload → assert identity).
6. **Sub-folder bootstrap** : `_ensure_dir()` est idempotent — appelé par helper avant chaque load/save. Pas besoin de pré-créer manuellement.
7. **Anti-pattern à éviter** : NE PAS instancier `<Type>.new()` directement comme defaults — toujours via `<Type>.create_defaults()` (factory ensures `_settings_version` cohérent).

## Alternatives Considered

### Alternative 1: ConfigFile partagé avec savegame (extend ADR-0010)

- **Description** : ajouter section `[settings.camera]`, `[settings.input]` dans `user://savegame.cfg`. Verbs SaveLoad existants (load_int, save_int, load_string_array, save_string_array) gèrent settings.
- **Pros** : 1 seul fichier, cohérence ADR-0010, zero new pattern.
- **Cons** : (a) settings flat key-value perd typage natif Resource (`@export_range`, `@export_enum`, validation IDE) ; (b) couple lifecycle settings à savegame (delete savegame → perd settings, pas désiré) ; (c) impossible de wipe-settings sans wipe-savegame ; (d) viole séparation conceptuelle préférences-user vs state-runtime ; (e) verbs SaveLoad manqueraient `load_float` typé, etc.
- **Estimated Effort** : LOW (réutilise ADR-0010 verbs).
- **Rejection Reason** : couplage lifecycle settings/savegame inacceptable. Settings doit survivre wipe-savegame (réinstallation, new-game). Typage Resource est la valeur ajoutée du pattern Godot.

### Alternative 2: Autoload `SettingsManager` central

- **Description** : autoload `SettingsManager` exposant `get_camera_settings() / get_input_settings() / save_all()`. Charge tous les settings au `_ready()`. Position #5 dans ADR-0007 D-1.
- **Pros** : 1 point d'orchestration, save coordonné, cache central.
- **Cons** : (a) ajoute autoload (modifie ADR-0007 D-1, complexifie boot order) ; (b) couplage centralisé inutile (chaque consumer connaît ses settings) ; (c) single-point-of-failure boot ; (d) viole loose coupling pattern adopté pour Camera/Movement/Level (chaque système outbound-zero, autonomy-first) ; (e) over-engineering pour 2-3 settings types MVP.
- **Estimated Effort** : MEDIUM (autoload + ADR-0007 amendment).
- **Rejection Reason** : pas justifié par le pattern. Helper static class atteint 100% des objectifs sans new autoload.

### Alternative 3: Per-system file naming `camera_settings.tres` (pas de sub-folder)

- **Description** : path canonique `user://camera_settings.tres`, `user://input_settings.tres` (flat à la racine `user://`).
- **Pros** : marginal (1 ligne de moins pour `_ensure_dir()`).
- **Cons** : (a) pollue racine `user://` avec N fichiers (settings + savegame + futurs logs/cache/replay) ; (b) wipe-settings demande grep par suffixe ; (c) pas scalable (audio, accessibility, graphics futurs aboutissent à 6+ fichiers à la racine).
- **Estimated Effort** : équivalent.
- **Rejection Reason** : sub-folder coût marginal pour gain organisation long-terme. Pattern OS-friendly (Steam/itch.io users navigueront moins ce dossier mais structure propre matters pour QA / debug).

### Alternative 4: Versioning par filename `camera_settings_v1.tres`

- **Description** : suffixer le filename par version. Migration = créer `camera_settings_v2.tres` à partir de `_v1`.
- **Pros** : version visible dans le filesystem, archivage trivial.
- **Cons** : (a) casse path canonique (helper doit scanner dossier pour trouver dernière version) ; (b) explosion fichiers anciennes versions ; (c) complique purge ; (d) pas de précédent dans le projet (savegame ADR-0010 versionne par champ `_save_version` dans le ConfigFile, cohérence souhaitable).
- **Estimated Effort** : MEDIUM (logique scan + ordering).
- **Rejection Reason** : champ dans-fichier est plus simple, cohérent avec ADR-0010 R-SAV-version, et n'a aucun désavantage concret pour settings (rare migration).

### Alternative 5: JSON via FileAccess + JSON.parse_string

- **Description** : settings en JSON éditable utilisateur (`user://settings/camera.json`).
- **Pros** : human-readable, editable text editor, zero engine API risk.
- **Cons** : (a) breaking change Godot 4.4 `FileAccess.store_*` retour bool (require workaround) ; (b) parsing manuel via `JSON.parse_string` retourne Variant non typé (lose `@export_range` validation) ; (c) injection risk (utilisateur peut casser le format) ; (d) pas idiomatique Godot (Resource est le pattern natif).
- **Estimated Effort** : LOW.
- **Rejection Reason** : Resource offre human-readable (text-based .tres) ET typage natif. JSON ne gagne rien.

## Consequences

### Positive

- Décision de format figée pour TOUS les futurs settings (audio, accessibility, graphics, controls remap Tier 2+).
- Pattern simple : 1 helper static + 1 Resource class par système. Aucun autoload. Aucun couplage cross-system.
- Typage natif Godot via `@export` — validation IDE, Tuning Knob `@export_range` enforce safe ranges au boot.
- Lifecycle settings DÉCOUPLÉ de savegame — wipe-savegame n'efface pas les préférences user (UX critique).
- Sub-folder `user://settings/` scalable et propre.
- Versioning + migration framework prêt pour Tier 2+ (ajout champ accessibilité, remap bindings, etc.).
- Corruption fallback uniforme = anti-friction Pillar 1 garanti (boot ne bloque jamais sur settings).

### Negative

- 2 patterns de persistance dans le projet : ConfigFile (savegame ADR-0010) + Resource (settings ADR-0014). Cognitive load pour nouveaux contributeurs (devra être documenté en `docs/architecture/architecture.md`).
- `migrate_from()` doit être maintenu à chaque bump `CURRENT_VERSION` — coût logiciel cumulatif (mitigation : MVP settings flat → migrations rares, version 1 stable indéfiniment probable).
- Helper static class `SettingsResource` ne peut pas mock easily (Callable injection fonctionne mais lourd dans tests). Mitigation : tests directs sur Resource concrètes via `<Type>.create_defaults()`.

### Neutral

- `user://settings/` empty au first launch — ajoute 1 mkdir au boot du premier consumer (idempotent, ~ms).
- `_settings_version` exporté visible dans `.tres` text — utilisateur peut éditer manuellement (acceptable Tier 1 anti-cheat naïf).

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Schema drift entre `@export` et `migrate_from()` | LOW | MEDIUM | Test unit obligatoire `test_<type>_defaults_version_matches_current` qui asserte `create_defaults()._settings_version == CURRENT_VERSION`. |
| `ResourceLoader.load()` retourne instance partielle (pas null) sur schema mismatch | LOW | MEDIUM | Cast explicit `as <Type>` retourne null si type-mismatch. Fallback defaults activé. Test corruption byte-flip valide ce path. |
| `duplicate(true)` insuffisant si nested resources future | LOW | LOW | MVP settings flat, pas de nested. Future review : si Accessibility settings nested, évaluer `duplicate_deep()` 4.5+ et bump engine compat HIGH. |
| Settings file race condition (utilisateur édite manuellement pendant que jeu save) | LOW | LOW | Last-write-wins acceptable Tier 1. Atomic tmp+rename déféré Tier 2+ (cohérent ADR-0010 OQ-SAV-4). |
| Sub-folder `user://settings/` pas créé (permission revoquée) | LOW | MEDIUM | `make_dir_recursive_absolute()` retourne Error — helper logue warning et continue avec defaults runtime (pas de save persistent ce session). Comportement identique à corruption fallback. |
| Test pollution `user://settings/` cross-test | MEDIUM | LOW | Tests doivent utiliser path mock ou cleanup `after_test()`. Convention : préfixe `test_` dans system name (`SettingsResource.load_or_default("test_camera", ...)`). |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| Boot CPU (settings load 1× per consumer) | n/a | < 1 ms par Resource (single .tres < 1 KB) | < 5 ms total tous settings |
| Save CPU (rare, on-quit ou menu apply) | n/a | < 5 ms par Resource | n/a (off hot path) |
| Memory (settings instances cached) | n/a | < 1 KB par Resource × N consumers | < 10 KB total |
| Disk footprint (`user://settings/`) | 0 | < 5 KB (3-5 fichiers MVP) | < 100 KB Tier 2+ |

Settings n'impactent PAS le frame budget gameplay (load = boot one-shot, save = rare event utilisateur).

## Migration Plan

Cette ADR introduit un nouveau pattern, pas de migration code existant requise (camera/input n'ont aucune persistance settings actuellement). Migration = activation des stories Blocked.

1. **ADR Accepted** → unblock stories camera-013 + input-010 (Status `Blocked` → `Ready` ; ajouter sections ADR Governing Implementation + Implementation Notes).
2. **TR registry** : `TR-cam-006` et `TR-inp-009` : `covered_by: [ADR-0014]` (au lieu de `[]`).
3. **Control manifest** : ajouter 2 forbidden patterns (D-9) au prochain manifest version bump.
4. **Architecture.md** : ajouter §X "Persistence patterns" comparant ADR-0010 (savegame, ConfigFile) vs ADR-0014 (settings, Resource) — documente le cognitive load mitigé (2 patterns assumés et justifiés).
5. **Sprints** : camera-013 + input-010 entrent en backlog Polish P3 (non-MVP). Implémentation à programmer post-Sprint 1 release.

**Rollback plan** : si l'ADR pose problème (e.g. Resource versioning trop fragile en pratique), l'ADR peut être superseded par une révision migrant les settings vers ConfigFile (alternative 1). Coût rollback : refactor 2 settings types (camera, input) — environ 1 jour de travail. Acceptable.

## Validation Criteria

Cette ADR est validée par les ACs des stories camera-013 + input-010 + (futur) audio-XXX :

- [ ] Camera settings : `mouse_sensitivity`, `mouse_y_inverted`, `fov_user_offset` persistés round-trip identité.
- [ ] Input settings : `mouse_sensitivity`, `mouse_y_inverted`, `mouse_capture_at_boot`, `focus_regain_window_ms`, `debug_overlay_default`, `latency_anomaly_threshold_ms` persistés round-trip identité.
- [ ] Corruption fallback : byte-flip simulé → defaults appliqués + warning loggé + aucun crash boot.
- [ ] First-launch : pas de fichier → defaults silencieux (no warning) + création fichier au premier save.
- [ ] Migration : v1 → v2 (futur bump CURRENT_VERSION) → champ nouveau rempli avec default + warning loggé.
- [ ] Sub-folder bootstrap : `user://settings/` n'existe pas → `_ensure_dir()` crée idempotent.
- [ ] Forbidden pattern lint : aucun `FileAccess.store_*` ciblant `user://settings/` dans le code.
- [ ] Forbidden pattern lint : aucun hardcoded settings value (mouse_sensitivity, etc.) dans gameplay code.
- [ ] Performance : settings load p99 < 1 ms par Resource (mesuré via test instrumentation).

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|--------------|--------|-------------|---------------------------|
| `design/gdd/camera-system.md` | Camera | Tuning Knobs `mouse_sensitivity`, `mouse_y_inverted`, `fov_user_offset` persistés cross-session (TR-cam-006) | Resource `CameraSettings` typé + helper `SettingsResource.load_or_default("camera", ...)` au CameraSystem._ready() + save explicit on settings change. |
| `design/gdd/input-system.md` | Input | Tuning Knobs `mouse_sensitivity`, `focus_regain_window_ms`, `debug_overlay_default` persistés (TR-inp-009) | Resource `InputSettings` typé + helper `SettingsResource.load_or_default("input", ...)` au InputManager._ready() + save explicit. |
| (futur) `design/gdd/audio-system.md` | Audio | Volume sliders + mute persistés Tier 2+ | Pattern réutilisable : Resource `AudioSettings` + même helper. |

> Cette ADR ratifie un pattern transverse — chaque GDD consumer ré-utilise SettingsResource sans new ADR (sauf cas exceptionnel : Accessibility settings pourraient être gouvernés par ADR-0015 Accessibility Interface Layer si nested resources non-trivial).

## Related

- ADR-0010 Save/Load Persistence Architecture (ConfigFile Ratification) — décision sœur pour savegame state runtime. Cette ADR diverge explicitement (Resource pour settings, justifié schémas stables vs runtime fluide).
- ADR-0007 GameStateManager — D-1 fixe l'ordre autoload à 4 entries ; cette ADR confirme zero new autoload.
- ADR-0004 Input API Focus Handling — D-7 main thread only ; cette ADR confirme settings I/O main thread (helper static, pas thread-safe explicitement, pas requis MVP).
- (futur) ADR-0015 Accessibility Interface Layer — pourrait s'intégrer à SettingsResource ou héberger ses propres settings selon nested complexity ; à trancher au moment de la création ADR-0015.
- Camera story-013 `production/epics/camera-system/story-013-camera-settings-save-load.md` — débloquée par cette ADR.
- Input story-010 `production/epics/input-system/story-010-settings-persistence.md` — débloquée par cette ADR.
