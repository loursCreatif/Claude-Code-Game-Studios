# Epic: Save/Load System

> **Layer**: Foundation / Persistence
> **GDD**: [save-load-system.md](../../../design/gdd/save-load-system.md) (Designed r1, 2026-04-27)
> **Architecture Module**: `SaveLoadSystem` autoload Node — position **#3 sur 4** (`InputManager → GameStateManager → SaveLoadSystem → AudioSystem`) — `src/core/save_load_system.gd`
> **Status**: Ready
> **Stories**: 8 stories created 2026-04-28 via `/create-stories save-load-system` (solo auto-approve, mode review-mode.txt = solo, QL-STORY-READY skipped).
> **Solo gates** : PR-EPIC skipped (`production/review-mode.txt` = `solo`).
> **Manifest Version** : 2026-04-23

## Overview

Le Save/Load System est la couche de persistance disque MVP du projet. Il expose une **API verbe pur typée** (4 verbes MVP + 2 Tier 2+ + 1 getter méta) au-dessus de `ConfigFile` Godot natif (`user://savegame.cfg`, section unique `[data]`, flat keys), avec write-through synchrone, type-safe load via Variant validation, et un handler `NOTIFICATION_WM_CLOSE_REQUEST`. Il ne consomme aucun signal des autres systèmes (zero orchestration, R-SAV-11) et n'émet aucun signal sortant (R-SAV-10) — les consumers (Credit Economy R-CRD-11/12, Shop System R-SHP-3/8, Upgrade System R-UPG-5 boot hydration, Secret System Tier 2+) décident *quand* appeler `save_*` / `load_*`. Le système est outbound-zero (R-SAV-17), main-thread only (D-7), et `PROCESS_MODE_ALWAYS` (D-4) — il continue de fonctionner sous pause et au quit. Pillar 1 préservé : `ConfigFile.save() ≈ 0.3 ms` SSD M1 (marge ×55 sur frame 16.6 ms @ 60fps, F-SAV-1).

**Pourquoi maintenant** : ADR-0010 Accepted 2026-04-27 + GDD r1 Designed 2026-04-27. **Débloque** Sprint 1 de 4 epics consumers : Credit Economy (R-CRD-11/12 boot hydrate + quit save), Shop System (R-SHP-3/8 owned_upgrades load/persist), Upgrade System (R-UPG-5 boot hydration via `load_string_array`), Menu System (R-MNU AC-MNU-57 délégation save-on-quit AC-MNU). **Sans cette epic, le Sprint 1 upgrade-system story-001 AC-UPG-3 BLOCKING strict** (`index("SaveLoadSystem") < index("UpgradeSystem")`) **ne peut pas passer**.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| **ADR-0010** Save/Load Persistence Architecture (ConfigFile Ratification) — **Accepted 2026-04-27** | D-1 Format ConfigFile sur `user://savegame.cfg` (rejet JSON/Resource/binary) + D-2 7 verbes typés API verrouillée + D-3 position autoload #3 figée + D-4 `PROCESS_MODE_ALWAYS` + D-5 outbound-zero (zero signal, zero orchestration) + D-6 `_save_version` forward-only + D-7 main-thread only assertion debug + D-8 `NOTIFICATION_WM_CLOSE_REQUEST` handler + D-9 atomic write `tmp+rename` déférée Tier 2+ via OQ-SAV-4 | **MEDIUM** — Godot 4.4 breaking change `FileAccess.store_*` retourne `bool` (pas `void`) ; ADR-0010 mitige via abstraction `ConfigFile` API stable Godot 3.x+ |
| **ADR-0007** GameStateManager + Scene Transition — Accepted 2026-04-23 (héritée) | D-1 ordre canonique autoload `InputManager → GSM → SaveLoadSystem → AudioSystem` figée + D-4 discipline `process_mode` autoloads Foundation en `PROCESS_MODE_ALWAYS = 3` (Godot 4.6 enum erratum 2026-04-28 commit `1649049` — `4` = `DISABLED`, jamais `ALWAYS`) | LOW (héritée) |

**Engine Risk Epic** : **MEDIUM** (max ADR-0010 ; ADR-0007 LOW absorbée).

## GDD Requirements

| R-SAV-ID | Requirement (résumé) | Coverage ADR |
|---|---|---|
| R-SAV-1 | SaveLoadSystem autoload Node singleton, position #3, pas de class_name | ADR-0010 D-3 + Key Interfaces ✅ |
| R-SAV-2 | Storage backend ConfigFile sur `user://savegame.cfg` (rejet JSON/Resource/binary) | ADR-0010 D-1 + Engine Compatibility ✅ |
| R-SAV-3 | Single section `[data]`, flat key namespace MVP (3 clés : `total_credits`, `owned_upgrades`, `_save_version`) | ADR-0010 D-1 ✅ |
| R-SAV-4 | API publique : 4 verbes MVP (`load_int`, `save_int`, `load_string_array`, `save_string_array`) + 2 Tier 2+ (`load_int_array`, `save_int_array`) + 1 getter (`get_save_version`) | ADR-0010 D-2 + Key Interfaces ✅ |
| R-SAV-5 | Write-through synchrone, pas de batch, pas de queue dirty | ADR-0010 D-2 sémantique save_* + D-9 atomic déférée ✅ |
| R-SAV-6 | Load à la demande, retour `default` sur absent / corrompu / type mismatch + push_warning | ADR-0010 D-2 sémantique load_* ✅ |
| R-SAV-7 | Boot lifecycle : `_ready()` charge fichier une fois, traite ERR_FILE_NOT_FOUND comme nominal | ADR-0010 D-3 ordre + Key Interfaces ✅ |
| R-SAV-8 | `process_mode = PROCESS_MODE_ALWAYS` (= 3 Godot 4.6) | ADR-0010 D-4 ✅ |
| R-SAV-9 | `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` handler + `_flush_pending()` no-op MVP | ADR-0010 D-8 ✅ |
| R-SAV-10 | Zero signal sortant MVP | ADR-0010 D-5 + VC-9 lint ✅ |
| R-SAV-11 | Zero orchestration de gameplay (consumers décident quand) | ADR-0010 D-5 + VC-10 lint ✅ |
| R-SAV-12 | Type-safe load via Variant validation (load_string_array normalise String → StringName) | ADR-0010 D-2 sémantique load_* ✅ |
| R-SAV-13 | Idempotence `save_int(key, value)` ×2 identique = no-op effectif | ADR-0010 D-2 (émergent du write-through) ✅ |
| R-SAV-14 | `_save_version` clé réservée + `_CURRENT_SAVE_VERSION = 1` + framework migration Tier 2+ forward-only | ADR-0010 D-6 ✅ |
| R-SAV-15 | Initialisation lazy `_save_version` (premier save_* écrit également la version) | ADR-0010 D-6 ✅ |
| R-SAV-16 | États internes UNINITIALIZED / READY_VOLATILE / READY_FRESH / READY_PERSISTED non exposés | ADR-0010 D-2 (états émergents) ✅ |
| R-SAV-17 | Outbound-only towards engine, inbound-only depuis consumers | ADR-0010 D-5 + VC-7/8 lint ✅ |

**Coverage** : **17/17 ✅** R-SAV-1..17 GDD r1 entièrement couverts par ADR-0010 (cf. ADR-0010 §"GDD Requirements Addressed" mapping exhaustif).

**TR Registry status** : ⚠ **0 entrée TR-sav-*** dans `docs/architecture/tr-registry.yaml`. Le registry n'a pas été repopulé post-ADR-0010. **Non-blocker** : ADR-0010 cite R-SAV-* GDD comme source de vérité opposable, et les stories ce skill produira référenceront R-SAV-* directement (analogue Shop+Upgrade+Menu epics où `R-SHP-*` / `R-UPG-*` / `R-MNU-*` servent de stable IDs jusqu'à `/architecture-review` post-Sprint 1 rotation). **Action follow-up** : prochain `/architecture-review` Phase 8 doit appender TR-sav-001..017.

## Acceptance Criteria — 33 ACs (AC-SAV-1..33)

Source autoritative : `design/gdd/save-load-system.md` §Acceptance Criteria (lignes 423-518). Distribution prévisionnelle :

- **5 BLOCKING priorité Sprint 1** : AC-SAV-1 (boot fresh) + AC-SAV-3 (boot corrompu graceful) + AC-SAV-9/10/11 (round-trip Array[StringName]) + AC-SAV-18 (permission revoquée graceful) + AC-SAV-21 (`NOTIFICATION_WM_CLOSE_REQUEST` handler).
- **6 BLOCKING lints cross-ADR** : VC-6 thread (grep `Thread\.|WorkerThreadPool\.` zéro match), VC-7 `_config` privé (grep `SaveLoadSystem._config` hors `save_load_system.gd` zéro match), VC-8 consumer refs (grep Credit/Shop/Secret/Upgrade/HUD/Audio/Input dans `save_load_system.gd` zéro match), VC-9 outbound signals (grep `signal\s+\w+` zéro match), VC-10 orchestration (grep `\.connect\s*\(` zéro match), VC-11 chain-blocked OQ-SAV-1 amendement Upgrade.
- **22 ACs gameplay/semantics restants** : couvrent edge cases boot/file lifecycle (EC-SAV-1..5), API verbes (load_int / save_int / load_string_array / save_string_array sémantique normale + corrompu + type mismatch), `_save_version` lifecycle, idempotence, Tier 2+ verbs réservés signatures.
- **1 ADVISORY** : VC-12 / AC-SAV-2 perf gate F-SAV-1 (`ConfigFile.save() < 1 ms` SSD reference CI).

## Open Questions

10 OQ-SAV (OQ-SAV-1..10) — cf. GDD r1 §Open Questions.

- **8 RESOLVED** par GDD r1 lui-même + ADR-0010 (atomic write OQ-SAV-4 déférée Tier 2+ ; multi-profile OQ-SAV-6 déférée ; chiffrement OQ-SAV-7 déférée ; async batch OQ-SAV-3 déférée ; migration framework OQ-SAV-5 déférée ; settings split OQ-SAV-2 déférée ; cap save bloat OQ-SAV-10 monitoring post-MVP ; settings file séparé OQ-SAV-2).
- **2 PROVISIONAL** :
  - **OQ-SAV-1** Upgrade consommation contrats : Save/Load r1 hypothèse "Upgrade lit Shop owned_upgrades indirect, pas d'appel SaveLoad direct" — à confirmer par ADR-0012 Upgrade Application Strategy futur. Stories save-load Sprint 1 verbes int_array réservés (`load_int_array` / `save_int_array`) signatures figées per R-SAV-4 — provision suffisante.
  - **OQ-SAV-2** Settings split file recommandé `user://settings.cfg` Tier 2+ pour Input remap / Audio volume — déférée Tier 2+ Settings GDD.

## Performance Budget

**F-SAV-1** (GDD § lignes 232-253) : `budget_save_ms = ConfigFile.save() wall-clock time at file_size_kb`.

| Variable | Symbol | Type | Range MVP | Description |
|---|---|---|---|---|
| `file_size_kb` | `S` | int | [0.1, 1.0] | Taille fichier (~0.1 KB pour 2 keys + version MVP) |
| `budget_save_ms` | `B` | float | [0.1, 1.0] | Wall-clock I/O sur SSD moderne |

**Output range MVP empirique** : `B ≈ 0.3 ms` à `S = 0.1 KB` (Godot 4.6 SSD M1). À 60 fps frame budget = 16.6 ms → **marge ×55**. Pillar 1 préservé sans amendement.

**CI gate** : AC-SAV-2 / VC-12 ADVISORY — `ConfigFile.save() < 1 ms` SSD reference (laptop CI), avec graceful degradation si HDD detected.

## Anti-deps (cross-system)

Cohérent ADR-0010 D-5 (outbound-zero) + R-SAV-10/11/17. **Aucune référence des identifiants suivants** dans `src/core/save_load_system.gd` :

- **Consumers gameplay** : `Credit`, `CreditEconomy`, `Shop`, `ShopSystem`, `Secret`, `SecretSystem`, `Upgrade`, `UpgradeSystem`, `HUDController`, `AudioSystem`, `InputManager`.
- **Tree paths** : `get_node("/root/<consumer>")`, `$<consumer>`, `preload("res://src/gameplay/<consumer>/...")`.
- **Signal connections** : `<signal>.connect(...)`, `<consumer>.<signal>.connect(...)`.

Lint statique BLOCKING (story-007) `tests/static/save_load_lint_test.gd` : grep cross-fichier 0 match (cohérent pattern Movement / Level / Combat lint cross-projet).

## Definition of Done

L'epic est complète quand :

- **All stories implémentées** : 7-9 stories save-load-system status `Complete` via `/story-done` (cf. cluster décomposition prévisionnelle).
- **All ACs verified** : 33 ACs GDD (AC-SAV-1..33) plus 6 VC ADR-0010 (VC-1..VC-12) cochées.
- **Tests Logic / Integration passants** :
  - `tests/integration/save_load/autoload_skeleton_test.gd` (R-SAV-1/7/8, EC-SAV-1/2/3) — story-001
  - `tests/unit/save_load/scalar_verbs_test.gd` (R-SAV-4 MVP scalar, R-SAV-6, R-SAV-12) — story-002
  - `tests/unit/save_load/array_verbs_test.gd` (R-SAV-4 MVP arrays, R-SAV-12 String→StringName) — story-003
  - `tests/unit/save_load/save_version_test.gd` (R-SAV-14/15) — story-004
  - `tests/integration/save_load/wm_close_request_test.gd` (R-SAV-9) — story-005
  - `tests/unit/save_load/tier2_verbs_signature_test.gd` (R-SAV-4 Tier 2+ stubs) — story-006
  - `tests/static/save_load_lint_test.gd` (VC-6/7/8/9/10) — story-007
  - `tests/performance/save_load_budget_test.gd` (VC-12 / AC-SAV-2 ADVISORY) — story-008 (optionnel)
- **Lints CI** : `lint-save-load-thread` + `lint-save-load-private-config` + `lint-save-load-consumer-refs` + `lint-save-load-outbound-signals` + `lint-save-load-orchestration` (5 grep gates).
- **Erratum process_mode propagé** : tout AC asserting `process_mode == PROCESS_MODE_ALWAYS` utilise **double-assert** (constante symbolique + valeur entière `3`) — pattern documenté upgrade-001 AC-UPG-4 ligne 102.
- **Sprint 1 unblock vérifié** : 4 consumers epics Sprint 1 (Credit, Shop, Upgrade, Menu) ne sont plus blockés par `SaveLoadSystem absent project.godot` — story-001 save-load fournit l'autoload registered.

## Story Decomposition Prévisionnelle (~7-9 stories)

| # | Cluster | Titre prévisionnel | Type | R-SAV / VC couverts | Débloque |
|---|---|---|---|---|---|
| 001 | C1 Architecture/Boot | Autoload skeleton + project.godot registration + `process_mode = ALWAYS` (= 3) + ConfigFile init `_ready()` | Integration | R-SAV-1, R-SAV-7, R-SAV-8 + AC-SAV-1 (boot fresh) + ADR-0007 D-1 ordre canonique partial (#3) | **upgrade-001 AC-UPG-3 BLOCKING** ✅ |
| 002 | C2 Scalar Verbs | `load_int` / `save_int` typed + R-SAV-12 type validation + EC-SAV-1/2/3 boot edge cases | Logic | R-SAV-4 MVP scalar, R-SAV-6, R-SAV-12 + AC-SAV-3/4/18/19 | Credit story-* boot hydrate `total_credits` |
| 003 | C2 Array Verbs | `load_string_array` / `save_string_array` typed + R-SAV-12 String→StringName cast | Logic | R-SAV-4 MVP arrays, R-SAV-12 normalization + AC-SAV-9/10/11 | Shop story-001 + Upgrade story-005 boot hydrate `owned_upgrades` |
| 004 | C3 Version Lifecycle | `_save_version` init lazy + `_CURRENT_SAVE_VERSION = 1` + R-SAV-15 first-write trigger | Logic | R-SAV-14, R-SAV-15 + AC-SAV-7/8 | Forward-compat Tier 2+ migration |
| 005 | C4 WM_CLOSE Handler | `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` handler + `_flush_pending()` no-op MVP | Integration | R-SAV-9 + AC-SAV-21 + D-8 | Menu story-007 délégation save-on-quit AC-MNU-57 |
| 006 | C5 Tier 2+ Stubs | `load_int_array` / `save_int_array` + `get_save_version()` getter — signatures figées stubs | Logic | R-SAV-4 Tier 2+ verbes + méta + AC-SAV-12/13/14 | Secret System Tier 2+ provision |
| 007 | C6 Lints Static | `tests/static/save_load_lint_test.gd` — 5 grep gates BLOCKING | Config/Data | VC-6/7/8/9/10 + AC-SAV-32/33 + R-SAV-10/11/17 | CI fail-fast régression couplage |
| 008 | C7 Perf Gate | `tests/performance/save_load_budget_test.gd` — `ConfigFile.save() < 1 ms` SSD reference | Logic ADVISORY | VC-12 / AC-SAV-2 + F-SAV-1 | Pillar 1 régression CI |

**Ordre pickup recommandé** :
1. **story-001** (urgent — débloque upgrade Sprint 1 + Shop + Credit + Menu) ← première story livrée
2. **story-002** (Credit boot hydrate)
3. **story-003** (Shop boot hydrate + Upgrade boot hydrate)
4. **story-004** (`_save_version` forward-compat avant que Credit/Shop écrivent leur premier save)
5. **story-005** (WM_CLOSE handler avant Menu story-007 quit-flow)
6. **story-006** (Tier 2+ stubs — peut être en parallèle avec story-005)
7. **story-007** (lints CI activated post-implémentation 001-006)
8. **story-008** (perf gate optionnel — cosmetic CI ADVISORY)

## Engine Notes (Godot 4.6)

- **`ConfigFile`** : API stable depuis Godot 3.x. `set_value(section, key, value)` / `get_value(section, key, default)` / `save(path) -> Error` / `load(path) -> Error`. Non-affectée par les breaking changes 4.4-4.6.
- **`FileAccess.store_*`** : Godot 4.4 a changé `void` → `bool`. **Évité** via abstraction ConfigFile (D-1 rejet binary justifié engine-compat ADR-0010).
- **`PROCESS_MODE_ALWAYS`** : enum `Node.ProcessMode` valeur entière **`3`** Godot 4.6 (erratum 2026-04-28 commit `1649049`). `4` = `PROCESS_MODE_DISABLED`. Tout AC assertant `process_mode == ALWAYS` doit utiliser double-assert (symbolique + entier).
- **`NOTIFICATION_WM_CLOSE_REQUEST`** : constante stable Godot 4.x. Reçue avant `SceneTree` close lors de alt-F4 / window close / OS signal. Garanti livré dans la frame de quit.
- **Thread safety** : `ConfigFile` et `FileAccess` **non documentés thread-safe**. ADR-0010 D-7 impose `OS.get_thread_caller_id() == OS.get_main_thread_id()` assertion debug build sur tous verbes publics. Cohérent ADR-0004 D-7 + `.claude/rules/input-singleton-main-thread-only.md`.
- **`user://`** : path résolu par Godot vers location système locale (`%APPDATA%/Godot/app_userdata/<projectName>/` Win, `~/.local/share/godot/app_userdata/<projectName>/` Linux, `~/Library/Application Support/Godot/...` macOS). Dossier garanti existant avant `_ready()` (Godot bootstrap).

## Control Manifest Rules (Foundation Layer)

Source : `docs/architecture/control-manifest.md` Manifest Version 2026-04-23 §Foundation Layer Rules.

**Required (Foundation Persistence)** :
- Autoload registré `project.godot` après `GameStateManager`, avant `AudioSystem` (ADR-0007 D-1 + ADR-0010 D-3).
- `process_mode = PROCESS_MODE_ALWAYS` (= 3) déclaré programmatiquement dans `_ready()` (ADR-0010 D-4 + ADR-0007 D-4).
- Pas de `class_name` pour SaveLoadSystem (memory `feedback_godot_class_name_autoload_collision` — autoload nom global réutilisable, fichier sans class_name).

**Forbidden (Foundation Persistence)** :
- Aucune référence vers consumer gameplay (Credit / Shop / Secret / Upgrade / HUD / Audio / Input) dans `src/core/save_load_system.gd` (ADR-0010 D-5 / R-SAV-17).
- Aucun `Thread.start` / `WorkerThreadPool.add_task` / `call_deferred` cross-thread vers verbes SaveLoad (ADR-0010 D-7).
- Aucun accès direct à `_config: ConfigFile` privé hors `src/core/save_load_system.gd` (ADR-0010 REQ-5 forbidden pattern registry).
- Aucun `signal` déclaration dans `src/core/save_load_system.gd` (R-SAV-10 zero outbound MVP).
- Aucun `.connect(` dans `src/core/save_load_system.gd` (R-SAV-11 zero orchestration).

**Guardrails (Foundation Persistence)** :
- `ConfigFile.save() < 1 ms` SSD reference (F-SAV-1 / AC-SAV-2 ADVISORY). Si HDD détecté, graceful degradation accepté.
- `_ready()` SaveLoadSystem < 5 ms headless CI (boot budget — boot fresh OK, boot corrompu OK avec push_error).

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | autoload-skeleton-configfile-init | Integration | Ready | ADR-0010 + ADR-0007 |
| 002 | scalar-verbs-load-save-int | Logic | Ready | ADR-0010 |
| 003 | array-verbs-load-save-string-array | Logic | Ready | ADR-0010 |
| 004 | save-version-lifecycle-forward-only | Logic | Ready | ADR-0010 |
| 005 | wm-close-request-handler | Integration | Ready | ADR-0010 |
| 006 | tier2-verbs-stubs-int-array-and-meta | Logic | Ready | ADR-0010 |
| 007 | lints-static-cross-system-isolation | Config/Data | Ready | ADR-0010 |
| 008 | perf-gate-configfile-save-budget | Logic ADVISORY | Ready | ADR-0010 |

**Ordre pickup recommandé** :

1. **story-001** (urgent — débloque upgrade Sprint 1 + Shop + Credit + Menu) ← première story livrée
2. **story-002** (Credit boot hydrate)
3. **story-003** (Shop boot hydrate + Upgrade boot hydrate)
4. **story-004** (`_save_version` forward-compat avant que Credit/Shop écrivent leur premier save)
5. **story-005** (WM_CLOSE handler avant Menu story-007 quit-flow)
6. **story-006** (Tier 2+ stubs — peut être en parallèle avec story-005)
7. **story-007** (lints CI activated post-implémentation 001-006)
8. **story-008** (perf gate ADVISORY — différable Sprint 1+ sans bloquer Sprint A)

**Story-001 est la priorité absolue Sprint 1** : unique story du projet qui débloque 4 epics consumers simultanément (upgrade-001 AC-UPG-3 + Credit boot hydrate + Shop boot hydrate + Menu save-on-quit).

## Next Step

Run **`/story-readiness production/epics/save-load-system/story-001-autoload-skeleton-configfile-init.md`** to validate story-001 implementation-readiness, puis **`/dev-story`** pour implémenter.
