# ADR-0010: Save/Load Persistence Architecture (ConfigFile Ratification)

## Status

Accepted (promoted 2026-04-27 from Proposed — débloque shop-system stories 003/005/010/011/015 et credit-economy/save-load epic Sprint 1)

## Date

2026-04-27

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core (file I/O, persistence) |
| **Knowledge Risk** | MEDIUM — Godot 4.4 a changé `FileAccess.store_*` de `void` à `bool` (cf. `docs/engine-reference/godot/breaking-changes.md`). Cet ADR retient `ConfigFile` comme abstraction au-dessus de FileAccess, ce qui isole la surface code du breaking change (R-SAV-2 du GDD justifie ce choix). |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md` (4.4 row `FileAccess.store_*`), godot-specialist validation 2026-04-27 (sur draft JSON initial — pivot vers ConfigFile per GDD), `design/gdd/save-load-system.md` r1 (R-SAV-1 à R-SAV-17, EC-SAV-1 à EC-SAV-20, F-SAV-1, AC-SAV-1 à AC-SAV-33, OQ-SAV-1 à OQ-SAV-10). |
| **Post-Cutoff APIs Used** | `ConfigFile.set_value` / `get_value` / `save` / `load` (stable depuis Godot 3.x). `OS.has_feature("debug")` (stable). Aucune API 4.5/4.6-only utilisée — choix ConfigFile justifié par stabilité cross-version. |
| **Verification Required** | 33 ACs définis dans `save-load-system.md` §Acceptance Criteria couvrent cet ADR. Tests prioritaires : AC-SAV-1 boot fichier inexistant, AC-SAV-3 boot fichier corrompu, AC-SAV-18 save sur permission revoquée, AC-SAV-21 NOTIFICATION_WM_CLOSE_REQUEST handler, AC-SAV-32/33 chain-blocked PROVISIONAL OQ-SAV-1/2. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0007 (GameStateManager — D-1 fixe l'ordre autoload `InputManager → GSM → SaveLoadSystem → AudioSystem`, position 3 verrouillée pour SaveLoad ; D-4 process_mode discipline `PROCESS_MODE_ALWAYS` pour autoloads). |
| **Enables** | ADR-0012 Upgrade Application Strategy (à venir — résout OQ-SAV-1 sur la consommation Save/Load par Upgrade). Future ADR Tier 2+ atomic write (résout OQ-SAV-4). Future ADR Tier 2+ multi-profile (résout OQ-SAV-6). |
| **Blocks** | shop-system epic Sprint 1 (R-SHP-8 persist owned_upgrades synchrone post-achat AVANT apply_upgrade — exige API SaveLoad disponible). credit-economy-system epic Sprint 1 (R-CRD-11/12 boot hydrate + quit save). save-load-system implementation epic. |
| **Ordering Note** | Doit être Accepted avant que les stories Sprint 1 du shop-system, credit-economy-system, et save-load-system entrent en implémentation. L'ADR ratifie une décision déjà prise dans le GDD save-load-system.md r1 — son acceptation rend la décision opposable cross-ADR. |

## Context

### Problem Statement

Le GDD `design/gdd/save-load-system.md` r1 (Designed 2026-04-27, 548 lignes) a pris la décision de format de persistance dans R-SAV-2 :

> **R-SAV-2 — Storage backend : ConfigFile sur `user://savegame.cfg`** — Format MVP : Godot `ConfigFile`, section unique `[data]`, clés string, valeurs typed primitive ou Array. **Rejet JSON** : verbeux, pas de typage natif, parsing manuel (overhead). **Rejet Resource (.tres)** : require schema class_name, casse migration MVP→Tier2+. **Rejet binary FileAccess** : attention Godot 4.4 breaking change `FileAccess.store_*` retourne `bool` (pas `void`) — ConfigFile abstrait l'API stable.

Cette décision **n'a pas encore d'ADR** la formalisant. Sans ADR, les conséquences architecturales suivantes sont fragiles :

1. **Cross-ADR drift** : un futur GDD Tier 2+ (Settings, Telemetry, Multi-profile) pourrait re-litiger le format à chaque ajout de système consommateur. Sans ADR opposable, chaque GDD documente sa propre justification → divergence prévisible.
2. **Forbidden patterns absents** : aucune entrée dans `docs/registry/architecture.yaml` n'interdit l'accès direct au cache `_config: ConfigFile` privé de SaveLoadSystem, ni l'accès thread-non-main aux verbes publics. Les conventions `outbound-only` (R-SAV-17), `zero signal` (R-SAV-10), `zero orchestration` (R-SAV-11) existent dans le GDD mais ne sont pas applicables par lint cross-projet.
3. **Engine Compatibility traçable** : la justification du rejet binary FileAccess (Godot 4.4 breaking change) doit être rappelée à chaque review architecture pour résister aux propositions de "switcher en binary pour la compacité". Un ADR formalise la décision avec son contexte engine.
4. **Locked contracts traçables** : les contrats provisoires Credit r1 (R-CRD-11/12) et Shop r1 (R-SHP-3/8) qui dépendent de `SaveLoad.load_int / save_int / load_string_array / save_string_array` n'ont pas de point d'ancrage architectural unique — ils référencent le GDD save-load-system.md, mais la pérennité du contrat (nom des verbes, signatures, sémantique des defaults) doit être lockable au niveau ADR pour permettre `/architecture-review` cross-system.

Cet ADR **ratifie** la décision GDD R-SAV-2 et l'élève au niveau architectural : il fournit les entrées registry, les forbidden patterns, et le rappel engine-compat permettant aux outils cross-ADR (`/architecture-review`, `/create-stories`, `/dev-story`) de raisonner sur Save/Load comme un système première classe.

L'ADR ne propose **aucune** modification du GDD r1. Toute divergence détectée entre cet ADR et le GDD doit être résolue en faveur du GDD (autorité design) — l'ADR formalise, il ne re-décide pas.

### Constraints

- **Engine** : Godot 4.6 + GDScript. Pas de bibliothèque tierce. Pas de GDExtension. Cohérent avec `.claude/docs/technical-preferences.md` (Engine Specialists : godot-gdscript-specialist + godot-specialist).
- **Plateforme** : PC desktop (Windows/macOS/Linux). `user://` est résolu par Godot vers une location système locale (NTFS/APFS/ext4) — `%APPDATA%/Godot/app_userdata/<projectName>/` sur Windows, `~/.local/share/godot/app_userdata/<projectName>/` sur Linux, `~/Library/Application Support/Godot/...` sur macOS. Dossier garanti existant avant `_ready()` (Godot bootstrap).
- **Pillar 1 latency** : F-SAV-1 du GDD valide budget `B ≈ 0.3 ms` à `S = 0.1 KB` SSD M1 (marge ×55 sur 16.6 ms). Ce plafond est respecté par ConfigFile.save() synchrone hors hot path gameplay.
- **Single-player** : 1 fichier, 1 profil, pas de cloud sync, pas de chiffrement MVP. Multi-profile et chiffrement déférés Tier 2+/3 (OQ-SAV-6, OQ-SAV-7).
- **Anti-cheat** : niveau naïf accepté Tier 1 (audience solo non-développeur). Le fichier `user://savegame.cfg` est lisible et éditable. Risque accepté.
- **Thread** : main thread only. Cohérent avec `.claude/rules/input-singleton-main-thread-only.md` et `.claude/rules/level-signals-main-thread-only.md`.
- **Couplage** : SaveLoadSystem est outbound-zero — aucune référence vers consumers (Credit, Shop, Secret, Upgrade, HUD, Audio, Input). Pattern outbound-only (R-SAV-17) cohérent avec ADR-0005 D-10 (MovementController), ADR-0011 D-7 (LevelSystem).

### Requirements

- **REQ-1** : ratifier le format ConfigFile retenu par le GDD save-load-system.md R-SAV-2 — la décision n'est pas re-litigée.
- **REQ-2** : exposer 4 verbes MVP + 2 verbes Tier 2+ + 1 getter méta avec signatures **exactes** au GDD R-SAV-4 (String keys, void save returns, Array[StringName] / Array[int] returns avec validation typée). Aucune renomination, aucun changement de signature.
- **REQ-3** : verrouiller la position autoload **#3 sur 4** (`InputManager → GSM → SaveLoadSystem → AudioSystem`) cohérent avec ADR-0007 D-1.
- **REQ-4** : verrouiller `process_mode = PROCESS_MODE_ALWAYS` (R-SAV-8 + ADR-0007 D-4 discipline).
- **REQ-5** : empêcher tout accès direct au cache `_config: ConfigFile` privé hors de `src/core/save_load_system.gd` (forbidden pattern registry).
- **REQ-6** : empêcher tout appel SaveLoad depuis Thread / WorkerThreadPool / call_deferred cross-thread (forbidden pattern registry, généralisation ADR-0004 D-7).
- **REQ-7** : enregistrer dans `docs/registry/architecture.yaml` : (a) state ownership `persistent_save_data` ; (b) interface contract `save_load_persistence` ; (c) api decision `save_load_serialization_format` ; (d) 2 forbidden patterns nouveaux.
- **REQ-8** : laisser explicitement à des ADRs futurs les décisions Tier 2+ déférées par le GDD (atomic tmp+rename OQ-SAV-4 ; multi-profile OQ-SAV-6 ; chiffrement OQ-SAV-7 ; async batch OQ-SAV-3 ; migration framework OQ-SAV-5 ; settings split OQ-SAV-2). Cet ADR ne tranche aucune de ces questions.

## Decision

### D-1 — Format ratifié : ConfigFile (`user://savegame.cfg`)

Cet ADR ratifie sans modification la décision GDD R-SAV-2 :

- **Format** : Godot `ConfigFile` natif.
- **Path canonique** : `user://savegame.cfg`. Single fichier, single section `[data]`, flat keys (R-SAV-3).
- **Engine API** : `ConfigFile.set_value(section, key, value)` / `get_value(section, key, default)` / `save(path)` / `load(path)`. Stables depuis Godot 3.x — non-affectés par les breaking changes 4.4-4.6.

Justification du choix (per GDD R-SAV-2, élevée au niveau architectural) :

1. **Rejet JSON** : verbosité du format, pas de typage natif (tout cast manuel), parsing JSON.parse_string + cast élément par élément requis pour Array[StringName] (godot-specialist Q4 2026-04-27). Coût additionnel sans gain pour le scope MVP (3 clés top-level).
2. **Rejet Resource (.tres)** : nécessite un schema `class_name` figé. Toute évolution Tier 2+ (ajout de clé, split section) casse les .tres existants. ConfigFile, sans schema, accepte des clés inconnues silencieusement (forward-safe).
3. **Rejet binary FileAccess** : Godot 4.4 a changé `FileAccess.store_*` de `void` à `bool` — toute lecture/écriture binaire devrait gérer ces retours, multipliant les chemins de code error-handling. ConfigFile abstrait cette API stable.
4. **Acceptation atomicité non-MVP** : ConfigFile.save() n'est **pas atomique** au niveau filesystem (EC-SAV-15). Crash mid-write peut tronquer le fichier → `ERR_FILE_CORRUPT` au prochain boot (EC-SAV-2). Risque accepté MVP (cas rare 2026 PC desktop avec UPS/battery). Atomic write tmp+rename déféré Tier 2+ via OQ-SAV-4.

### D-2 — API publique typée verrouillée

Cet ADR verrouille l'API exposée par SaveLoadSystem au signatures **identiques** au GDD R-SAV-4 :

```gdscript
# src/core/save_load_system.gd — autoload Node #3 (post-GSM, pre-Audio)
extends Node

# === MVP API (4 verbes) ===
func load_int(key: String, default: int) -> int
func save_int(key: String, value: int) -> void

func load_string_array(key: String, default: Array[StringName]) -> Array[StringName]
func save_string_array(key: String, value: Array[StringName]) -> void

# === Tier 2+ API réservée (2 verbes) ===
func load_int_array(key: String, default: Array[int]) -> Array[int]
func save_int_array(key: String, value: Array[int]) -> void

# === Méta (1 getter) ===
func get_save_version() -> int
```

**Sémantique verrouillée** :
- `load_*` retournent `default` sur fichier absent / corrompu / type mismatch / élément Array invalide (R-SAV-6, R-SAV-12). `push_warning` émis sur corruption type. Jamais de crash, jamais de prompt utilisateur.
- `save_*` retournent `void` (PAS `bool` — différence clé avec un draft JSON antérieur). En cas d'échec ConfigFile.save() (`ERR_FILE_NO_PERMISSION`, disque plein), `push_error` est émis avec le code erreur ; l'appelant ne reçoit **pas** de feedback de succès/échec. Justification GDD : write-through synchrone implique « si l'appelant a la main après save_int, la write a réussi (ou un push_error a été émis) ». Le caller n'a pas de chemin de récupération significatif (le fichier reste dans son état pré-write si la save a échoué — l'état RAM consumer reste cohérent indépendamment).
- `load_string_array` normalise `String → StringName` au load (ConfigFile sérialise `StringName` comme `String` entre quotes, R-SAV-12).
- `get_save_version()` retourne `_save_version` lu au boot (default `1` si absent).

**Aucune autre méthode publique au MVP**. Pas de getter générique `Variant`-typed (force le typage explicite côté consumer). Pas d'accès direct à `_config: ConfigFile`.

### D-3 — Position autoload verrouillée (#3 sur 4)

L'ordre autoload `InputManager → GameStateManager → SaveLoadSystem → AudioSystem` est verrouillé par ADR-0007 D-1. Cet ADR confirme et formalise pour tous les consumers :

- **Garantie** : `_ready()` SaveLoadSystem précède `_ready()` de **tous les consumers gameplay** (Credit, Shop, Secret, Upgrade). Donc un consumer peut appeler `SaveLoad.load_int(...)` dès son propre `_ready()` sans race (R-SAV-7).
- **Conséquence** : tout futur autoload qui consomme SaveLoad doit être déclaré APRÈS SaveLoadSystem dans `project.godot`. Toute proposition de déplacer SaveLoadSystem (ex: position 1) requiert un amendement formel ADR-0007 + cet ADR.

### D-4 — `process_mode = PROCESS_MODE_ALWAYS`

Cohérent avec ADR-0007 D-4 (autoloads en PROCESS_MODE_ALWAYS) et GDD R-SAV-8. SaveLoadSystem continue à fonctionner pendant `get_tree().paused = true` — un consumer peut appeler `SaveLoad.save_int(...)` depuis un menu pause sans risque que la save soit suspendue.

### D-5 — Outbound-zero (zéro signal, zéro orchestration)

Cet ADR verrouille les conventions GDD R-SAV-10 (zero outbound signals) + R-SAV-11 (zero orchestration) + R-SAV-17 (outbound-only towards engine, inbound-only depuis consumers) :

- **SaveLoadSystem n'émet aucun signal au MVP**. Si Tier 2+ introduit `save_completed(key, success)` pour async batch, ce sera un amendement de cet ADR (et du GDD).
- **SaveLoadSystem ne consomme aucun signal des autres systèmes**. Spécifiquement : pas de `state_changed(MENU)` connecté pour déclencher save automatique. Les consumers (Credit R-CRD-12, Shop R-SHP-8) décident *quand* appeler `save_*`.
- **SaveLoadSystem ne référence aucun consumer**. Aucun `class_name`, `NodePath`, `get_node()`, `preload()` vers Credit/Shop/Secret/Upgrade/HUD/Audio/Input. Lint grep des identifiants consumer dans `src/core/save_load_system.gd` = 0 match attendu (forbidden pattern registry).

### D-6 — Schema versioning forward-only via `_save_version`

Verrouille R-SAV-14 + R-SAV-15 : la clé top-level `_save_version: int` est obligatoire dans tout fichier `savegame.cfg` post-MVP. Valeur MVP figée à `1`. Toute modification de schéma (rename clé, change type, split section) DOIT incrémenter `_CURRENT_SAVE_VERSION` et fournir un migration step (ADR successeur ou amendement).

Comportement sur `_save_version` futur (> `_CURRENT_SAVE_VERSION` lu, EC-SAV-11) : warning logué, lecture partielle (clés absentes en version courante = defaults). Pas de crash. Acceptable downgrade scenario rare (utilisateur upgrade vers Tier 2 puis revient au binaire MVP).

### D-7 — Thread safety : main thread only

Toutes les méthodes publiques (`load_int`, `save_int`, `load_string_array`, `save_string_array`, `load_int_array`, `save_int_array`, `get_save_version`) **doivent** assertir `OS.get_thread_caller_id() == OS.get_main_thread_id()` en debug build. Cohérent avec :

- ADR-0004 D-7 (`Input` singleton main-thread only)
- `.claude/rules/input-singleton-main-thread-only.md`
- `.claude/rules/level-signals-main-thread-only.md`

Justification : `ConfigFile` et `FileAccess` ne sont pas documentés thread-safe Godot. Race conditions sur descriptor de fichier OS, corruption mid-write, deadlock sur lock interne sont tous possibles. Cet ADR généralise la règle main-thread-only à tout I/O système Godot dans `src/core/`.

### D-8 — `NOTIFICATION_WM_CLOSE_REQUEST` handler

Verrouille R-SAV-9 : SaveLoadSystem implémente `_notification(what)` qui intercepte `NOTIFICATION_WM_CLOSE_REQUEST` (alt-F4, fermeture fenêtre, signal OS). Le handler appelle `_flush_pending()` qui est **no-op au MVP** grâce au write-through synchrone exhaustif (R-SAV-5) — aucune save dirty ne peut exister entre deux frames. Le hook existe pour absorber Tier 2+ async batch sans casser l'API.

### D-9 — Atomicité tmp+rename : DÉFÉRÉE Tier 2+

Cet ADR **n'introduit pas** d'atomic write au MVP. Le GDD R-SAV-5 + EC-SAV-15 + OQ-SAV-4 documentent que ConfigFile.save() n'est pas atomique au niveau filesystem, et accepte ce risque pour le MVP (cas rare PC desktop 2026 avec UPS/battery, audience solo, single fichier sub-1 KB).

L'atomic write (tmp + DirAccess.rename atomique POSIX/NTFS) est **réservée à un ADR successeur Tier 2+** qui résoudra OQ-SAV-4. Cet ADR successeur devra :
1. Documenter la garantie atomicité par OS (Windows MoveFileEx atomique NTFS même volume ; macOS APFS rename atomique ; Linux ext4 rename atomique).
2. Fournir une migration : remplacer R-SAV-5 step (2) `_config.save(SAVE_FILE_PATH)` par un wrapper `_atomic_save(path, content)` qui write `path.tmp`, fsync, DirAccess.rename(`path.tmp`, `path`).
3. Ajouter un test GUT validant qu'un kill -9 simulé pendant write ne corrompt pas le fichier final.
4. Ajouter une entrée registry `forbidden_patterns: configfile_save_direct_outside_atomic_wrapper` pour empêcher la régression.

### Architecture Diagram

```
┌─────────────────────────────────────┐
│ SaveLoadSystem (autoload #3)        │  PROCESS_MODE_ALWAYS, main thread
│ src/core/save_load_system.gd        │
│                                     │
│  _config: ConfigFile (privé)        │  ← hydraté depuis user://savegame.cfg au _ready()
│  _config_loaded: bool               │
│                                     │
│  Public API (D-2) :                 │
│   load_int / save_int               │ ─┐
│   load_string_array /               │  │ Consumers self-call ces méthodes
│   save_string_array                 │  │ depuis leurs propres handlers
│   load_int_array (Tier 2+) /        │  │ (state_changed, buy_button_pressed)
│   save_int_array (Tier 2+)          │  │
│   get_save_version                  │  │
│                                     │  │
│  _notification(WM_CLOSE_REQUEST) :  │  │
│   _flush_pending() (no-op MVP)      │  │
│                                     │  │   ┌────────────────────────┐
│  Internal (D-1) :                   │ ─┼─→ │ user://                │
│   _config.set_value/save/load       │  │   │   savegame.cfg         │
└─────────────────────────────────────┘  │   │   [data]               │
                                         │   │   _save_version=1      │
                                         │   │   total_credits=0      │
                                         │   │   owned_upgrades=[]    │
                                         │   └────────────────────────┘
                                         │
   ┌─────────────────────────────────────┴────────────────────────┐
   │                                                              │
   ▼                                                              ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────────────────┐
│ Credit       │  │ Shop         │  │ Secret (T2+) │  │ Upgrade (provisional│
│ (autoload)   │  │ (scene-local)│  │ (autoload)   │  │  OQ-SAV-1, t.b.d.)  │
│              │  │              │  │              │  │                     │
│ MENU →       │  │ buy click →  │  │ MENU →       │  │ Hypothèse Save/Load │
│ save_int(    │  │ save_string_ │  │ save_int_    │  │ r1 : N/A — Upgrade  │
│  total_      │  │ array(owned_ │  │ array(       │  │ lit Shop owned_     │
│  credits)    │  │ upgrades)    │  │ collected_   │  │ upgrades indirect.  │
│              │  │              │  │ secret_ids)  │  │ À confirmer ADR-0012│
└──────────────┘  └──────────────┘  └──────────────┘  └─────────────────────┘
```

### Key Interfaces

```gdscript
# src/core/save_load_system.gd
# Autoload nom : SaveLoadSystem (position 3 sur 4 — ADR-0007 D-1)
# Pas de class_name (autoload sans class_name évite collision Godot 4.6 — cf. memory feedback_godot_class_name_autoload_collision)
extends Node

const SAVE_FILE_PATH: String = "user://savegame.cfg"
const _CURRENT_SAVE_VERSION: int = 1

# === MVP API verrouillée ===
func load_int(key: String, default: int) -> int
func save_int(key: String, value: int) -> void

func load_string_array(key: String, default: Array[StringName]) -> Array[StringName]
func save_string_array(key: String, value: Array[StringName]) -> void

# === Tier 2+ API réservée (verbes typés signatures figées) ===
func load_int_array(key: String, default: Array[int]) -> Array[int]
func save_int_array(key: String, value: Array[int]) -> void

# === Méta (read-only) ===
func get_save_version() -> int

# === Hooks Engine ===
func _ready() -> void  # set process_mode = PROCESS_MODE_ALWAYS, hydrate _config
func _notification(what: int) -> void  # WM_CLOSE_REQUEST → _flush_pending()
```

Référencement : tous les consumers utilisent `SaveLoadSystem.load_int(...)` directement (l'autoload nom = `SaveLoadSystem`, accessible en global GDScript). Le fichier `save_load_system.gd` n'a pas de `class_name` (pattern délibéré, R-SAV-1).

## Alternatives Considered

### Alternative 1 : JSON texte (`user://save_slot_0.json`)

- **Description** : sérialiser `_data: Dictionary` via `JSON.stringify` + écrire dans un fichier texte. Lecture via `JSON.parse_string`.
- **Pros** : human-readable (debug Sprint 1), schema versioning trivial via clé `_schema_version`, extensibilité forward-compatible naturelle.
- **Cons** :
  - **Verbosité** : ~3× la taille de ConfigFile pour le même payload (overhead `{`, `:`, `,`, espaces, quotes).
  - **Typage natif perdu** : `JSON.parse_string` retourne un `Array` brut pour un `Array[StringName]` ; cast élément par élément requis (godot-specialist Q4 2026-04-27). Code de validation typée plus lourd que ConfigFile (qui round-trip-erase StringName↔String mais nécessite seulement un cast simple R-SAV-12).
  - **Parsing manuel** : JSON est plus expressive que le besoin (Dict nested, types mixtes) — overhead pour 3 clés flat top-level MVP.
  - **Anti-cheat équivalent** : également éditable au notepad, gain anti-cheat naïf nul vs ConfigFile.
- **Rejection Reason** : le GDD save-load-system.md R-SAV-2 a explicitement rejeté JSON pour cause de verbosité et typage manuel. Cet ADR ratifie le rejet. Le bénéfice debuggabilité humaine est partiellement préservé par ConfigFile (format INI lisible, plus compact que JSON).

### Alternative 2 : Resource sérialisée (`.tres` schema-locked)

- **Description** : créer une classe `class_name SaveData extends Resource` avec `@export var total_credits: int` etc. Sauver via `ResourceSaver.save(save_data, "user://savegame.tres")`.
- **Pros** : type-safety stricte garantie par le moteur (round-trip Variant exact), toolable in-editor (Inspector pour inspecter un save), versioning via Resource sub-resources.
- **Cons** :
  - **Schema locked** : ajouter une clé Tier 2+ requiert d'amender la classe SaveData → break des saves existants si pas de migration explicite.
  - **Couplage compile-time** : SaveLoadSystem doit `preload("res://src/core/save_data.gd")`, perdant l'agnostique vis-à-vis des consumers.
  - **Ouverture du registry interne** : Resource serialization pose des risques si un export futur référence un Resource interne (ResourceFormatLoader recursion).
- **Rejection Reason** : casse la migration MVP→Tier2+ et introduit un couplage compile-time. Le GDD R-SAV-2 a explicitement rejeté pour ces raisons.

### Alternative 3 : Binary `FileAccess.store_var` / `get_var`

- **Description** : sérialisation binaire via FileAccess.store_var(_data) / get_var().
- **Pros** : compact, type-preserving Variant exact, géré nativement.
- **Cons** :
  - **Godot 4.4 breaking change** : `FileAccess.store_*` retourne `bool` (était `void`). Tout code error-handling doit gérer ces retours — multiplication des chemins.
  - **Opaque debug** : impossible de `cat user://savegame.dat` pour diagnostiquer une régression Sprint 1.
  - **Fragilité versioning** : Godot ne garantit pas la rétrocompatibilité binaire entre versions mineures pour `store_var`.
  - **Tests GUT plus durs** : impossible de hardcoder un fixture binaire lisible dans un test.
- **Rejection Reason** : Godot 4.4 breaking change augmente la surface d'erreur. Le GDD R-SAV-2 a explicitement rejeté pour cette raison. ConfigFile abstrait l'API stable.

### Alternative 4 : Multi-fichier (un fichier par système)

- **Description** : `user://credits.cfg`, `user://upgrades.cfg`, `user://secrets.cfg`.
- **Pros** : isolation par système, corruption d'un fichier n'affecte pas les autres.
- **Cons** : multiplie la surface I/O par 3+, pas de transaction cross-système Tier 2+, complexité orchestration accrue.
- **Rejection Reason** : surface attaque corruption identique (filesystem peut planter sur n'importe quel fichier), gain isolation marginal vs validation typée par-clé (R-SAV-12). Settings split file Tier 2+ (OQ-SAV-2) reste possible — c'est un cas d'isolation différent (settings vs gameplay save).

### Alternative 5 : SQLite via GDExtension

- **Description** : embarquer SQLite via GDExtension pour transactions ACID natives.
- **Pros** : robustesse industrielle, transactions multi-clés atomiques.
- **Cons** : dépendance GDExtension (binaire native par plateforme), surcoût build ~500 KB, complexité tests (mock SQLite ou TempDir par test), totalement disproportionné pour 3 clés flat MVP.
- **Rejection Reason** : over-engineering total. Ré-évaluable Tier 3+ si le projet introduit save cloud, multi-slot avec leaderboards, ou structures relationnelles.

## Consequences

### Positive

- **Décision GDD opposable cross-ADR** : tout futur ADR ou GDD qui voudrait re-litiger le format sera redirigé vers cet ADR. Stabilité du contrat sur Sprint 1+.
- **Registry entries** : `state_ownership.persistent_save_data`, `interfaces.save_load_persistence`, `api_decisions.save_load_serialization_format`, `forbidden_patterns.save_data_direct_access_outside_save_load`, `forbidden_patterns.save_load_thread_offload` — accessibles à `/architecture-review`, `/create-stories`, `/dev-story` via `docs/registry/architecture.yaml`.
- **Engine-compat tracé** : la justification du rejet binary FileAccess (Godot 4.4 breaking change) est captured dans Engine Compatibility — résiste aux propositions de "switch en binary pour la compacité" lors de futurs reviews.
- **Locked contracts traçables** : Credit r1 R-CRD-11/12 et Shop r1 R-SHP-3/8 ont maintenant un point d'ancrage architectural unique (cet ADR + l'entrée registry `save_load_persistence`). `/architecture-review` peut détecter une dérive de signature (ex: si un futur GDD propose `save_int(key: StringName, ...)` au lieu de `key: String`, le conflit est levé).
- **Forbidden patterns appliqués** : les conventions GDD R-SAV-10/11/17 (zero signal, zero orchestration, outbound-only) sont maintenant lintables via grep cross-projet, pas seulement documentées.
- **Cohérence avec patterns établis** : main-thread only (D-7) cohérent ADR-0004 + rules ; outbound-zero (D-5) cohérent ADR-0005 D-10 + ADR-0011 D-7 ; PROCESS_MODE_ALWAYS (D-4) cohérent ADR-0007 D-4.

### Negative

- **Atomicité non garantie MVP** : crash mid-write peut tronquer le fichier (EC-SAV-15). Risque accepté par le GDD ; cet ADR le ratifie. Si analytics post-launch révèle des saves corrompues > 1‰, ouvrir l'ADR successeur Tier 2+ via OQ-SAV-4.
- **Format ConfigFile éditable** : un joueur peut ouvrir `savegame.cfg` au notepad et modifier `total_credits = 999999`. Risque accepté Tier 1 (audience solo, anti-cheat naïf documenté).
- **Pas de migration tooling MVP** : si Tier 2 change le format d'une clé existante, une migration manuelle sera requise. Mitigation : `_save_version` permet de détecter ; coût de casser les saves de l'auteur acceptable au MVP.
- **save_* return void** : pas de feedback de succès au caller. `push_error` log la défaillance mais pas de récupération automatique. Mitigation : write-through synchrone est immédiat ; un échec se traduit par un état RAM cohérent (consumer continue) + erreur loguée — pas de désynchronisation. Conséquence acceptable per GDD R-SAV-5.
- **Pas de cap de taille de save** : si Tier 2+ accumule des arrays sans bornes, lecture/écriture devient O(N). Surveillance analytics requise post-MVP ; cap si > 100 KB observé (OQ-SAV-10).

### Risks

- **Risque 1 : un consumer oublie de déclencher save sur un event critique** (ex: shop oublie d'appeler `save_string_array` après achat → upgrade perdue au crash).
  - **Mitigation** : les GDDs (R-SHP-8, R-CRD-12) imposent l'appel ; les ACs (AC-CRD-25, AC-SHP-19) gateway le test. Aucune mitigation supplémentaire au niveau SaveLoad — la responsabilité reste côté consumer (cohérent outbound-zero D-5).

- **Risque 2 : ConfigFile.save() lent sur HDD spinning** (rare 2026 mais possible).
  - **Mitigation** : F-SAV-1 GDD documente `B ≈ 5–20 ms` sur HDD selon fragmentation. Reste hors hot path gameplay (transitions MENU, achat shop modal). OQ-SAV-3 deferred Tier 2+ pour async I/O si stats post-launch flag ce cas.

- **Risque 3 : autoload position drift** (ex: futur dev ajoute un autoload entre GSM et SaveLoadSystem).
  - **Mitigation** : ADR-0007 D-1 + cet ADR D-3 verrouillent l'ordre. Tout PR qui modifie `project.godot` autoload section doit citer un amendement explicite des deux ADRs. Lint CI possible (vérifier l'ordre dans `project.godot`) — à formaliser dans un futur amendement si les ajouts deviennent fréquents.

- **Risque 4 : confusion StringName vs String côté consumer**.
  - **Mitigation** : `load_string_array` normalise explicitement String → StringName au load (R-SAV-12). Le consumer reçoit toujours `Array[StringName]` typé strict. Tests AC-SAV-9/10/11 GDD couvrent.

- **Risque 5 : déférement Tier 2+ jamais réalisés** (atomic write, multi-profile, chiffrement restent OQ-SAV-* sans deadline).
  - **Mitigation** : acceptable car le scope MVP est délibérément minimal. Chaque OQ a une condition de réveil documentée (analytics post-launch, scope Tier 2+ planifié). Pas de blocker MVP.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `save-load-system.md` | R-SAV-1 « SaveLoadSystem est un autoload Node singleton, position 3 sur 4 (post-GSM, pre-Audio), pas de class_name » | D-3 verrouille la position autoload (cohérent ADR-0007 D-1). Key Interfaces documente l'absence de class_name (cohérent memory `feedback_godot_class_name_autoload_collision`). |
| `save-load-system.md` | R-SAV-2 « ConfigFile sur user://savegame.cfg, rejet JSON/Resource/binary FileAccess » | D-1 ratifie le format ConfigFile. Engine Compatibility documente la justification engine-compat du rejet binary (Godot 4.4 store_* breaking). Alternatives Considered formalise les rejets pour audit cross-ADR. |
| `save-load-system.md` | R-SAV-4 « 4 verbes MVP + 2 Tier 2+ + 1 getter, signatures String keys / void save returns » | D-2 verrouille les 7 signatures à l'identique. Key Interfaces les capture pour reference cross-ADR. |
| `save-load-system.md` | R-SAV-5 « write-through synchrone, pas de batch » | D-2 sémantique save_* + D-9 défère atomic write Tier 2+. F-SAV-1 budget validé. |
| `save-load-system.md` | R-SAV-6 + R-SAV-12 « load à la demande, default sur absent/corrompu, type validation » | D-2 sémantique load_* documentée — pattern partagé GDD R-SAV-12 (Array StringName cast élément par élément). |
| `save-load-system.md` | R-SAV-7 + R-SAV-15 « boot _ready() charge fichier une fois, init lazy _save_version » | D-3 ordre autoload garantit pre-consumer ; D-6 versioning. |
| `save-load-system.md` | R-SAV-8 « PROCESS_MODE_ALWAYS » | D-4 verrouille (cohérent ADR-0007 D-4). |
| `save-load-system.md` | R-SAV-9 « NOTIFICATION_WM_CLOSE_REQUEST handler » | D-8 verrouille. |
| `save-load-system.md` | R-SAV-10 « zero signal sortant » | D-5 verrouille + forbidden pattern registry empêche régression. |
| `save-load-system.md` | R-SAV-11 « zero orchestration, consumers décident quand » | D-5 verrouille. |
| `save-load-system.md` | R-SAV-13 « idempotence save_int(key, value) appelé deux fois identique » | Comportement émergent du write-through synchrone D-2 — pas de cache RAM intermédiaire à dirty-flag. |
| `save-load-system.md` | R-SAV-14 « _save_version réservé, framework migration Tier 2+ » | D-6 verrouille forward-only. |
| `save-load-system.md` | R-SAV-17 « outbound-only towards engine, inbound-only depuis consumers » | D-5 + forbidden pattern registry. |
| `credit-economy-system.md` | R-CRD-11 « Boot hydration : SaveLoad.load_int("total_credits", 0) au state_changed(PLAYING) » | D-2 expose `load_int(key: String, default: int) -> int` à signature exacte attendue. D-3 garantit ordre autoload. EC-CRD-8 default sur corrompu couvert par R-SAV-6/12. |
| `credit-economy-system.md` | R-CRD-12 « Persistance MENU : SaveLoad.save_int("total_credits", value) à state_changed(MENU) » | D-2 expose `save_int(key: String, value: int) -> void` à signature exacte. Sémantique void return cohérente. |
| `shop-system.md` | R-SHP-4 « _owned_upgrades = SaveLoad.load_string_array("owned_upgrades", []) dans _ready() » | D-2 expose `load_string_array(key: String, default: Array[StringName]) -> Array[StringName]` à signature exacte. R-SAV-12 normalisation String → StringName couvre EC-SHP-7. |
| `shop-system.md` | R-SHP-8 « SaveLoad.save_string_array("owned_upgrades", _owned_upgrades) synchrone post-achat AVANT apply_upgrade » | D-2 + write-through synchrone R-SAV-5 garantissent l'ordre. EC-SHP-9 « save échoue post-débit : RAM cohérente, push_error log » couvert par sémantique save_* void + push_error D-2. |
| `secret-system.md` | OQ-SEC-2 (Tier 2+) « SaveLoad.save_int_array("collected_secret_ids", arr) + load_int_array(key, default) provisoire » | D-2 expose `save_int_array` + `load_int_array` à signature exacte attendue (verbes Tier 2+ réservés R-SAV-4). Provisoire confirmé : Secret System pourra consommer cet ADR au moment du Tier 2+ sans changement de contrat. |

## Performance Implications

- **CPU** :
  - Boot `_ready()` : 1× `ConfigFile.load(SAVE_FILE_PATH)` = ~0.3 ms SSD M1 pour fichier sub-1 KB (F-SAV-1 GDD validé empiriquement). Acceptable boot budget.
  - `save_*` synchrone : 1× `ConfigFile.save(SAVE_FILE_PATH)` = ~0.3 ms SSD ; ~5-20 ms HDD. Hors hot path gameplay.
  - `load_*` post-boot : `_config.get_value` = O(1) hash lookup + cast = sub-microsecond pour scalars, O(N) pour Array (cast élément par élément, négligeable < 100 éléments).
- **Memory** :
  - `_config: ConfigFile` ~1-2 KB overhead Godot + payload réel. MVP = 3 clés × ~40 bytes ASCII = ~120 bytes RAM section.
  - `JSON.stringify` n'est pas utilisé (ConfigFile sérialise en interne en INI-like — pas d'allocation String temporaire visible côté GDScript).
  - Pas de fuite : ConfigFile mutate-in-place, pas d'allocation par save.
- **Load Time** : impact boot < 0.5 ms — non perceptible.
- **Network** : N/A (jeu solo, pas de cloud sync MVP).

## Migration Plan

Pas de migration de code existant — système entièrement nouveau, première implémentation au Sprint 1.

**Tier 2+ migration template** (forward-only) — à implémenter via ADR successeur résolvant OQ-SAV-5 :

```gdscript
func _ready() -> void:
    # ... R-SAV-7 standard hydrate ...
    var version: int = _config.get_value("data", "_save_version", 1)
    if version < _CURRENT_SAVE_VERSION:
        _run_migration(version, _CURRENT_SAVE_VERSION)
        _config.set_value("data", "_save_version", _CURRENT_SAVE_VERSION)
        _config.save(SAVE_FILE_PATH)  # persiste la migration immédiatement

func _run_migration(from_version: int, to_version: int) -> void:
    # Implémenté par ADR successeur Tier 2+ (résout OQ-SAV-5)
    pass
```

Tout futur ADR qui modifie le schéma au-delà de l'ajout de clés DOIT (a) bumper `_CURRENT_SAVE_VERSION`, (b) implémenter `_run_migration`, (c) ajouter un test GUT avec fixture old-version.

## Validation Criteria

L'ADR est validé par les 33 ACs du GDD save-load-system.md §Acceptance Criteria. Les ACs prioritaires couvrant cet ADR :

- **VC-1 (BLOCKING — délégué AC-SAV-1)** : `_ready()` sur fichier inexistant → no crash, tous load_* retournent default.
- **VC-2 (BLOCKING — délégué AC-SAV-3)** : `_ready()` sur fichier corrompu (bytes random) → no crash, push_error émis, tous load_* retournent default.
- **VC-3 (BLOCKING — délégué AC-SAV-9/10/11)** : round-trip `Array[StringName]` typé strict via load_string_array (cast String → StringName).
- **VC-4 (BLOCKING — délégué AC-SAV-18)** : save_int sur permission revoquée → push_error émis avec err code, return normal void, no crash.
- **VC-5 (BLOCKING — délégué AC-SAV-21)** : NOTIFICATION_WM_CLOSE_REQUEST → handler exécuté, pas d'exception, état file inchangé.
- **VC-6 (BLOCKING — lint cross-ADR)** : grep `Thread\s*\.|WorkerThreadPool\s*\.` dans `src/core/save_load_system.gd` retourne 0 match.
- **VC-7 (BLOCKING — lint cross-ADR)** : grep `SaveLoadSystem\._config\b` dans tout `src/**/*.gd` autre que `src/core/save_load_system.gd` retourne 0 match (privé, jamais exposé — forbidden pattern registry).
- **VC-8 (BLOCKING — lint cross-ADR)** : grep d'identifiants consumer (Credit, Shop, Secret, Upgrade, HUD, AudioSystem, InputManager) dans `src/core/save_load_system.gd` retourne 0 match (outbound-only D-5).
- **VC-9 (BLOCKING — délégué AC-SAV-32)** : grep `signal\s+\w+` dans `src/core/save_load_system.gd` retourne 0 match (zero outbound signals D-5 / R-SAV-10).
- **VC-10 (BLOCKING — délégué AC-SAV-33)** : grep `\.connect\s*\(` dans `src/core/save_load_system.gd` retourne 0 match (zero orchestration D-5 / R-SAV-11).
- **VC-11 (BLOCKING — chain-blocked OQ-SAV-1 — délégué AC-SAV-32)** : amendement de cet ADR si Upgrade GDD r1 confirme un verbe additionnel SaveLoad requis.
- **VC-12 (ADVISORY — délégué AC-SAV-2)** : F-SAV-1 budget I/O respecté en CI sur SSD reference (`ConfigFile.save()` < 1 ms pour fichier ~80 bytes).

## Related Decisions

- **ADR-0007** Game State Manager — D-1 fixe ordre autoload `InputManager → GSM → SaveLoadSystem → AudioSystem` (D-3 référencé) ; D-4 process_mode discipline (D-4 ratifié).
- **ADR-0004** Input API & Focus Handling — D-7 main-thread only pattern (D-7 généralisé ici à l'I/O système).
- **ADR-0005** Movement Signals Architecture — D-10 outbound-only pattern (D-5 réplique).
- **ADR-0011** Level Scene Architecture — D-7 outbound-only pattern (D-5 réplique).
- **design/gdd/save-load-system.md** r1 — **autorité design**. Cet ADR ratifie sans modification.
- **design/gdd/credit-economy-system.md** r1 — consumer R-CRD-11/12, OQ-CRD-2 RESOLVED par save-load-system.md r1.
- **design/gdd/shop-system.md** r1 — consumer R-SHP-3/8, OQ-SHP-3 RESOLVED par save-load-system.md r1.
- **design/gdd/secret-system.md** r1 — consumer Tier 2+ OQ-SEC-2 (verbes int_array réservés).
- **`.claude/rules/input-singleton-main-thread-only.md`** — référence pattern thread-safety (D-7 généralisation).
- **memory `feedback_godot_class_name_autoload_collision`** — référence pattern autoload sans class_name (Key Interfaces).

---

**Validation post-rédaction (2026-04-27)** :
- godot-specialist : PASS with concerns sur draft JSON antérieur (corrections godot-specialist Q1-Q6) — pivot vers ConfigFile per GDD R-SAV-2 absorbe la majorité des concerns (l'API ConfigFile.save / load est stable cross-version, pas affectée par Godot 4.4 store_* breaking ; godot-specialist Q4 cast Array[StringName] reste pertinent et est couvert par R-SAV-12 normalisation).
- TD-ADR : skipped (Solo mode `production/review-mode.txt` = `solo`).
- GDD sync check : 4 GDDs (Credit r1, Shop r1, Secret r1, Save/Load r1) référencent l'API à signatures exactes — zéro renommage requis. Cet ADR ratifie sans amendement.
- Conflict check : pivot opéré 2026-04-27 après détection que `save-load-system.md` r1 existait déjà avec choix ConfigFile explicite. ADR draft initial JSON aurait contredit le GDD ; corrigé via réécriture totale en mode ratification.
