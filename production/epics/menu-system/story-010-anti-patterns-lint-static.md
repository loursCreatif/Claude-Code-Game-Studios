# Story 010: Anti-Patterns Lint Static — 8 Grep + Anti-Deps + SaveLoad Zero-Ref

> **Epic**: Menu System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: Config/Data
> **Manifest Version**: 2026-04-23
> **Estimate**: S (2-3 h, CI yaml + rule file)
> **Performance**: zéro runtime impact — lints statiques pur (grep + parse `.tscn/.tres`), exécutés en CI uniquement. Pas de code menu écrit dans cette story.

## Context

**GDD**: `design/gdd/menu-system.md`
**Requirement**: `R-MNU-15` (zero tween), `R-MNU-16` (zero confirm), `R-MNU-18` (anti-deps strictes), `R-MNU-19` (save-on-quit délégation pure)

**ADR Governing Implementation**: ADR-0007 D-4 (GSM seul autorité pause + time_scale + get_tree().paused) ; ADR-0010 R-SAV-9 (Menu ne référence jamais SaveLoad APIs).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Aucun runtime requis — lint statique seulement (grep + parse `.tscn/.tres`).

**Control Manifest Rules (Presentation layer)**:
- Forbidden : ParallaxBackground/AnimationPlayer/AnimationTree dans menus ; gradient material ; SFX dans menus ; `Engine.time_scale` mutation depuis Menu ; `get_tree().paused` mutation hors GSM.
- Required : grep CI gates pour anti-patterns testables (Groupe K).

---

## Acceptance Criteria

*Tous ACs sont des grep statiques exécutables localement OU en CI :*

- [ ] **AC-MNU-36** [Static — ADVISORY] : `grep -r 'Tween\|create_tween\|tween_property\|InterpolateValue' src/gameplay/menu/` retourne 0 match (R-MNU-15 + K.7 anti-tween absolu).
- [ ] **AC-MNU-44** [Static — BLOCKING] : `grep -rE "AudioStreamPlayer|play_sfx|audio_play" scenes/menus/ src/gameplay/menu/ scenes/etages/` retourne 0 match dans `scenes/menus/` + `src/gameplay/menu/` ; pour `scenes/etages/`, AudioStreamPlayer trouvés appartiennent à des nœuds non-Menu (parse `.tscn` + filtre).
- [ ] **AC-MNU-45** [Static — BLOCKING] : `grep -r "AcceptDialog\|ConfirmationDialog\|PopupPanel\|PopupMenu" scenes/menus/ src/gameplay/menu/` retourne 0 match (R-MNU-16 zero confirm).
- [ ] **AC-MNU-46** [Static — BLOCKING] : `grep -r "corner_radius" scenes/menus/` retourne 0 match OU toutes valeurs `= 0` (Chrome Zen hard-edge K.5).
- [ ] **AC-MNU-47** [Static — ADVISORY] : `grep -r "ParallaxBackground\|ParallaxLayer\|AnimationPlayer\|AnimationTree" scenes/menus/` retourne 0 match.
- [ ] **AC-MNU-48** [Static — ADVISORY] : `grep -r "Gradient\|GradientTexture\|CanvasItemMaterial\|ShaderMaterial" src/gameplay/menu/` retourne 0 match.
- [ ] **AC-MNU-49** [Static — BLOCKING] : `grep -r "Engine\.time_scale\|Engine.time_scale" src/gameplay/menu/` retourne 0 match (ADR-0007 D-4 GSM seul autorité).
- [ ] **AC-MNU-50** [Static — BLOCKING] : `grep -r "get_tree()\.paused\|SceneTree.*paused" src/gameplay/menu/` retourne 0 match (autorité unique GSM).
- [ ] **AC-MNU-57** [Static — BLOCKING] *(r2)* : `grep -rE "SaveLoad|\bsave_int\b|\bsave_string_array\b|save_now" src/gameplay/menu/` retourne 0 match (R-MNU-19 délégation pure).
- [ ] **AC-MNU-63** [Static — BLOCKING] *(r2)* : `grep -rE 'NOTIFICATION_WM_WINDOW_FOCUS|_notification\b.*_focus' src/gameplay/menu/` retourne 0 match (R-MNU-18 anti-dep).
- [ ] **AC-MNU-64** [Static — ADVISORY] *(r2)* : `grep -rE '\b(Tween|create_tween|tween_property|InterpolateValue|AnimationPlayer|AnimationTree)\b' src/gameplay/menu/` retourne 0 match (superset AC-MNU-36 + K.9 reduce-motion compliance par construction).
- [ ] **Anti-deps R-MNU-18** [Static — BLOCKING] : `grep -rE '\b(LevelSystem|CombatSystem|MovementController|CreditSystem|SecretSystem|UpgradeSystem)\b' src/gameplay/menu/` retourne 0 match.

---

## Implementation Notes

*Lints CI-gated — pas de code menu écrit dans cette story, uniquement vérification :*

1. **CI job `lint-menu-anti-patterns`** dans `.github/workflows/tests.yml` (analogue aux jobs existants `lint-input-main-thread`, `lint-level-signals-main-thread`, `lint-collision-layers`) :
   ```yaml
   lint-menu-anti-patterns:
     runs-on: ubuntu-latest
     steps:
       - uses: actions/checkout@v4
       - name: AC-MNU-36 + AC-MNU-64 anti-tween
         run: |
           ! grep -rE '\b(Tween|create_tween|tween_property|InterpolateValue|AnimationPlayer|AnimationTree)\b' src/gameplay/menu/
       - name: AC-MNU-44 anti-SFX scenes/menus + src
         run: |
           ! grep -rE "AudioStreamPlayer|play_sfx|audio_play" scenes/menus/ src/gameplay/menu/
       - name: AC-MNU-45 anti-confirm dialogs
         run: |
           ! grep -rE "AcceptDialog|ConfirmationDialog|PopupPanel|PopupMenu" scenes/menus/ src/gameplay/menu/
       - name: AC-MNU-46 corner_radius zero
         run: |
           grep -r "corner_radius" scenes/menus/ | grep -vE '= 0\b' | wc -l | grep -q '^0$'
       - name: AC-MNU-47 anti-Parallax/Animation
         run: |
           ! grep -rE "ParallaxBackground|ParallaxLayer|AnimationPlayer|AnimationTree" scenes/menus/
       - name: AC-MNU-48 anti-gradient
         run: |
           ! grep -rE "Gradient|GradientTexture|CanvasItemMaterial|ShaderMaterial" src/gameplay/menu/
       - name: AC-MNU-49 zero Engine.time_scale
         run: |
           ! grep -rE "Engine\.time_scale" src/gameplay/menu/
       - name: AC-MNU-50 zero get_tree().paused mutation
         run: |
           ! grep -rE "get_tree\(\)\.paused|SceneTree.*paused" src/gameplay/menu/
       - name: AC-MNU-57 zero SaveLoad ref
         run: |
           ! grep -rE "SaveLoad|\bsave_int\b|\bsave_string_array\b|save_now" src/gameplay/menu/
       - name: AC-MNU-63 zero focus notification handler
         run: |
           ! grep -rE 'NOTIFICATION_WM_WINDOW_FOCUS|_notification\b.*_focus' src/gameplay/menu/
       - name: R-MNU-18 anti-deps
         run: |
           ! grep -rE '\b(LevelSystem|CombatSystem|MovementController|CreditSystem|SecretSystem|UpgradeSystem)\b' src/gameplay/menu/
   ```
2. **Local rule file** : créer `.claude/rules/menu-anti-patterns.md` (analogue à `level-signals-main-thread-only.md`, `input-singleton-main-thread-only.md`) qui documente les 11 lints + leurs sources GDD/ADR + commandes locales de vérification.
3. **Exception comments** : si un lint génère un faux positif justifié (ex : commentaire technique mentionnant `AnimationPlayer` à des fins de documentation), accepter `# lint-menu-ok: <raison>` comme marqueur d'exception (analogue `# lint-emit-thread-ok` existant).
4. AC-MNU-44 portée étages : nécessite parse `.tscn` plus fin que grep brut. Helper Python ou GDScript qui :
   - Pour chaque `scenes/etages/etage_*.tscn`, identifie les `[node ...]` enfants directs/indirects de l'instance `pause_overlay.tscn`.
   - Si AudioStreamPlayer dans cette sous-arborescence → fail.
   - Si AudioStreamPlayer hors sous-arborescence (ex : ambient track étage) → ok.

---

## Out of Scope

- Stories 001-009 : code menu lui-même.
- Tests de comportement (Logic/Integration) — cette story ne vérifie que présence/absence statique des patterns.

---

## QA Test Cases

*Mode : Config/Data — smoke check via CI ou local script. Pas de test unit/integration.*

**AC-MNU-36** : zéro tween src/gameplay/menu
- Setup : exécuter le job CI `lint-menu-anti-patterns` step "AC-MNU-36 + AC-MNU-64 anti-tween".
- Verify : exit code 0 (grep miss).

**AC-MNU-44** : zéro SFX scenes + src
- Setup : exécuter step "AC-MNU-44 anti-SFX scenes/menus + src".
- Verify : exit code 0.
- Edge cases : `scenes/etages/` parse plus fin via helper script (cf. Implementation Notes #4).

**AC-MNU-45 à AC-MNU-50** : grep simples
- Setup : exécuter chaque step CI correspondant.
- Verify : exit code 0 pour chaque lint.

**AC-MNU-46** : corner_radius zero ou absent
- Setup : `grep -r "corner_radius" scenes/menus/ | grep -vE '= 0\b'`
- Verify : retour vide (toutes valeurs sont 0 ou absent).
- Pass condition : `wc -l == 0`.

**AC-MNU-57** : zéro SaveLoad
- Setup : exécuter step "AC-MNU-57 zero SaveLoad ref".
- Verify : exit code 0.
- Pass condition : Menu ne référence aucune API `SaveLoadSystem` (R-MNU-19 + R-SAV-9 délégation pure).

**AC-MNU-63** : zéro handler focus côté Menu
- Setup : step "AC-MNU-63 zero focus notification handler".
- Verify : exit code 0.

**AC-MNU-64** : superset anti-tween
- Setup : step "AC-MNU-36 + AC-MNU-64 anti-tween" (même commande, scope élargi).
- Verify : exit code 0.

**Anti-deps R-MNU-18** :
- Setup : step "R-MNU-18 anti-deps".
- Verify : exit code 0.
- Pass condition : zéro reference cross-system Level/Combat/Movement/Credit/Secret/Upgrade.

---

## Test Evidence

**Story Type**: Config/Data
**Required evidence**:
- CI workflow `.github/workflows/tests.yml` job `lint-menu-anti-patterns` ajouté + green run.
- Smoke check : `production/qa/smoke-menu-anti-patterns-[date].md` (output CI green run + 11 lints pass).
- Rule documentation : `.claude/rules/menu-anti-patterns.md`.

**Status**: [x] Created and passing — CI workflow `.github/workflows/tests.yml` job `lint-menu-anti-patterns` ajouté (11 lints) + rule file `.claude/rules/menu-anti-patterns.md` + smoke check `production/qa/smoke-menu-anti-patterns-2026-05-02.md` + GdUnit4 parity test `tests/static/menu_anti_patterns_lint_test.gd` (10/10 PASSED 127 ms `reports/report_122`). Suite menu complète régression-free **68/68 PASSED 1s 445ms** (`reports/report_123`).

---

## Dependencies

- Depends on : Stories 001-009 (code menu écrit pour que les lints aient quelque chose à scanner — mais peut courir en parallèle car les lints sur 0 fichiers passent triviaux ; activer en mode bloquant après chaque story merge).
- Unlocks : Story 011 (perf bench peut tourner avec confiance que le code respecte les contraintes structurelles), Story 013 (playtest n'introduira pas de régression).

---

## Completion Notes

**Completed** : 2026-05-02
**Criteria** : 11/11 PASS (AC-MNU-36/44/45/46/47/48/49/50/57/63/64 + R-MNU-18). Story-Type Config/Data — smoke check evidence requirement satisfied.
**Deviations** : 1 ADVISORY — `src/gameplay/menu/main_menu_controller.gd:47` exception marker `# lint-menu-ok: read-only sanity assert (AC-MNU-50 forbids mutation, not lecture)`. Rationale ADR-0007 D-4 cible mutation, pas lecture. Project-pattern conforme.
**Test Evidence** : Smoke check `production/qa/smoke-menu-anti-patterns-2026-05-02.md` + GdUnit4 static `tests/static/menu_anti_patterns_lint_test.gd` (10/10 PASSED 127 ms `reports/report_122`) + suite menu **68/68 PASSED 1s 445ms** (`reports/report_123`) régression-free.
**Code Review** : APPROVED (manual /code-review pass 2026-05-02 — Solo mode QL-TEST-COVERAGE + LP-CODE-REVIEW gates skipped).
**Files livrés** :
- `.github/workflows/tests.yml` (MODIFIED +120 L) — job `lint-menu-anti-patterns` après `lint-collision-layers`
- `.claude/rules/menu-anti-patterns.md` (NEW 130 L)
- `tests/static/menu_anti_patterns_lint_test.gd` (NEW 195 L, 10 tests static)
- `production/qa/smoke-menu-anti-patterns-2026-05-02.md` (NEW)
- `src/gameplay/menu/main_menu_controller.gd:47` (+1 marker)
