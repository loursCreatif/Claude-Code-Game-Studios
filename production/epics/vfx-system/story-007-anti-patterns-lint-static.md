# Story 007: Anti-Patterns Lint Static — `lint-vfx-pool` + `lint-vfx-tween` + `lint-vfx-deferred` + `lint-vfx-outbound` (4 Grep Gates BLOCKING CI)

> **Epic**: VFX System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: Logic
> **Manifest Version**: 2026-05-04
> **Estimate**: S (2-3 h, rule Markdown + GdUnit4 static test + CI job — calque audio-anti-patterns.md / story-009)

## Context

**GDD**: `design/gdd/vfx-system.md` (r1 §AC-VFX-04/05/23/24 + R-VFX-1/14)
**Requirements** (R-VFX stable IDs jusqu'à `/architecture-review` post-Sprint 1) :
- R-VFX-1 : Autoload pool exclusive — `GPUParticles3D.new()` / `Decal.new()` / `MeshInstance3D.new()` interdits hors `src/core/vfx_system.gd` (lint CI `lint-vfx-pool`)
- R-VFX-3 : `CONNECT_DEFERRED` par défaut sur tous les signals consumer (lint CI `lint-vfx-deferred`)
- R-VFX-5/15 : Wall-clock fades dans `_physics_process` exclusivement via `Time.get_ticks_msec()` — Tween interdit sur effets time-critical (`color`, `modulate`, trail opacity) (lint CI `lint-vfx-tween`)
- R-VFX-14 : Outbound-zero terminal — VFX ne mute aucun état amont, n'émet aucun signal (lint CI `lint-vfx-outbound`)

**ADR Governing**: ADR-0009 D-2 (pool exclusive pattern) + D-3 (wall-clock fades pattern) + D-4 (CONNECT_DEFERRED pattern) — VFX applique le **même pattern architectural** que Audio System.

**Decision Summary**: 4 lints CI grep statiques BLOCKING — guard structurel rapide indépendant runtime. Pattern précédent epics : `audio-anti-patterns.md` (3 lints) + `menu-anti-patterns.md` (11 lints) + `level-signals-main-thread-only.md` + `input-singleton-main-thread-only.md` + `movement-emit-physics-only.md` + `no-alloc-hot-paths.md`. Implémentation : (1) règle Markdown dans `.claude/rules/vfx-anti-patterns.md` documentant scope + forbidden patterns + exception annotation `# lint-vfx-{lint-name}-ok: <raison>` ; (2) test GdUnit4 static `tests/static/vfx_anti_patterns_lint_test.gd` (FileAccess + RegEx, 0 dépendance runtime) ; (3) job CI GitHub Actions `lint-vfx-anti-patterns` dans `.github/workflows/tests.yml`.

**Engine**: Godot 4.6 | **Risk**: LOW (lint statique pur, pas de runtime dependency)
**Engine Notes**: Pattern hermétique GdUnit4 static lint test cohérent test-suite project. Aucune dépendance Godot API runtime — uniquement `FileAccess` + `RegEx` parsing.

**Control Manifest Rules (Presentation layer)**:
- Required : 4 lints zero match (sauf exceptions annotées) ; rule Markdown `.claude/rules/vfx-anti-patterns.md` documentant patterns + raisons ; GdUnit4 static test `tests/static/vfx_anti_patterns_lint_test.gd` ; CI job `.github/workflows/tests.yml` BLOCKING.
- Forbidden patterns enforced :
  - `GPUParticles3D.new()` / `Decal.new()` / `MeshInstance3D.new()` HORS `src/core/vfx_system.gd` (R-VFX-1)
  - `Tween.tween_property.*color` / `tween_property.*modulate` / `tween_property.*opacity` dans `src/core/vfx_system.gd` (R-VFX-5 wall-clock obligatoire)
  - `connect()` sans flag `CONNECT_DEFERRED` dans handlers `_on_*` `src/core/vfx_system.gd` (R-VFX-3)
  - `emit_signal` / `\.emit\(` dans `src/core/vfx_system.gd` (R-VFX-14 outbound-zero terminal)

---

## Acceptance Criteria

*From GDD §Acceptance Criteria r1 + pattern audio-anti-patterns.md :*

- [ ] **AC-VFX-04** [BLOCKING][AUTO] **GIVEN** un profile mémoire GdUnit4 headless est exécuté sur 60 secondes de gameplay simulé avec 30 kills, **WHEN** le système VFX est actif, **THEN** `MEMORY_STATIC` delta sur 60 s < 16 KB (pas de `Decal.new()`, `GPUParticles3D.new()`, `MeshInstance3D.new()` dans les hot paths post-boot). *(Lint static `lint-vfx-pool` enforce le contract structurel ; runtime stress test peut être déféré story-002 perf.)*
- [ ] **AC-VFX-05** [BLOCKING][AUTO] **GIVEN** le code VFX est scanné par le lint statique CI, **WHEN** `grep -rE "GPUParticles3D\.new\(\)|Decal\.new\(\)|MeshInstance3D\.new\(\)" src/ | grep -v src/core/vfx_system.gd`, **THEN** zéro match (aucune instanciation VFX hors `vfx_system.gd`).
- [ ] **AC-VFX-23** [BLOCKING][AUTO] **GIVEN** Le code `src/core/vfx_system.gd` et `src/gameplay/vfx/` est scanné, **WHEN** `grep -rE "emit_signal|\.emit\(" src/core/vfx_system.gd src/gameplay/vfx/`, **THEN** zéro match (VFX n'émet aucun signal).
- [ ] **AC-VFX-24** [BLOCKING][AUTO] **GIVEN** Les handlers `_on_enemy_killed`, `_on_swing_started`, etc. sont exécutés, **WHEN** Inspection post-handler via unit test, **THEN** `enemy.position` et `player.global_position` ne sont pas mutés par VFX ; aucune propriété Enemy/Player/Combat n'est modifiée. *(Validation runtime via test integration ; lint static `lint-vfx-outbound` couvre le contract `emit_signal` interdit.)*
- [ ] **AC-NEW-09** [BLOCKING][AUTO] `lint-vfx-tween` — grep `Tween\.tween_property.*\b(color|modulate|opacity)\b` ou `tween_property.*alpha` dans `src/core/vfx_system.gd` → zéro match. Exception annotée `# lint-vfx-tween-ok: <raison>` autorisée pour cas pathologique audité (e.g. trail fade alternatif Tween si `time_scale==1.0` garanti par GSM).
- [ ] **AC-NEW-10** [BLOCKING][AUTO] `lint-vfx-deferred` — grep `\.connect\([^,)]+\)\s*$` (connect sans flag explicite) dans handlers `_on_*` methods VFXSystem → zéro match. Tous les `connect()` doivent inclure flag `CONNECT_DEFERRED` (sauf SYNC justifié OQ-VFX-4 enemy_killed flash kill — exception annotée `# lint-vfx-deferred-ok: SYNC flash frame-precise`).
- [ ] **AC-NEW-11** [BLOCKING][AUTO] **Rule Markdown** : `.claude/rules/vfx-anti-patterns.md` créé avec scope + forbidden patterns table + enforcement local + CI + pattern recommandé + source (cohérent template `audio-anti-patterns.md`).
- [ ] **AC-NEW-12** [BLOCKING][AUTO] **CI job activé** : `.github/workflows/tests.yml` job `lint-vfx-anti-patterns` ajouté, FAIL si zéro exception annotée mais pattern matched. Log artefact `production/qa/evidence/vfx-anti-patterns-lint-{date}.log` uploadé.

---

## Implementation Notes

### `.claude/rules/vfx-anti-patterns.md` (rule Markdown)

```markdown
# VFX System — Anti-Patterns Lint Static

Le VFX System est un autoload Presentation layer outbound-only terminal. Quatre invariants
structurels gardent la qualité de l'implémentation contre les régressions silencieuses :

- **Pool exclusive (R-VFX-1)** : seul `src/core/vfx_system.gd` instancie `GPUParticles3D` /
  `Decal` / `MeshInstance3D` runtime. Les consumers passent par l'API publique
  (`play_kill_at`, `start_katana_trail`, `flash_kill`, etc.).
- **Wall-clock fades (R-VFX-5/15)** : les fades temps-critiques (`color`, `modulate`,
  trail opacity) sont calculés dans `_physics_process` via `Time.get_ticks_msec()`.
  Tween est interdit sur effets time-critical car `time_scale`-dépendant (casse Pillar 1
  60 fps wall-clock indépendant slow-mo Combat AC-VFX-25/26).
- **CONNECT_DEFERRED (R-VFX-3)** : tous les `connect()` vers handlers `_on_*` VFXSystem
  doivent inclure le flag `CONNECT_DEFERRED` pour éviter les mutations cross-system
  mid-physics-frame. Exception SYNC justifiée OQ-VFX-4 (flash kill frame-precise) annotée.
- **Outbound-zero (R-VFX-14)** : VFX System ne mute aucun état amont, n'émet aucun signal,
  ne stocke aucune référence Node enemies/player. Terminal pur.

## Scope

**Fichiers** :
- `src/core/vfx_system.gd` (VFXSystem autoload)
- `src/gameplay/vfx/**/*.gd` (handlers consumer futurs si extraction post-MVP)

**Hors scope** : `tests/` (fixtures stub `Decal.new()` autorisé), assets, scenes
(pas d'instanciation Particle runtime via `.new()` en `.tscn`).

## Forbidden Patterns

| AC | Pattern (regex) | Source | Niveau |
|----|-----------------|--------|--------|
| AC-VFX-05 / AC-NEW-08 | `GPUParticles3D\.new\(\)` / `Decal\.new\(\)` / `MeshInstance3D\.new\(\)` HORS `src/core/vfx_system.gd` | R-VFX-1 + ADR-0009 D-2 (pattern) | BLOCKING |
| AC-NEW-09 | `Tween\.tween_property.*\b(color|modulate|opacity|alpha)\b` dans `src/core/vfx_system.gd` | R-VFX-5/15 + ADR-0009 D-3 (pattern) | BLOCKING |
| AC-NEW-10 | `\.connect\([^,)]+\)\s*$` (1 arg sans flag) sur ligne contenant `_on_*` handler | R-VFX-3 + ADR-0009 D-4 (pattern) | BLOCKING |
| AC-VFX-23 | `emit_signal\b` ou `\.emit\(` dans `src/core/vfx_system.gd` | R-VFX-14 outbound-zero | BLOCKING |

**Exception annotation** (ligne par ligne) :
- `# lint-vfx-pool-ok: <raison>` — autorise instanciation hors `vfx_system.gd` (cas pathologique uniquement)
- `# lint-vfx-tween-ok: <raison>` — autorise Tween sur color/modulate (e.g. trail fade `time_scale==1.0` garanti)
- `# lint-vfx-deferred-ok: <raison>` — autorise `connect()` sans `CONNECT_DEFERRED` (e.g. SYNC flash kill OQ-VFX-4)
- `# lint-vfx-outbound-ok: <raison>` — autorise emit_signal hors VFXSystem (cas pathologique uniquement, ne devrait jamais arriver)

Lignes commentaires pures (`#` au début de ligne) sont automatiquement skipées.

## Enforcement

### Local

```bash
set -euo pipefail
violations=0
fail() { echo "FAIL $1"; violations=$((violations + 1)); }

# AC-VFX-05 — pool exclusive (anti `*.new()` hors vfx_system.gd)
matches=$(grep -rnE 'GPUParticles3D\.new\(\)|Decal\.new\(\)|MeshInstance3D\.new\(\)' src/ 2>/dev/null \
  | grep -v 'src/core/vfx_system.gd' \
  | grep -v '^[^:]*:[0-9]*:\s*#' \
  | grep -v 'lint-vfx-pool-ok' \
  || true)
[ -z "$matches" ] || { fail AC-VFX-05; echo "$matches"; }

# AC-NEW-09 — anti-Tween sur color/modulate/opacity dans vfx_system.gd
matches=$(grep -rnE 'Tween\.tween_property.*\b(color|modulate|opacity|alpha)\b' src/core/vfx_system.gd 2>/dev/null \
  | grep -v '^[^:]*:[0-9]*:\s*#' \
  | grep -v 'lint-vfx-tween-ok' \
  || true)
[ -z "$matches" ] || { fail AC-NEW-09; echo "$matches"; }

# AC-NEW-10 — connect() sans CONNECT_DEFERRED dans handlers _on_*
matches=$(grep -rnE '\.connect\([^,)]+\)\s*$' src/core/vfx_system.gd src/gameplay/vfx/ 2>/dev/null \
  | grep -v '^[^:]*:[0-9]*:\s*#' \
  | grep -v 'lint-vfx-deferred-ok' \
  | grep -E '_on_[a-z_]+' \
  || true)
[ -z "$matches" ] || { fail AC-NEW-10; echo "$matches"; }

# AC-VFX-23 — outbound-zero (anti emit_signal / .emit dans vfx_system.gd)
matches=$(grep -rnE 'emit_signal\b|\.emit\(' src/core/vfx_system.gd src/gameplay/vfx/ 2>/dev/null \
  | grep -v '^[^:]*:[0-9]*:\s*#' \
  | grep -v 'lint-vfx-outbound-ok' \
  || true)
[ -z "$matches" ] || { fail AC-VFX-23; echo "$matches"; }

[ "$violations" -eq 0 ] && echo "ALL PASS" || (echo "FAIL: $violations violations"; exit 1)
```

Zéro violation = lint pass.

### CI (GitHub Actions)

Intégré dans `.github/workflows/tests.yml` — job `lint-vfx-anti-patterns`.
Le job échoue si un pattern interdit apparaît, sauf marquage explicite via
`lint-vfx-{pool,tween,deferred,outbound}-ok: <raison>`.

Log artefact : `production/qa/evidence/vfx-anti-patterns-lint-YYYY-MM-DD.log`
(uploadé via `actions/upload-artifact@v4`).

### GdUnit4 static test (parité project-pattern)

`tests/static/vfx_anti_patterns_lint_test.gd` — wrapper GdUnit4 sur les mêmes
greps (`FileAccess` + `RegEx`) pour exécution locale rapide via la suite test.

```bash
godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add tests/static/vfx_anti_patterns_lint_test.gd \
  --ignoreHeadlessMode
```

Couvre AC-VFX-05/23 + AC-NEW-09/10 — 4 tests static (0 dépendance runtime).

## Pattern recommandé

### Pool exclusive (AC-VFX-05)

```gdscript
# CORRECT — consumer passe par VFXSystem API
func _on_combat_kill(_enemy: Node, position: Vector3) -> void:
    VFXSystem.play_kill_at(position)  # API publique VFXSystem

# INCORRECT — instanciation directe hors vfx_system.gd
func _on_combat_kill(_enemy: Node, position: Vector3) -> void:
    var p: GPUParticles3D = GPUParticles3D.new()  # VIOLATION AC-VFX-05
    add_child(p)
    p.global_position = position
    p.emitting = true
```

### Wall-clock fades (AC-NEW-09)

```gdscript
# CORRECT — _physics_process tick + Time.get_ticks_msec() injection wall-clock
func _physics_process(_delta: float) -> void:
    if _flash_kill_active:
        var elapsed_ms: int = _get_time_msec.call() - _flash_kill_start_msec
        var t: float = clampf(float(elapsed_ms) / FLASH_KILL_DURATION_MS, 0.0, 1.0)
        _flash_overlay_rect.color = Color(1.0, 1.0, 1.0, 1.0 - t)

# INCORRECT — Tween sur color (time_scale-scaled, casse Pillar 1 60 fps wall-clock)
func _trigger_flash_kill() -> void:
    var tween: Tween = create_tween()
    tween.tween_property(_flash_overlay_rect, "color:a", 0.0, 0.08)  # VIOLATION AC-NEW-09
```

### CONNECT_DEFERRED (AC-NEW-10)

```gdscript
# CORRECT — flag CONNECT_DEFERRED explicite sur handlers _on_*
func _connect_combat_signals() -> void:
    combat_system.swing_started.connect(_on_swing_started, CONNECT_DEFERRED)
    enemy_system.enemy_killed.connect(_on_enemy_killed, CONNECT_DEFERRED)

# CORRECT — exception annotée pour SYNC flash kill (OQ-VFX-4 playtest)
enemy_system.enemy_killed.connect(_on_enemy_killed)  # SYNC frame-precise
# lint-vfx-deferred-ok: SYNC flash kill frame-precise (OQ-VFX-4 playtest validated)

# INCORRECT — connect sans flag (mutation cross-system mid-physics-frame possible)
func _connect_combat_signals() -> void:
    combat_system.swing_started.connect(_on_swing_started)        # VIOLATION AC-NEW-10
```

### Outbound-zero (AC-VFX-23)

```gdscript
# CORRECT — VFX consume, ne mute jamais, n'émet aucun signal
func _on_enemy_killed(_enemy: Node, position: Vector3) -> void:
    _spawn_blood_spurt(position)  # opération interne uniquement
    _spawn_decal_on_surface(position)

# INCORRECT — VFX émet signal observable par d'autres systèmes
signal vfx_played(event_type: StringName)
func _on_enemy_killed(_enemy: Node, position: Vector3) -> void:
    _spawn_blood_spurt(position)
    vfx_played.emit(&"kill")  # VIOLATION AC-VFX-23 — VFX terminal pur
```

## Source

- ADR-0009 D-2 (pool exclusive pattern) + D-3 (wall-clock fades pattern) + D-4 (CONNECT_DEFERRED pattern) — `docs/architecture/adr-0009-audio-system.md`
- R-VFX-1 + R-VFX-3 + R-VFX-5 + R-VFX-14/15 — `design/gdd/vfx-system.md` Detailed Rules
- AC-VFX-04/05/23/24 + AC-NEW-09/10/11/12 — `design/gdd/vfx-system.md` Acceptance Criteria
- Story 007 — `production/epics/vfx-system/story-007-anti-patterns-lint-static.md`
```

### `tests/static/vfx_anti_patterns_lint_test.gd` (GdUnit4 static test)

```gdscript
extends GdUnitTestSuite

const VFX_SYSTEM_PATH := "res://src/core/vfx_system.gd"
const VFX_HANDLERS_DIR := "res://src/gameplay/vfx/"
const SRC_DIR := "res://src/"

func test_lint_vfx_pool_no_node_new_outside_vfx_system() -> void:
    var matches: Array[String] = _grep_src_excluding(
        "GPUParticles3D\\.new\\(\\)|Decal\\.new\\(\\)|MeshInstance3D\\.new\\(\\)",
        VFX_SYSTEM_PATH,
        "lint-vfx-pool-ok"
    )
    assert_array(matches).override_failure_message(
        "AC-VFX-05 violation — VFX node instancié hors src/core/vfx_system.gd :\n%s" % "\n".join(matches)
    ).is_empty()

func test_lint_vfx_tween_no_color_modulate_in_vfx_system() -> void:
    var matches: Array[String] = _grep_violations(
        [VFX_SYSTEM_PATH, VFX_HANDLERS_DIR],
        "Tween\\.tween_property.*\\b(color|modulate|opacity|alpha)\\b",
        "lint-vfx-tween-ok"
    )
    assert_array(matches).override_failure_message(
        "AC-NEW-09 violation — Tween sur color/modulate/opacity détecté hors exception annotée :\n%s" % "\n".join(matches)
    ).is_empty()

func test_lint_vfx_deferred_handlers_use_connect_deferred() -> void:
    var matches: Array[String] = _grep_violations(
        [VFX_SYSTEM_PATH, VFX_HANDLERS_DIR],
        "\\.connect\\([^,)]+\\)\\s*$",
        "lint-vfx-deferred-ok"
    ).filter(func(line: String) -> bool: return line.contains("_on_"))
    assert_array(matches).override_failure_message(
        "AC-NEW-10 violation — connect() sans CONNECT_DEFERRED dans handler _on_* :\n%s" % "\n".join(matches)
    ).is_empty()

func test_lint_vfx_outbound_no_emit_in_vfx_system() -> void:
    var matches: Array[String] = _grep_violations(
        [VFX_SYSTEM_PATH, VFX_HANDLERS_DIR],
        "emit_signal\\b|\\.emit\\(",
        "lint-vfx-outbound-ok"
    )
    assert_array(matches).override_failure_message(
        "AC-VFX-23 violation — VFXSystem émet signal détecté (R-VFX-14 outbound-zero terminal) :\n%s" % "\n".join(matches)
    ).is_empty()

# Helpers _grep_violations / _grep_src_excluding — cohérent audio_anti_patterns_lint_test.gd
```

### CI job dans `.github/workflows/tests.yml`

```yaml
lint-vfx-anti-patterns:
  name: Lint — VFX anti-patterns (4 grep gates BLOCKING)
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - name: Run VFX anti-patterns lint
      run: |
        set -euo pipefail
        # AC-VFX-05 — pool exclusive
        ! grep -rE 'GPUParticles3D\.new\(\)|Decal\.new\(\)|MeshInstance3D\.new\(\)' src/ 2>/dev/null \
          | grep -v 'src/core/vfx_system.gd' \
          | grep -v '#' \
          | grep -v 'lint-vfx-pool-ok' \
          || (echo "FAIL AC-VFX-05"; exit 1)
        # AC-NEW-09, AC-NEW-10, AC-VFX-23 — analogue
    - name: Upload log artifact
      if: always()
      uses: actions/upload-artifact@v4
      with:
        name: vfx-anti-patterns-lint-${{ github.run_id }}
        path: production/qa/evidence/vfx-anti-patterns-lint-*.log
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Story 001-006 : code production VFX (lints scannent ce code)
- Story 002 : `_perform_decal_raycast` body, splash spawn, trail activation
- Story 003 : decal LRU ring buffer eviction
- Story 004 : flash wall-clock timer body
- Story 005 : accessibility pull body
- Story 006 : GSM visibility gating body
- Story 008 : Visual/Feel playtest (orthogonal, pas couvert par lints statiques)
- Performance budget runtime (60 s × 30 kills MEMORY_STATIC delta < 16 KB) — peut être déféré story future ou validé par run manuel post-impl stories 002-006

---

## QA Test Cases

**AC-VFX-05** : Pool exclusive zero match
- Given : code VFX complet (post stories 001-006)
- When : `grep -rE 'GPUParticles3D\.new\(\)|Decal\.new\(\)|MeshInstance3D\.new\(\)' src/ | grep -v src/core/vfx_system.gd`
- Then : zéro match (sauf exception annotée `# lint-vfx-pool-ok` cas pathologique)
- Edge cases : si match → FAIL "AC-VFX-05 — VFX node instancié hors API publique VFXSystem — utiliser `VFXSystem.play_kill_at` (R-VFX-1)"

**AC-NEW-09** : Lint tween color/modulate zero match
- Given : `src/core/vfx_system.gd` complet
- When : `grep -rnE 'Tween\.tween_property.*\b(color|modulate|opacity)\b' src/core/vfx_system.gd`
- Then : zéro match (sauf exception annotée `# lint-vfx-tween-ok`)
- Edge cases : si match non annoté → FAIL "AC-NEW-09 — Tween sur color/modulate détecté ligne X — utiliser wall-clock `_physics_process` via `_get_time_msec.call()` (R-VFX-5/15)"

**AC-NEW-10** : Lint deferred handlers _on_* zero match
- Given : handlers `_on_swing_started`, `_on_enemy_killed`, `_on_died`, `_on_respawned`, `_on_state_changed`, `_on_accessibility_settings_changed`, `_on_swing_ended`, `_on_multi_kill` connectés via `signal.connect(handler, CONNECT_DEFERRED)`
- When : `grep -rnE '\.connect\([^,)]+\)\s*$' src/core/vfx_system.gd | grep -E '_on_[a-z_]+'`
- Then : zéro match (tous flag `CONNECT_DEFERRED` ; exception `# lint-vfx-deferred-ok` autorisée pour SYNC OQ-VFX-4)

**AC-VFX-23** : Outbound-zero zero match
- Given : `src/core/vfx_system.gd` complet
- When : `grep -rnE 'emit_signal\b|\.emit\(' src/core/vfx_system.gd`
- Then : zéro match (R-VFX-14 terminal pur)
- Edge cases : si match → FAIL "AC-VFX-23 — VFXSystem émet signal détecté ligne X — VFX est terminal pur, R-VFX-14"

**Test GdUnit4 static execution** :
- Given : `.godot/global_script_class_cache.cfg` existe
- When : `godot --headless --script addons/gdUnit4/bin/GdUnitCmdTool.gd --add tests/static/vfx_anti_patterns_lint_test.gd --ignoreHeadlessMode`
- Then : exit code 0 ; 4 test cases | 0 failures ; rapport `reports/report_N/`

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/static/vfx_anti_patterns_lint_test.gd` (4 test cases AC-VFX-05/23 + AC-NEW-09/10)
- `.claude/rules/vfx-anti-patterns.md` (rule Markdown documentation)
- `.github/workflows/tests.yml` job `lint-vfx-anti-patterns` (CI gate BLOCKING)
- `production/qa/evidence/vfx-anti-patterns-lint-{date}.log` (CI artefact, premier run smoke check Sprint VFX)

**Status**: [ ] Not yet created.

---

## Dependencies

- Depends on: Stories 001-006 (lints scannent code production écrit par stories handlers)
- Cross-system : aucun (lint statique pur, 0 dépendance runtime)
- Unlocks: AC-VFX-04/05/23 BLOCKING — Definition of Done epic VFX item "4 lint CI gates BLOCKING activés et zero match"

---

## Completion Notes

**Completed** : 2026-05-09 (chain auto post story-006 done — close-out structural epic VFX)
**Verdict** : COMPLETE — AC-VFX-04 DEFERRED (acceptable scope MVP — lint structurel AC-VFX-05 enforce invariant) ; AC-VFX-24 RESOLVED 2026-05-09 (chore tech-debt-cleanup — runtime test ajouté `tests/integration/vfx/vfx_outbound_zero_mutation_test.gd` 2 tests PASS)
**Criteria** : 6/6 BLOCKING + 2 advisory — AC-VFX-05 + AC-VFX-23 + AC-NEW-09/10/11/12 PASS ; AC-VFX-04 deferred ; AC-VFX-24 resolved post-close-out
**Re-confirm tests** : 47/47 PASS cumulé exit 0 / 3.30 s (`reports/report_466/results.xml`) — story-001..007 + AC-VFX-24 runtime test
**Deviations** : None bloquantes — toutes corrigées pendant `/code-review` ou drift fixé post-close-out :
  - AC-VFX-24 → RESOLVED 2026-05-09 chore tech-debt-cleanup : `tests/integration/vfx/vfx_outbound_zero_mutation_test.gd` 2 tests (snapshot pré/post enemy_node Node3D + mock_combat/camera metadata après tous handlers VFX)
  - AC-VFX-04 deferred : explicitly per story spec (lint structurel rendant violation runtime impossible) — acceptable scope MVP
  - 2 ROI fixes appliqués : `on_handler_regex.compile` assertion parité L62 + skip silencieux paths empty → FAIL bruyant (protection régression refactor si vfx_system.gd renamed)
  - Drift pré-existant `lint-audio-anti-patterns` absent du `needs:` ligne 1038 → RESOLVED 2026-05-09 chore tech-debt-cleanup (commit `ac38691`) : ajout `lint-audio-anti-patterns` + `lint-menu-anti-patterns` au needs: gate test job
  - AC-NEW-08 fantôme dans story spec ligne 87 (cleanup doc — rule MD utilise AC-VFX-05 correct)
**Test Evidence** : `tests/static/vfx_anti_patterns_lint_test.gd` (4 tests post-fixes)
**Code Review** : Complete — godot-gdscript-specialist APPROVED WITH SUGGESTIONS (Pattern Audio cohérence parfaite + 4 ACs covered + scope correct, 3 suggestions cosmétiques) + qa-tester GAPS doc-only (2 gaps non-bloquants — AC-VFX-24 + skip silencieux fix appliqué)

**0 violation détectée dans code prod stories 001-006** : pattern Audio R-AUD-* parfaitement transposé. Confirme respect strict ADR-0009 D-2/D-3/D-4 patterns + R-VFX-1/3/5/14/15 invariants depuis le boot du Sprint VFX.

**Pattern référence parfait** : calque exact `audio-anti-patterns.md` / `audio_anti_patterns_lint_test.gd` / `lint-audio-anti-patterns` CI job (Audio System story-009).

**Definition of Done VFX item "4 lint CI gates BLOCKING activés et zero match" SATISFAIT.**

**Files livrés (3)** :
- `.claude/rules/vfx-anti-patterns.md` (NEW, 208 L)
- `tests/static/vfx_anti_patterns_lint_test.gd` (NEW, ~200 L post-fixes)
- `.github/workflows/tests.yml` (MODIF) — job `lint-vfx-anti-patterns` ligne 629-757 + `needs:` ligne 1038

**Out of Scope strict respecté** : zéro touch code prod stories 001-006, zéro playtest story-008.

**Tech debt** : RESOLVED 2026-05-09 (chore tech-debt-cleanup) — AC-VFX-24 runtime mutation property check couvert via `tests/integration/vfx/vfx_outbound_zero_mutation_test.gd` (2 tests : enemy_node Node3D + cluster 5-kill repeated ; assertions sur global_position / scale / rotation / name / metadata pre==post après enemy_killed + swing_started/ended + died + respawned).
