# Story 007: Lints static cross-system isolation (5 grep gates BLOCKING)

> **Epic**: Save/Load System
> **Status**: Ready
> **Layer**: Foundation / Persistence
> **Type**: Config/Data
> **Manifest Version**: 2026-04-23
> **Estimate**: ~1-2h — t-shirt XS
> **Risk**: LOW

## Context

**GDD**: `design/gdd/save-load-system.md` r1
**Requirement**: R-SAV-10 (zero outbound signals MVP), R-SAV-11 (zero orchestration de gameplay), R-SAV-17 (outbound-only towards engine, inbound-only depuis consumers)

**ADR Governing Implementation**: ADR-0010 — Accepted 2026-04-27
**ADR Decision Summary**: D-5 outbound-zero (zéro signal, zéro orchestration) + D-7 main-thread only assertion debug. Story-007 livre les 5 lints CI BLOCKING (grep gates) qui empêchent toute régression couplage cross-system par dérive accidentelle. Pattern aligné avec lints existants Movement / Level / Combat (analogie cross-projet).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**:
- Lints implémentés via GDScript GUT runner exécutant `OS.execute("bash", ["-c", grep_command])` ou `Bash.exec`. Cohérent pattern `tests/static/menu_main_menu_lint_test.gd` story-001 menu-system.
- Tests static utilisent `OS.execute("bash", ...)` — ne fonctionne pas en CI Windows pur ; OK macOS/Linux dev. Cohérent stack technique projet (CLAUDE.md technical-preferences.md PC desktop primary).
- `grep -rl` retourne fichiers matching ; `grep -rE` retourne lignes matching. Convention exit code 0 = match found, exit 1 = zero match.

**Control Manifest Rules (Foundation Persistence)**:
- **Required**: 5 grep gates BLOCKING dans `tests/static/save_load_lint_test.gd` (analogue `tests/static/movement_lint_test.gd`).
- **Forbidden**: jamais skip / ignore / disable un lint qui FAIL — fix le code source, pas le test (CLAUDE.md "Never disable or skip failing tests to make CI pass").
- **Guardrail**: lint exécution < 100 ms total (5 grep cross-fichiers, project taille MVP).

---

## Acceptance Criteria

*From GDD `design/gdd/save-load-system.md`, scoped to this story:*

- [ ] **AC-SAV-28** [Logic] [ADVISORY] : GIVEN SaveLoadSystem au runtime, WHEN tree node hierarchy inspection, THEN aucun child Control / Label / Sprite / AudioStreamPlayer présent. Mécanisme : unit GUT scene tree introspection (BLOCKING-promoted dans story-007 — partie de la stricte Foundation Persistence isolation).
- [ ] **AC-SAV-29** [Logic] [ADVISORY] : GIVEN inspection statique du fichier `save_load_system.gd`, WHEN grep `signal\s+`, THEN zero match (R-SAV-10 zero outbound signals MVP). Mécanisme : static check via Bash. **Promu BLOCKING dans CI lint**.
- [ ] **AC-SAV-30** [Logic] [ADVISORY] : GIVEN inspection statique, WHEN grep `\.connect\s*\(`, THEN zero match dans `save_load_system.gd` (R-SAV-11 no orchestration). Mécanisme : static check. **Promu BLOCKING dans CI lint**.
- [ ] **AC-SAV-31** [Logic] [ADVISORY] : GIVEN inspection, WHEN grep import / preload de `Credit\|Shop\|Secret\|Upgrade\|HUD\|Combat\|Movement\|Camera\|VFX\|Audio` dans `save_load_system.gd`, THEN zero match (R-SAV-17 zero coupling cross-system). Mécanisme : static check Bash. **Promu BLOCKING dans CI lint**.

**5 lints BLOCKING déclarés EPIC §Definition of Done — implémentés ici** :

- [ ] **VC-6 (lint-save-load-thread)** : grep `\bThread\.|\bWorkerThreadPool\.|\.call_deferred\s*\(.*save_int\|\.call_deferred\s*\(.*save_string_array\|\.call_deferred\s*\(.*save_int_array` dans `src/core/save_load_system.gd` zéro match (ADR-0010 D-7 main-thread-only).
- [ ] **VC-7 (lint-save-load-private-config)** : grep `SaveLoadSystem\._config|SaveLoad\._config` dans tous fichiers `src/**/*.gd` SAUF `src/core/save_load_system.gd` lui-même → zéro match (ADR-0010 REQ-5 forbidden pattern, R-SAV-1 cache privé).
- [ ] **VC-8 (lint-save-load-consumer-refs)** : grep `\b(CreditEconomy|Shop|ShopSystem|Secret|SecretSystem|Upgrade|UpgradeSystem|HUDController|HUDSystem|AudioSystem|InputManager|CameraSystem|CombatSystem|MovementController|VFXManager)\b` dans `src/core/save_load_system.gd` → zéro match (R-SAV-17 + ADR-0010 D-5 outbound-zero).
- [ ] **VC-9 (lint-save-load-outbound-signals)** : grep `^\s*signal\s+\w+` dans `src/core/save_load_system.gd` → zéro match (R-SAV-10).
- [ ] **VC-10 (lint-save-load-orchestration)** : grep `\.connect\s*\(` dans `src/core/save_load_system.gd` → zéro match (R-SAV-11).

---

## Implementation Notes

*Derived from ADR-0010 D-5 / D-7 + lints cross-projet existants (movement_lint_test.gd, level_signals_lint_test.gd):*

1. **Créer `tests/static/save_load_lint_test.gd`** :
   ```gdscript
   extends GutTest

   const SAVE_LOAD_PATH := "res://src/core/save_load_system.gd"

   func _run_grep(pattern: String, files: Array[String]) -> int:
       var args := ["-c", "grep -rE '%s' %s | grep -v '^[^:]*:[[:space:]]*#' | wc -l" % [pattern, " ".join(files)]]
       var output := []
       var exit := OS.execute("bash", args, output, true)
       if exit != 0:
           return -1  # erreur exécution grep
       var count_str: String = output[0].strip_edges() if output.size() > 0 else "0"
       return int(count_str)

   func test_vc6_no_thread_or_worker_pool_in_save_load() -> void:
       var count := _run_grep('\\bThread\\.|\\bWorkerThreadPool\\.', [SAVE_LOAD_PATH])
       assert_eq(count, 0, "VC-6 (ADR-0010 D-7) : %s contient %d référence Thread/WorkerThreadPool" % [SAVE_LOAD_PATH, count])

   func test_vc7_no_private_config_access_outside_save_load() -> void:
       # Cherche toute référence à _config ConfigFile depuis l'extérieur
       var args := ["-c",
           "grep -rE 'SaveLoad(System)?\\._config|SaveLoad(System)?\\.get_config' src/ | grep -v '^src/core/save_load_system.gd:' | grep -v '^[^:]*:[[:space:]]*#' | wc -l"]
       var output := []
       OS.execute("bash", args, output, true)
       var count := int(output[0].strip_edges()) if output.size() > 0 else 0
       assert_eq(count, 0, "VC-7 (ADR-0010 REQ-5) : %d accès _config privé hors save_load_system.gd" % count)

   func test_vc8_no_consumer_refs_in_save_load() -> void:
       var consumers := "\\b(CreditEconomy|Shop|ShopSystem|Secret|SecretSystem|Upgrade|UpgradeSystem|HUDController|HUDSystem|AudioSystem|InputManager|CameraSystem|CombatSystem|MovementController|VFXManager)\\b"
       var count := _run_grep(consumers, [SAVE_LOAD_PATH])
       assert_eq(count, 0, "VC-8 (R-SAV-17 + ADR-0010 D-5) : %s contient %d référence consumer gameplay" % [SAVE_LOAD_PATH, count])

   func test_vc9_no_outbound_signals_in_save_load() -> void:
       var count := _run_grep('^[[:space:]]*signal[[:space:]]+\\w+', [SAVE_LOAD_PATH])
       assert_eq(count, 0, "VC-9 (R-SAV-10) : %s déclare %d signal sortant — zero outbound MVP" % [SAVE_LOAD_PATH, count])

   func test_vc10_no_orchestration_connect_in_save_load() -> void:
       var count := _run_grep('\\.connect[[:space:]]*\\(', [SAVE_LOAD_PATH])
       assert_eq(count, 0, "VC-10 (R-SAV-11) : %s contient %d appel .connect — zero orchestration MVP" % [SAVE_LOAD_PATH, count])
   ```

2. **AC-SAV-28 scene tree introspection** — test runtime distinct (non-static) qui boot SaveLoadSystem et vérifie qu'aucun child UI / Audio n'est présent :
   ```gdscript
   func test_ac_sav_28_no_ui_or_audio_children() -> void:
       var save_load := preload("res://src/core/save_load_system.gd").new()
       add_child(save_load)
       await get_tree().process_frame
       for child in save_load.get_children():
           assert_false(child is Control, "AC-SAV-28 : SaveLoadSystem ne doit pas avoir de child Control")
           assert_false(child is AudioStreamPlayer, "AC-SAV-28 : SaveLoadSystem ne doit pas avoir de child AudioStreamPlayer")
       save_load.queue_free()
   ```

3. **CI integration** : après livraison story-007, ajouter à `.github/workflows/tests.yml` un job `lint-save-load-static` qui exécute `godot --headless --script tests/gdunit4_runner.gd --include tests/static/save_load_lint_test.gd` (cohérent CLAUDE.md Godot CLI safety rules — `--script` form mandatory).

4. **Exception process** : si lint VC-* fail à juste titre (genre Tier 2+ légitime), ajouter `# lint-save-load-*-ok: <raison>` commentaire sur la ligne offending. Pattern aligné `.claude/rules/level-signals-main-thread-only.md`.

---

## Out of Scope

- **Story 002 / 003 / 004 / 005 / 006**: implémentation des verbes — story-007 vérifie statiquement ce que les autres stories produisent.
- **Story 008** : perf gate `ConfigFile.save() < 1 ms` — perf, pas isolation.

---

## QA Test Cases

**AC-SAV-28** — runtime tree no UI/Audio children :
- Given : SaveLoadSystem instancié comme child d'un test scene
- When : iteration `save_load.get_children()`
- Then : 0 child de type Control / Label / Sprite / AudioStreamPlayer
- Edge cases : permission qu'un child Timer/Tween/Node de gestion interne existe (filtre uniquement UI/Audio).

**AC-SAV-29** — grep no outbound signals :
- Given : `src/core/save_load_system.gd` existe
- When : `grep -rE '^\s*signal\s+\w+' src/core/save_load_system.gd`
- Then : exit code != 0 (zero match) OU stdout vide
- Edge cases : tester aussi qu'un commentaire `# signal foo` n'est PAS un match (regex doit ignorer les comments via post-filter).

**AC-SAV-30** — grep no .connect( :
- Given : `src/core/save_load_system.gd` existe
- When : `grep -rE '\.connect\s*\(' src/core/save_load_system.gd`
- Then : zero match
- Edge cases : ignorer commentaires.

**AC-SAV-31** — grep no consumer imports :
- Given : `src/core/save_load_system.gd` existe
- When : grep des identifiants consumer gameplay
- Then : zero match
- Edge cases : tolérer mention dans commentaire d'en-tête (genre `# Outbound-zero : pas de référence à Credit, Shop, etc.`) en filtrant les lignes commencant par `#`.

**VC-6** — grep no Thread / WorkerThreadPool :
- Given : `src/core/save_load_system.gd` existe
- When : grep `\bThread\.|\bWorkerThreadPool\.`
- Then : zero match
- Edge cases : ignorer commentaires expliquant pourquoi PAS de thread.

**VC-7** — grep no _config access cross-fichier :
- Given : tous les fichiers `src/**/*.gd`
- When : grep `SaveLoadSystem\._config` (ou `SaveLoad._config`) en excluant `save_load_system.gd` lui-même
- Then : zero match
- Edge cases : aucune.

---

## Test Evidence

**Story Type**: Config/Data (lints static)
**Required evidence**:
- `tests/static/save_load_lint_test.gd` — must exist and pass (8 tests : 5 VC + 4 AC-SAV-28/29/30/31, dont AC-SAV-29 = VC-9 doublonne, AC-SAV-30 = VC-10 doublonne, AC-SAV-31 = VC-8 doublonne — soit 5 tests VC-6/7/8/9/10 + 1 test AC-SAV-28 runtime tree introspection = **6 tests effectifs**)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: **story-001** (skeleton existant), **story-002 + 003 + 004 + 005 + 006** (toutes les implémentations doivent exister pour que le grep cross-fichier soit significatif)
- Unlocks: CI fail-fast régression couplage cross-system — gate permanent qualité Foundation Persistence
