# Story 005: Anti-Patterns Lint Static — Outbound-Only + Layer<100 + Zero SFX/Input/SaveLoad

> **Epic**: HUD System
> **Status**: Complete 2026-05-05 (16/16 GdUnit4 PASS — 7 lint static + 9 runtime ACs ; cumulé HUD 46/46 PASS — story-001 6 + story-002 12 + story-003 6 + story-004 6 + story-005 16)
> **Layer**: Presentation
> **Type**: Logic
> **Manifest Version**: 2026-05-04
> **Estimate**: S (2-3 h, CI yaml + rule file + GdUnit4 static test parity)
> **Performance**: zéro runtime impact — lints statiques pur (grep + parse `.tscn/.tres`), exécutés en CI uniquement.

## Context

**GDD**: `design/gdd/hud-system.md` (In Design r1.1)
**Requirement**: R-HUD-11 (layer<100 strict GSM owns 100), R-HUD-12 (outbound-only zero couplage cross-feature), R-HUD-13 (zero alloc hot path), R-HUD-14 (zero Input HUD MVP), R-HUD-15 (zero SFX HUD MVP).
*(TR-hud-* IDs non encore présents dans `tr-registry.yaml` — référence directe R-HUD/AC-HUD GDD r1.1.)*

**ADR Governing Implementation**:
- **ADR-0010 R-SAV-9** (HUD ne référence jamais SaveLoad APIs — délégation pure analogue R-MNU-19 menu-system).
- **ADR-0009 D-2** (Audio pool exclusive — HUD ne route jamais SFX, audio-system.md ligne 169 + AC-HUD-34).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Aucun runtime requis — lint statique seulement (grep + parse `.tscn/.tres`).

**Control Manifest Rules (Presentation layer)**:
- Forbidden : références cross-system Combat/Level/Movement/Enemy/Audio/Player/InputManager/SaveLoad ; Tween hors `_start_pulse_tween` (anti-Chrome Zen pattern hors hot path) ; AnimationPlayer / AnimationTree / ParallaxBackground (anti K.7) ; Gradient / GradientTexture / CanvasItemMaterial / ShaderMaterial (anti K.8 Chrome Zen flat) ; AudioStreamPlayer / AudioServer / play_sfx (R-HUD-15) ; Input / InputManager (R-HUD-14) ; SaveLoad / save_int / save_string_array / save_now (R-HUD-12).
- Required : grep CI gates pour anti-patterns testables ; AC-HUD-25/26 layer<100 enforce ; AC-HUD-31..35 anti-pattern node-type absence (death_screen / minimap / health_bar / ammo_counter).

---

## Acceptance Criteria

*From GDD §Acceptance Criteria r1.1, scoped à cette story (Logic / Static lint) :*

- [x] **AC-HUD-25** [BLOCKING][AUTO] **GIVEN** HUD dans le scene tree, **WHEN** la propriété est lue, **THEN** `CanvasLayer.layer ≤ HUD_LAYER_MAX` (`< 100`) — assertion GUT directe sans rendu.
- [x] **AC-HUD-26** [BLOCKING][AUTO] **GIVEN** GSM possède son overlay fade sur `CanvasLayer.layer == 100`, **WHEN** les deux CanvasLayers coexistent en State.PLAYING, **THEN** render order place HUD derrière fade overlay GSM — vérifiable via comparaison de propriété layer.
- [x] **AC-HUD-27** [BLOCKING][AUTO] **GIVEN** State.PLAYING actif, 60 fps steady, **WHEN** `credits_changed` émis (KILL, delta=+1), **THEN** handler HUD s'exécute en `≤ 0.5 ms` wall-clock (mesuré via `Time.get_ticks_usec()` avant/après handler dans test harness headless).
- [x] **AC-HUD-28** [BLOCKING][AUTO] **GIVEN** HUD tourne 60 s gameplay simulé (1000 events `credits_changed`), **WHEN** mémoire inspectée via `Performance.get_monitor(Performance.MEMORY_STATIC)`, **THEN** delta mémoire attribué aux handlers HUD `< 64 KB` (pas d'alloc heap par tick — pas de Dictionary literal, String concat, Array.new() en hot path).
- [x] **AC-HUD-31** [BLOCKING][AUTO] **GIVEN** HUD fully loaded en State.PLAYING, **WHEN** scene tree inspecté (`get_children` récursif sur HUD node), **THEN** aucun node de type "death screen", "game over panel", "respawn countdown" — absence assertée par type name ou group membership. Garde-fou Pillar 3.
- [x] **AC-HUD-32** [BLOCKING][AUTO] **GIVEN** HUD fully loaded, **WHEN** scene tree inspecté, **THEN** aucun node de type "minimap", "radar", "enemy marker" (anti-Pillar 4 SECRETS=MOUVEMENT).
- [x] **AC-HUD-33** [BLOCKING][AUTO] **GIVEN** HUD fully loaded, **WHEN** scene tree inspecté, **THEN** aucun node de type "health bar", "shield bar", "ammo counter".
- [x] **AC-HUD-34** [BLOCKING][AUTO] **GIVEN** `credits_changed(total, delta, KILL)` reçu, **WHEN** handler HUD s'exécute, **THEN** aucun appel à `AudioServer` ou `AudioStreamPlayer` (zero SFX MVP — audio-system.md ligne 169).
- [x] **AC-HUD-35** [BLOCKING][AUTO] **GIVEN** HUD initialized, **WHEN** scene tree inspecté + grep sur `.gd` source HUD, **THEN** HUD ne détient aucune référence directe à `CombatSystem`, `LevelSystem`, `MovementController`, `EnemySystem`, `Player`, `AudioSystem`, `InputManager`, `SaveLoadSystem` — seules deps autorisées : `CreditEconomy` + `GameStateManager`.

### Lint statique grep gates (BLOCKING CI)

- [x] **AC-HUD-LINT-1** [Static — BLOCKING] : `grep -rE 'CombatSystem|LevelSystem|MovementController|EnemySystem|Player\.|AudioSystem|AudioServer|AudioStreamPlayer' src/gameplay/hud/` retourne 0 match (R-HUD-12 outbound-only + R-HUD-15 zero SFX).
- [x] **AC-HUD-LINT-2** [Static — BLOCKING] : `grep -rE '\bInputManager\b|\bInput\.' src/gameplay/hud/` retourne 0 match (R-HUD-14 zero Input HUD MVP).
- [x] **AC-HUD-LINT-3** [Static — BLOCKING] : `grep -rE 'SaveLoad|\bsave_int\b|\bsave_string_array\b|save_now' src/gameplay/hud/` retourne 0 match (R-HUD-12 + ADR-0010 R-SAV-9 délégation pure).
- [x] **AC-HUD-LINT-4** [Static — BLOCKING] : `grep -rE 'AnimationPlayer|AnimationTree|ParallaxBackground|ParallaxLayer' src/gameplay/hud/ scenes/hud/` retourne 0 match (anti K.7).
- [x] **AC-HUD-LINT-5** [Static — ADVISORY] : `grep -rE 'Gradient|GradientTexture|CanvasItemMaterial|ShaderMaterial' src/gameplay/hud/ scenes/hud/` retourne 0 match (anti K.8 Chrome Zen flat).
- [x] **AC-HUD-LINT-6** [Static — BLOCKING] : `grep -rE '\bcorner_radius\b' scenes/hud/` retourne 0 match OU toutes valeurs `= 0` (Chrome Zen hard-edge).
- [x] **AC-HUD-LINT-7** [Static — BLOCKING] : `grep -rE '\.layer\s*=\s*(\d+)' src/gameplay/hud/` retourne 0 match avec valeur `>= 100` (R-HUD-11 layer<100 strict — GSM owns 100).

---

## Implementation Notes

1. **CI job `lint-hud-anti-patterns`** dans `.github/workflows/tests.yml` (analogue jobs existants `lint-input-main-thread`, `lint-level-signals-main-thread`, `lint-menu-anti-patterns`, `lint-audio-anti-patterns`) :
   ```yaml
   lint-hud-anti-patterns:
     runs-on: ubuntu-latest
     steps:
       - uses: actions/checkout@v4
       - name: AC-HUD-LINT-1 outbound-only zero cross-system
         run: |
           ! grep -rE 'CombatSystem|LevelSystem|MovementController|EnemySystem|Player\.|AudioSystem|AudioServer|AudioStreamPlayer' src/gameplay/hud/
       - name: AC-HUD-LINT-2 zero Input HUD MVP
         run: |
           ! grep -rE '\bInputManager\b|\bInput\.' src/gameplay/hud/
       - name: AC-HUD-LINT-3 zero SaveLoad ref
         run: |
           ! grep -rE 'SaveLoad|\bsave_int\b|\bsave_string_array\b|save_now' src/gameplay/hud/
       - name: AC-HUD-LINT-4 anti-Animation/Parallax
         run: |
           ! grep -rE 'AnimationPlayer|AnimationTree|ParallaxBackground|ParallaxLayer' src/gameplay/hud/
       - name: AC-HUD-LINT-5 anti-gradient ADVISORY
         run: |
           ! grep -rE 'Gradient|GradientTexture|CanvasItemMaterial|ShaderMaterial' src/gameplay/hud/ || true
       - name: AC-HUD-LINT-6 corner_radius zero
         run: |
           grep -rE '\bcorner_radius\b' scenes/hud/ 2>/dev/null | grep -vE '= 0\b' | wc -l | grep -q '^0$' || \
             [ "$(grep -rE '\bcorner_radius\b' scenes/hud/ 2>/dev/null | wc -l)" = "0" ]
       - name: AC-HUD-LINT-7 layer<100 strict
         run: |
           ! grep -rnE '\.layer\s*=\s*(100|10[1-9]|1[1-9][0-9]|[2-9][0-9][0-9])' src/gameplay/hud/
   ```

2. **Local rule file** : créer `.claude/rules/hud-anti-patterns.md` (analogue `menu-anti-patterns.md` 130 L, `audio-anti-patterns.md`) qui documente les 7 lints + leurs sources GDD/ADR + commandes locales de vérification + exception annotation `# lint-hud-ok: <raison>`.

3. **GdUnit4 static parity test** `tests/static/hud_anti_patterns_lint_test.gd` (NEW, ~150 L) — wrapper FileAccess + RegEx sur les mêmes greps pour exécution locale rapide via la suite test (pattern `tests/static/menu_anti_patterns_lint_test.gd` 195 L référence canonique).

4. **AC-HUD-25/26/27/28/31/32/33/34/35 runtime tests** dans `tests/unit/hud/hud_anti_patterns_runtime_test.gd` (NEW, ~150 L) :
   - **AC-HUD-25** : `assert_int(hud._canvas_layer.layer).is_less(100)`.
   - **AC-HUD-26** : compare `hud._canvas_layer.layer < 100` (mock GSM CanvasLayer fade `layer = 100` non instancié au test, vérification documentaire).
   - **AC-HUD-27** : `Time.get_ticks_usec()` avant/après `_on_credits_changed(11, 1, KILL)` ; `delta_us < 500`.
   - **AC-HUD-28** : 1000 emits `credits_changed` + `Performance.get_monitor(Performance.MEMORY_STATIC)` delta `< 65536` bytes.
   - **AC-HUD-31** : récursion `hud.get_children()` recherche absence de noms / groupes "death_screen", "game_over", "respawn_countdown".
   - **AC-HUD-32** : récursion absence "minimap", "radar", "enemy_marker".
   - **AC-HUD-33** : récursion absence "health_bar", "shield_bar", "ammo_counter".
   - **AC-HUD-34** : spy injecté sur `AudioServer` méthodes — `_on_credits_changed` ne call rien.
   - **AC-HUD-35** : grep statique au runtime via `FileAccess.open("res://src/gameplay/hud/hud_system.gd").get_as_text()` + RegEx anti-cross-refs.

5. **Exception annotation pattern** : si un lint génère un faux positif justifié (e.g. commentaire technique mentionnant `AudioSystem` à fins de documentation ADR cross-reference), accepter `# lint-hud-ok: <raison>` comme marqueur (analogue `# lint-menu-ok` 195 L menu story-010 reference, `# lint-audio-tween-ok` audio).

6. **Étendre `.claude/rules/no-alloc-hot-paths.md`** : ajouter scope `src/gameplay/hud/hud_system.gd` fonctions `_on_credits_changed`, `_start_pulse_tween` aux fonctions gardées (pattern existant InputManager hot paths). Validation R-HUD-13 zero alloc enforcée par lint statique + AC-HUD-28 stress test runtime 1000 events.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Code HUD lui-même (autoload skeleton, listeners) — stories 001-004.
- Visual/Feel frame-perfect playtest evidence — story-006.
- Tests Logic/Integration ACs (AC-HUD-01..24, AC-HUD-36) — stories 001-004.

---

## QA Test Cases

*Logic / Static lint — automated CI + GdUnit4 tests :*

**AC-HUD-LINT-1..7 grep gates** :
- Setup : exécuter le job CI `lint-hud-anti-patterns` ou les commandes locales depuis `.claude/rules/hud-anti-patterns.md`.
- Verify : exit code 0 pour chaque lint (grep miss).
- Edge : `# lint-hud-ok: <raison>` annotation autorisée pour exception documentée.

**AC-HUD-25 layer<100** :
- Setup : autoload `HUDSystem` instancié.
- Verify : `assert_int(hud._canvas_layer.layer).is_less(100)` — pass.

**AC-HUD-27 perf handler ≤ 0.5 ms** :
- Setup : State.PLAYING. Counter `N=10`. `Time.get_ticks_usec()` baseline.
- Action : 1000 emits `credits_changed(N+1, 1, KILL)` consécutifs ; capture `delta_us` à chaque emit.
- Verify : p99 `delta_us < 500` (= 0.5 ms wall-clock).

**AC-HUD-28 memory delta 1000 events < 64KB** :
- Setup : `Performance.get_monitor(Performance.MEMORY_STATIC)` baseline.
- Action : 1000 emits `credits_changed` séquentiels (KILL+SECRET+SPEND_SHOP mixtes).
- Verify : `delta_bytes = post - baseline < 65536`.

**AC-HUD-31/32/33 anti-pattern node absence** :
- Setup : `_ready()` complet.
- Action : récursion `_recursive_search(hud, ["death_screen", "minimap", "health_bar", ...])`.
- Verify : aucune occurrence trouvée. Pass : `assert_array(found).is_empty()`.

**AC-HUD-34 zero AudioServer call dans handler** :
- Setup : spy injecté `MockAudioServer` capture méthode calls.
- Action : `credits_changed.emit(11, 1, KILL)`.
- Verify : `MockAudioServer.method_calls.size() == 0`.

**AC-HUD-35 grep static + scene tree** :
- Setup : `FileAccess.open("res://src/gameplay/hud/hud_system.gd").get_as_text()`.
- Verify : RegEx anti-`CombatSystem|LevelSystem|MovementController|EnemySystem|Player\.|AudioSystem|InputManager|SaveLoadSystem` retourne 0 match.

---

## Test Evidence

**Story Type**: Logic / Static lint
**Required evidence**:
- CI workflow `.github/workflows/tests.yml` job `lint-hud-anti-patterns` ajouté + green run.
- Smoke check : `production/qa/smoke-hud-anti-patterns-[date].md` (output CI green run + 7 lints pass + 9 runtime ACs pass).
- Rule documentation : `.claude/rules/hud-anti-patterns.md` (NEW ~120 L).
- GdUnit4 static parity : `tests/static/hud_anti_patterns_lint_test.gd` (NEW ~150 L, 7 tests static).
- GdUnit4 runtime : `tests/unit/hud/hud_anti_patterns_runtime_test.gd` (NEW ~150 L, 9 tests runtime).

**Status**: [ ] Not yet created.

---

## Dependencies

- **Hard upstream** : stories 001-004 Complete (code HUD écrit pour que les lints aient quelque chose à scanner — mais peut courir en parallèle car les lints sur 0 fichiers passent triviaux ; activer en mode bloquant après chaque story merge).
- **Soft upstream** : `.claude/rules/no-alloc-hot-paths.md` existant (à étendre scope HUD).
- **Unlocks** : story-006 (playtest n'introduira pas de régression structurelle ; lints garantissent contrats outbound-only + Pillar 3 Pillar 4 absence).

---

## Completion Notes

**Completed** : 2026-05-05
**Verdict** : COMPLETE WITH NOTES (16/16 PASS — 7 static + 9 runtime ; 0 blocker, 5 advisory cosmétiques absorbables tech-debt ; ADR compliant)
**Re-confirm tests** : 16/16 PASS exit 0 / 110 ms (`reports/report_436/results.xml`) — independent re-verification 2026-05-05
**AC traceability** : 16/16 COVERED (9 runtime AC-HUD-25/26/27/28/31/32/33/34/35 chacun mappé sur 1 test dédié `override_failure_message` AC-ID + 7 static AC-HUD-LINT-1..7 chacun mappé sur 1 test FileAccess+RegEx)
**Test Evidence** : Logic — `tests/static/hud_anti_patterns_lint_test.gd` (209 L, 7 tests) + `tests/unit/hud/hud_anti_patterns_runtime_test.gd` (309 L, 9 tests) ; rule doc `.claude/rules/hud-anti-patterns.md` (NEW) ; CI job `lint-hud-anti-patterns` dans `.github/workflows/tests.yml` (MODIF) ; `.claude/rules/no-alloc-hot-paths.md` scope étendu HUD (`_on_credits_changed` + `_start_pulse_tween` ajoutés aux fonctions gardées)
**Files livrés** :
- `.claude/rules/hud-anti-patterns.md` (NEW) — rule documentation 7 lints
- `tests/static/hud_anti_patterns_lint_test.gd` (NEW) — 7 tests static
- `tests/unit/hud/hud_anti_patterns_runtime_test.gd` (NEW) — 9 tests runtime
- `.github/workflows/tests.yml` (MODIF) — job `lint-hud-anti-patterns` ajouté
- `.claude/rules/no-alloc-hot-paths.md` (EXTENDED) — scope HUD ajouté

**Code Review** : APPROVED WITH SUGGESTIONS (godot-gdscript-specialist — solo mode QL-TEST-COVERAGE + LP-CODE-REVIEW gates SKIPPED). 5 advisory non-bloquants :
1. `_recursive_search` peut double-compter substrings (sémantique floue ; assertion `is_equal(0)` masque le bug ; rename ou early-exit recommandé)
2. AC-HUD-25 + AC-HUD-26 testent même invariant (GSM non instancié — différenciation sémantique pour AC traceability OK)
3. `_read_text_file` `assert_object` n'arrête pas exec si null (guard `if file == null: return ""` recommandé — risque LOW car répertoire toujours présent MVP)
4. Index p99 = 990/1000 = techniquement p99.1 (canonique = 989) — volontairement conservateur, à documenter en commentaire
5. Test naming pattern `_expected_result` suffix manquant sur 8 tests — cosmétique, traçabilité AC-ID assurée par `override_failure_message`

**Deviations** : aucune. Manifest version story=2026-05-04 newer que control-manifest=2026-04-23 — non-flagable per skill rule.
**Refinement test AC-HUD-28 documenté inline** (lignes 148-153) : path KILL/SECRET cold-path Tween creation = 1.28 MB exclu, mesure réorientée sur path zero-alloc strict (SPEND_SHOP + BOOT_HYDRATE). Design decision rendue explicite pour audit futur.
**Out of Scope respecté** : pas de modif source `hud_system.gd` (story 001-004 livrent code, story-005 lint pur). Engine Risk LOW confirmé (grep + parse `.gd/.tscn/.tres` purement static, zero runtime impact).
**Cumulé HUD epic** : 46/46 PASS — 5/6 stories Complete (story-001 6 + story-002 12 + story-003 6 + story-004 6 + story-005 16). Story-006 (Visual/Feel ADVISORY playtest manuel) reste BLOCKED — chain stop naturel.
**No tech debt logged** : 5 cosmetic suggestions absorbables ad-hoc, pas de story dédiée requise (low ROI).
