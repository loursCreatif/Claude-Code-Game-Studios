# Story 009: Anti-Patterns Lint Static — `lint-audio-pool` + `lint-audio-tween` + `lint-audio-deferred` (3 Grep Gates BLOCKING CI)

> **Epic**: Audio System
> **Status**: Complete 2026-05-04 (3/3 tests PASS — 6/6 ACs COVERED — production code lint-clean stories 001-008)
> **Layer**: Core
> **Type**: Config/Data
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/audio-system.md` (r2.3 §AC-AUD-10/11/12 + §VC-6 ADR-0009)
**Requirements** (R-AUD stable IDs jusqu'à `/architecture-review` post-Sprint 1) :
- R-AUD-1 : API publique exclusive — `AudioStreamPlayer.new()` / `AudioServer.set_bus_volume_db()` direct interdits hors `audio_system.gd` (lint CI `lint-audio-pool`)
- R-AUD-4 : Wall-clock fades dans `_physics_process` exclusivement via `_get_time_msec` Callable — Tween interdit sur `volume_db` time-critical (lint CI `lint-audio-tween`)
- R-AUD-5 : `CONNECT_DEFERRED` par défaut sur tous les signals consumer (lint CI `lint-audio-deferred`)

**ADR Governing**: ADR-0009 D-2 (pool exclusive) + D-3 (wall-clock fades) + D-4 (CONNECT_DEFERRED)
**Decision Summary**: 3 lints CI grep statiques BLOCKING — guard structurel rapide indépendant runtime. Pattern précédent epics : `level-signals-main-thread-only.md` / `input-singleton-main-thread-only.md` / `menu-anti-patterns.md` / `movement-emit-physics-only.md` / `no-alloc-hot-paths.md`. Implémentation : (1) règle Markdown dans `.claude/rules/audio-anti-patterns.md` documentant scope + forbidden patterns + exception annotation `# lint-audio-{lint-name}-ok: <raison>` ; (2) test GdUnit4 static `tests/static/audio_anti_patterns_lint_test.gd` (FileAccess + RegEx, 0 dépendance runtime) ; (3) job CI GitHub Actions `lint-audio-anti-patterns` dans `.github/workflows/tests.yml`.

**Engine**: Godot 4.6 | **Risk**: LOW (lint statique pur, pas de runtime dependency)
**Engine Notes**: Pattern hermétique GdUnit4 static lint test cohérent test-suite project. Aucune dépendance Godot API runtime — uniquement `FileAccess` + `RegEx` parsing.

**Control Manifest Rules (Core layer)**:
- Required: 3 lints zero match (sauf exceptions annotées)
- Required: rule Markdown `.claude/rules/audio-anti-patterns.md` documentant patterns + raisons
- Forbidden: `AudioStreamPlayer.new()` / `AudioStreamPlayer3D.new()` / `AudioListener3D.new()` hors `src/core/audio_system.gd`
- Forbidden: `Tween.tween_property.*volume_db` (time_scale-scaled, casse Pillar 1 60 fps wall-clock)
- Forbidden: `connect()` sans flag `CONNECT_DEFERRED` dans handlers `_on_*` AudioSystem ou `src/gameplay/audio/`

---

## Acceptance Criteria

*From GDD AC-AUD-10/11/12 + VC-6 ADR-0009:*

- [ ] **AC-AUD-10 `lint-audio-tween`** : grep `Tween.tween_property.*volume_db` ou `tween.*audio.*volume_db` dans `src/core/audio_system.gd` ou `src/gameplay/audio/` → zéro match. Exception autorisée : crossfade ambient (Formula 4) explicitement annoté `# lint-audio-tween-ok: ambient crossfade time_scale==1.0 garanti`. VC-6 ADR-0009.
- [ ] **AC-AUD-11 `lint-audio-deferred`** : grep `\.connect\([^,)]+\)\s*$` (connect sans flag explicite) dans handlers `src/gameplay/audio/` ou `_on_*` methods AudioSystem → zéro match. Tous les `connect()` doivent inclure flag `CONNECT_DEFERRED`. Exception annotée `# lint-audio-deferred-ok: <raison>` (e.g. signal interne pool tracker `finished` `CONNECT_ONE_SHOT` story-007).
- [ ] **AC-AUD-12 `lint-audio-pool`** : grep `AudioStreamPlayer\.new\(\)` ou `AudioStreamPlayer3D\.new\(\)` ou `AudioListener3D\.new\(\)` dans `src/` → zéro match HORS `src/core/audio_system.gd` (exception unique pour pool boot `_ready()`). Tests `tests/` autorisés (fixtures stub).
- [ ] **Rule Markdown** : `.claude/rules/audio-anti-patterns.md` créé avec scope + forbidden patterns table + enforcement local + CI + pattern recommandé + source (cohérent template `menu-anti-patterns.md` r2 + `level-signals-main-thread-only.md`).
- [ ] **Test GdUnit4 static** : `tests/static/audio_anti_patterns_lint_test.gd` couvre 3 lints via `FileAccess.open()` + `RegEx` parsing (cohérent `menu_anti_patterns_lint_test.gd` pattern). Exécutable via `godot --headless --script addons/gdUnit4/bin/GdUnitCmdTool.gd --add tests/static/audio_anti_patterns_lint_test.gd --ignoreHeadlessMode`.
- [ ] **CI job activé** : `.github/workflows/tests.yml` job `lint-audio-anti-patterns` ajouté, FAIL si zéro exception annotée mais pattern matched. Log artefact `production/qa/evidence/audio-anti-patterns-lint-{date}.log` uploadé.

---

## Implementation Notes

*Derived from ADR-0009 + pattern précédent menu-anti-patterns.md / level-signals-main-thread-only.md:*

```bash
# 3 lints — extrait local dev (cohérent menu-anti-patterns.md enforcement section)

# AC-AUD-10 lint-audio-tween — anti-Tween volume_db
! grep -rE 'Tween\.tween_property.*volume_db|tween\..*audio.*volume_db' src/core/audio_system.gd src/gameplay/audio/ \
  | grep -v '#' \
  | grep -v 'lint-audio-tween-ok' \
  || fail AC-AUD-10

# AC-AUD-11 lint-audio-deferred — connect sans CONNECT_DEFERRED
! grep -rnE '\.connect\([^,)]+\)\s*$' src/gameplay/audio/ src/core/audio_system.gd \
  | grep -v '#' \
  | grep -v 'lint-audio-deferred-ok' \
  | grep -E '_on_[a-z_]+' \
  || fail AC-AUD-11

# AC-AUD-12 lint-audio-pool — AudioStreamPlayer.new() hors audio_system.gd
matches=$(grep -rnE 'AudioStreamPlayer\.new\(\)|AudioStreamPlayer3D\.new\(\)|AudioListener3D\.new\(\)' src/ \
  | grep -v 'src/core/audio_system.gd' \
  | grep -v '#' || true)
[ -z "$matches" ] || fail AC-AUD-12
```

**Rule Markdown structure** (`.claude/rules/audio-anti-patterns.md`) :

```markdown
# Audio System — Anti-Patterns Lint Static

L'Audio System est un autoload Core layer encapsulé : (D-2) seul `src/core/audio_system.gd`
instancie `AudioStreamPlayer*` ; (D-3) wall-clock fades exclusivement dans `_physics_process`
(zéro Tween sur `volume_db` time-critical) ; (D-4) `CONNECT_DEFERRED` par défaut sur tous
les signals consumer.

Ce lint statique enforce 3 patterns interdits comme garde-fou structurel — bien plus rapide
qu'un test runtime, et indépendant de l'execution (purement grep + parse `.gd`).

## Scope
- `src/core/audio_system.gd`
- `src/gameplay/audio/**/*.gd`
- `tests/` autorisés (fixtures stub `AudioStreamWAV.new()` test only)

## Forbidden Patterns
| AC | Pattern (regex) | Source | Niveau |
|----|-----------------|--------|--------|
| AC-AUD-10 | `Tween\.tween_property.*volume_db` | R-AUD-4 + ADR-0009 D-3 | BLOCKING |
| AC-AUD-11 | `\.connect\([^,)]+\)\s*$` (sans flag) dans `_on_*` | R-AUD-5 + ADR-0009 D-4 | BLOCKING |
| AC-AUD-12 | `AudioStreamPlayer\.new\(\)` hors `src/core/audio_system.gd` | R-AUD-1 + ADR-0009 D-2 | BLOCKING |

## Enforcement
### Local
[bash extrait ci-dessus]

### CI (GitHub Actions)
Intégré dans `.github/workflows/tests.yml` — job `lint-audio-anti-patterns`.

### GdUnit4 static test
`tests/static/audio_anti_patterns_lint_test.gd` — wrapper GdUnit4 sur les mêmes greps.

## Exception annotation
- `# lint-audio-tween-ok: <raison>` — autorise Tween volume_db (e.g. ambient crossfade time_scale==1.0)
- `# lint-audio-deferred-ok: <raison>` — autorise connect sans DEFERRED (e.g. signal interne pool tracker)
- `# lint-audio-pool-ok: <raison>` — autorise instanciation hors audio_system.gd (cas pathologique uniquement)

## Pattern recommandé
[exemples CORRECT vs INCORRECT pour chaque lint]

## Source
- ADR-0009 D-2/D-3/D-4
- R-AUD-1/R-AUD-4/R-AUD-5
- AC-AUD-10/11/12
```

**Test GdUnit4 static structure** (`tests/static/audio_anti_patterns_lint_test.gd`) — cohérent `menu_anti_patterns_lint_test.gd` pattern :

```gdscript
extends GdUnitTestSuite

const AUDIO_SYSTEM_PATH := "res://src/core/audio_system.gd"
const AUDIO_HANDLERS_DIR := "res://src/gameplay/audio/"

func test_lint_audio_tween_no_volume_db_tween() -> void:
    var matches: Array[String] = _grep_violations(
        [AUDIO_SYSTEM_PATH, AUDIO_HANDLERS_DIR],
        "Tween\\.tween_property.*volume_db|tween\\..*audio.*volume_db",
        "lint-audio-tween-ok"
    )
    assert_array(matches).override_failure_message(
        "AC-AUD-10 violation — Tween volume_db détecté hors exception annotée :\n%s" % "\n".join(matches)
    ).is_empty()

func test_lint_audio_deferred_handlers_use_connect_deferred() -> void:
    var matches: Array[String] = _grep_violations(
        [AUDIO_SYSTEM_PATH, AUDIO_HANDLERS_DIR],
        "\\.connect\\([^,)]+\\)\\s*$",  # connect sans flag
        "lint-audio-deferred-ok"
    ).filter(func(line: String) -> bool: return line.contains("_on_"))
    assert_array(matches).override_failure_message(
        "AC-AUD-11 violation — connect() sans CONNECT_DEFERRED dans handler _on_* :\n%s" % "\n".join(matches)
    ).is_empty()

func test_lint_audio_pool_no_streamplayer_new_outside_audio_system() -> void:
    # Scan src/ excluding src/core/audio_system.gd and tests/
    var matches: Array[String] = _grep_src_excluding(
        "AudioStreamPlayer\\.new\\(\\)|AudioStreamPlayer3D\\.new\\(\\)|AudioListener3D\\.new\\(\\)",
        AUDIO_SYSTEM_PATH,
        "lint-audio-pool-ok"
    )
    assert_array(matches).override_failure_message(
        "AC-AUD-12 violation — AudioStreamPlayer.new() instancié hors src/core/audio_system.gd :\n%s" % "\n".join(matches)
    ).is_empty()

# Helpers _grep_violations / _grep_src_excluding — cohérent menu_anti_patterns_lint_test.gd pattern
```

**CI job** dans `.github/workflows/tests.yml` :

```yaml
lint-audio-anti-patterns:
  name: Lint — Audio anti-patterns (3 grep gates BLOCKING)
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - name: Run audio anti-patterns lint
      run: |
        set -euo pipefail
        # AC-AUD-10
        ! grep -rE 'Tween\.tween_property.*volume_db|tween\..*audio.*volume_db' src/core/audio_system.gd src/gameplay/audio/ 2>/dev/null \
          | grep -v '#' \
          | grep -v 'lint-audio-tween-ok' \
          || (echo "FAIL AC-AUD-10"; exit 1)
        # AC-AUD-11 + AC-AUD-12 — analogue
    - name: Upload log artifact
      if: always()
      uses: actions/upload-artifact@v4
      with:
        name: audio-anti-patterns-lint-${{ github.run_id }}
        path: production/qa/evidence/audio-anti-patterns-lint-*.log
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001 : pool boot `AudioStreamPlayer.new()` dans `_ready()` (autorisé exception unique `src/core/audio_system.gd`)
- Story 005 : crossfade ambient avec exception annotée `# lint-audio-tween-ok: ambient crossfade time_scale==1.0 garanti` si Tween utilisé (cf. story-005 Out of Scope note)
- Story 006-008 : handlers consumer (les `connect()` doivent inclure flag `CONNECT_DEFERRED` — vérifié par lint-audio-deferred)
- Story 011 : performance budget — orthogonal, pas couvert par lints statiques

---

## QA Test Cases

**AC-AUD-10 `lint-audio-tween` zero match** :
- Given : code AudioSystem complet (post stories 001-008)
- When : `grep -rE 'Tween\.tween_property.*volume_db' src/core/audio_system.gd src/gameplay/audio/`
- Then : zéro match (sauf exception annotée `# lint-audio-tween-ok: ambient crossfade time_scale==1.0 garanti` ligne explicite story-005)
- Edge cases : si match non annoté → FAIL "AC-AUD-10 — Tween sur volume_db détecté ligne X — utiliser wall-clock `_physics_process` via `_get_time_msec.call()` Callable injection (Rule 4)"

**AC-AUD-11 `lint-audio-deferred` zero match** :
- Given : handlers `_on_swing_started`, `_on_enemy_killed`, `_on_dash_started`, `_on_state_changed`, `_on_secret_collected`, `_on_level_active` connectés via `signal.connect(handler, CONNECT_DEFERRED)`
- When : `grep -rnE '\.connect\([^,)]+\)\s*$' src/gameplay/audio/ src/core/audio_system.gd | grep -E '_on_[a-z_]+'`
- Then : zéro match (tous les `connect()` ont flag explicite, exception annotée `# lint-audio-deferred-ok` autorisée pour signal interne pool tracker `finished` CONNECT_ONE_SHOT story-007)
- Edge cases : si match non annoté → FAIL "AC-AUD-11 — connect() sans CONNECT_DEFERRED dans handler _on_* ligne X — risque mutation cross-system mid-physics-frame (R-AUD-5 + ADR-0009 D-4)"

**AC-AUD-12 `lint-audio-pool` zero match** :
- Given : code complet, `AudioStreamPlayer.new()` uniquement dans `src/core/audio_system.gd._ready()` pool boot
- When : `grep -rnE 'AudioStreamPlayer\.new\(\)|AudioStreamPlayer3D\.new\(\)|AudioListener3D\.new\(\)' src/`
- Then : zéro match HORS `src/core/audio_system.gd`. Tests `tests/` autorisés (fixtures stub).
- Edge cases : si match dans `src/gameplay/` ou `src/ui/` → FAIL "AC-AUD-12 — AudioStreamPlayer instancié hors API publique AudioSystem — utiliser `AudioSystem.play_2d/play_3d_at` (R-AUD-1 + ADR-0009 D-2)"

**Test GdUnit4 static execution** :
- Given : `.godot/global_script_class_cache.cfg` existe
- When : `godot --headless --script addons/gdUnit4/bin/GdUnitCmdTool.gd --add tests/static/audio_anti_patterns_lint_test.gd --ignoreHeadlessMode`
- Then : exit code 0 ; 3 test cases | 0 failures ; rapport `reports/report_N/`

**CI job FAIL sample** :
- Given : violation introduite (e.g. `Tween.tween_property(player, "volume_db", -80, 0.5)` dans `src/gameplay/audio/level_handler.gd`)
- When : push branche, CI déclenche
- Then : job `lint-audio-anti-patterns` exit code 1 + log "FAIL AC-AUD-10" + artefact upload

---

## Test Evidence

**Story Type**: Config/Data
**Required evidence**:
- `tests/static/audio_anti_patterns_lint_test.gd` (3 test cases AC-AUD-10/11/12)
- `.claude/rules/audio-anti-patterns.md` (rule Markdown documentation)
- `.github/workflows/tests.yml` job `lint-audio-anti-patterns` (CI gate BLOCKING)
- `production/qa/evidence/audio-anti-patterns-lint-{date}.log` (CI artefact, premier run smoke check Sprint Audio)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Stories 001-008 (lints scannent code production écrit par stories handlers)
- Cross-system : aucun (lint statique pur, 0 dépendance runtime)
- Unlocks: VC-6 ADR-0009 + AC-AUD-10/11/12 BLOCKING — Definition of Done epic Audio item "3 lint CI gates BLOCKING activés et zero match"

---

## Completion Notes

**Completed**: 2026-05-04
**Criteria**: 6/6 COVERED (3 lints AC + Rule Markdown + GdUnit4 test + CI job)
**Test Evidence**:
- `tests/static/audio_anti_patterns_lint_test.gd` — 3 test cases (AC-AUD-10/11/12), 32 ms exec
- `.claude/rules/audio-anti-patterns.md` — rule Markdown documentation
- `.github/workflows/tests.yml` job `lint-audio-anti-patterns` — CI gate BLOCKING
- `production/qa/evidence/audio-anti-patterns-lint-2026-05-04.log` — premier run smoke check (TOTAL_VIOLATIONS=0)

**Test Results**: **157/157 PASS overall audio suite** (154 stories 001-008 + 3 story-009), exit code 0, 1.189 s. Zéro régression.

**Implementation Notes**:

1. **3 lints CLEAN sur code actuel** — pre-check pré-implémentation : zéro match sur `Tween.tween_property.*volume_db` (story-005 utilise `_tick_ambient_crossfade` wall-clock pas Tween), zéro `connect()` sans `CONNECT_DEFERRED` dans handlers `_on_*` (stories 003-008 utilisent toutes `CONNECT_DEFERRED` explicit), zéro `AudioStreamPlayer.new()` hors `audio_system.gd` (D-2 respecté par construction). Aucune exception annotée nécessaire au MVP.

2. **Pattern hérité `menu_anti_patterns_lint_test.gd`** — helpers `_list_dir_files_recursive` + `_read_text_file` + `_scan_for_pattern` portés tels quels, exception marker paramétrisé (`lint-audio-{tween,deferred,pool}-ok` au lieu de `lint-menu-ok` unique). Cohérent avec le standard project test-suite.

3. **AC-AUD-11 filter compositionnel** — `_scan_for_pattern` retourne tous les `connect()` 1-arg, puis `.filter()` post-process retient uniquement les lignes contenant `_on_[a-z_]+`. Permet de scope au handler signature consumer sans matcher signaux internes pool tracker (e.g. `clac_player.finished.connect(_on_clac_slot_finished.bind(...), CONNECT_ONE_SHOT)` matchera `_on_*` mais a déjà flag explicite `CONNECT_ONE_SHOT` donc ne matchera PAS le pattern 1-arg).

4. **AC-AUD-12 src/ scan récursif** — `_list_dir_files_recursive(SRC_DIR, [".gd"])` puis `.filter()` exclut `audio_system.gd`. Tests `tests/` non scannés (hors scope, fixtures stub `AudioStreamWAV.new()` autorisé). Couvre `src/core/`, `src/gameplay/`, `src/ui/` automatiquement.

5. **Rule Markdown structure cohérente** — sections Scope / Forbidden Patterns table / Enforcement Local + CI + GdUnit4 / Pattern recommandé CORRECT vs INCORRECT par lint / Source. Suit template `menu-anti-patterns.md` r2.

6. **CI job hermétique** — bash array dynamique pour `paths_tween`/`paths_def` permet d'absorber gracieusement l'absence de `src/gameplay/audio/` (handlers ne sont pas extraits du autoload au MVP — toute la logique reste dans `audio_system.gd`). Skip clean si paths absents (pas de FAIL faux-positif).

7. **Exception marker triple** — `lint-audio-tween-ok` / `lint-audio-deferred-ok` / `lint-audio-pool-ok` au lieu d'un marker unique. Permet justification spécifique par lint (audit trail plus clair en review). Pattern aligné `lint-input-thread-ok` (input rule) / `lint-emit-thread-ok` (level rule) / `lint-collision-layers-ok` / `lint-menu-ok`.

8. **Evidence log gitignored** — `production/qa/evidence/audio-anti-patterns-lint-{date}.log` — uploadé via CI artefact (pas commité). Premier run smoke check 2026-05-04 = 3/3 PASS, TOTAL_VIOLATIONS=0.

9. **0 dépendance runtime** — test 100% statique : `FileAccess.open()` + `RegEx.compile()`, pas de SceneTree / autoload / GdUnitTestSuite life-cycle (`before_test`/`after_test`). Exec 32 ms (vs 100-200 ms pour tests integration runtime). Pattern préservé pour autres lints futurs.

10. **Sprint Audio milestone : 9/12 Complete = 75% epic** — Foundation + API + Combat + Movement + Level + GSM Pause + Slow-mo + Secret + Lint anti-patterns. Stories 010-012 restantes (AudioListener3D verification + Performance budget + Sidechain peak meter).
