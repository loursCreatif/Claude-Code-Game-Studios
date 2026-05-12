# Test Flakiness Register — Combat Integration time_scale Audit
**Date** : 2026-05-11
**Scope** : 4 tests à risque latent cross-suite pollution `Engine.time_scale`
**Branche** : `chore/story-014-tech-debt-cleanup`
**CI scannée** : 50 derniers runs (`gh run list --limit 50`)
**Méthode** : lecture code source + recherche `FAILED` dans `--log-failed` sur tous runs failure

---

## Résumé exécutif

Aucun des 4 tests n'a flaké en CI sur les 50 derniers runs. Conformément à la
politique projet (pas de hardening préventif sans signal flake observé), **aucune
modification de code n'est appliquée**. Le registre documente le risque résiduel
pour référence future.

---

## Tableau de risque

| Test | Lignes assert time_scale | Tolerance | Pattern reset existant | Signal CI flaké | Risk Score (0–10) | Recommandation |
|---|---|---|---|---|---|---|
| `mutual_kill_death_pending_test.gd` | L131, L188 | ±0.0001 | `after_test()` ENGINE reset | Non | **3** | Surveiller — `after_test` couvre, mais pas de `before_test` guard |
| `integration_soak_test.gd` | L100–104 | ±0.0001 | `after_test()` ENGINE reset | Non | **3** | Surveiller — même gap `before_test` |
| `multi_hit_distance_sort_test.gd` | L149–150, L252–253 | `is_equal_approx` ±0.001 | `var prev` local + cleanup manuel L155–156 | Non | **5** | Risque modéré — cleanup `Engine.time_scale = initial_time_scale` dépend de l'exécution sans crash mid-test |
| `single_hit_kill_dedup_test.gd` | L252–253 | `is_equal_approx` ±0.001 | `var prev` local + cleanup manuel L256–257 | Non | **5** | Risque modéré — même pattern que `multi_hit_distance_sort` |

---

## Analyse détaillée par test

### 1. `mutual_kill_death_pending_test.gd`

**Asserts time_scale** :
- L131 : `assert_float(Engine.time_scale).is_between(1.0 - 0.0001, 1.0 + 0.0001)`
  — AC-CMB-20, test `test_combat_died_swinging_without_collider_clean_drain`
- L188 : `assert_float(Engine.time_scale).is_between(1.0 - TIME_SCALE_TOLERANCE, 1.0 + TIME_SCALE_TOLERANCE)`
  — test `test_combat_died_swinging_with_active_slow_mo_restores_time_scale_at_drain`

**Pattern reset** : `after_test()` ligne 35–37 — reset `Engine.time_scale = 1.0` après
chaque test. Couvre la pollution vers les tests suivants. Gap : aucun `before_test()` pour
absorber une pollution entrante d'une suite précédente en cas de crash mid-`after_test`.

**Analyse** : risque faible. Le test `_slow_mo_restores` force manuellement
`Engine.time_scale = CombatSystem.SLOW_MO_SCALE` avant le test, puis l'assert vérifie
que le drain le restaure. Si une suite précédente laisse `time_scale != 1.0`, le setup
explicite du test le force lui-même — auto-protection partielle. Le test
`_without_collider_clean_drain` n'override pas `time_scale` avant l'assert : dépend que
`CombatSystem._drain_combat()` le restaure, pas d'une valeur d'entrée garantie. Risque
réel seulement si `time_scale` arrive pollué ET que le drain ne le détecte pas.

---

### 2. `integration_soak_test.gd`

**Asserts time_scale** :
- L100–104 : `assert_float(Engine.time_scale).is_between(1.0 - 0.0001, 1.0 + 0.0001)`
  — AC-CMB-37 (b), dans la boucle SOAK_CYCLES (200 itérations),
  `test_combat_soak_cycles_reset_invariants_after_each_swing`

**Pattern reset** : `after_test()` ligne 63–65 — reset `Engine.time_scale = 1.0`.
L'assert (b) vérifie que slow-mo n'est PAS déclenché (pas de kill réel en soak pur) —
donc si `time_scale` arrive à 0.5 d'une suite précédente, l'assert (b) cycle 0 échoue
immédiatement.

**Analyse** : risque identique à `mutual_kill`. Le soak ne déclenche pas de slow-mo (pas
de `_resolve_kills` avec kill réel), donc l'assert vérifie l'invariant "pas de mutation
parasite". Pollution entrante est le seul vecteur de flake. `after_test` présent couvre
la sortie — la lacune `before_test` est réelle mais jamais activée en 50 runs CI.

---

### 3. `multi_hit_distance_sort_test.gd`

**Asserts time_scale** :
- L149–150 : `assert_float(Engine.time_scale).is_equal_approx(CombatSystem.SLOW_MO_SCALE, 0.001)`
  — AC-CMB-25, test `test_combat_multi_kill_two_enemies_slow_mo_idempotent`
- Cleanup L155–156 : `Engine.time_scale = initial_time_scale` + `combat._slow_mo_active = false`

**Pattern reset** : pas de `before_test` / `after_test`. Pattern `var prev` local :
`var initial_time_scale: float = Engine.time_scale` capturé avant act, restauré
manuellement après assert. Vecteur flake : si un test précédent dans la **même suite**
crash avant son propre cleanup, `initial_time_scale` capture une valeur polluée.
L'assert `is_equal_approx(SLOW_MO_SCALE, 0.001)` vérifie la valeur absolue — résistant
à la pollution entrante pour cet assert spécifique. Mais si `initial_time_scale` est
déjà à `SLOW_MO_SCALE` au moment de la capture, la restauration L155 laisse `time_scale`
à 0.5 pour les tests suivants.

**Risque modéré** : le cleanup manuel est fragile en cas d'exception non rattrapée mid-test
par GdUnit4 (le restore L155–156 ne s'exécute pas). Dans ce projet (GdUnit4 + headless),
les exceptions GDScript provoquent `SCRIPT ERROR` mais continuent — cleanup probablement
exécuté. Tolérance `0.001` plus large que le pattern `0.0001` des autres suites.

---

### 4. `single_hit_kill_dedup_test.gd`

**Asserts time_scale** :
- L252–253 : `assert_float(Engine.time_scale).is_equal_approx(CombatSystem.SLOW_MO_SCALE, 0.001)`
  — test `test_combat_first_kill_triggers_slow_mo`
- Cleanup L256–257 : `Engine.time_scale = initial_time_scale` + `combat._slow_mo_active = false`

**Pattern reset** : identique à `multi_hit_distance_sort`. Même analyse, même score 5/10.

---

## Analyse CI — Signal observé

Scannés : 50 runs (2026-05-10 à 2026-05-02). Fails réels observés sur d'autres suites :
- `wall_jump_test`, `jump_coyote_test`, `level_state_machine_test`, `input/was_pressed_this_tick_test`,
  `no_alloc_play_2d_test`, `main_menu_boot_test`, `death_respawn_lifecycle_test`

**Zéro fail observé** sur les 4 tests du registre.

Le fail `death_respawn_lifecycle_test` (run `34672ff`, 2026-05-10) était la cause
du commit `4228597` (pattern `before_test` defense-in-depth). Les 4 tests du présent
registre étaient **verts dans ce même run**.

---

## Sources de pollution time_scale connues

Suites qui mutent `Engine.time_scale` (cross-suite risk si elles crashent avant cleanup) :

| Suite | Ligne | Valeur | Pattern reset |
|---|---|---|---|
| `formula4_crossfade_midpoint_test.gd` | ~L203 | 0.3 | `after_test()` |
| `enemy_grunt_death_tween_test.gd` | ~L79 | 0.3 | `var prev` |
| `slow_mo_wall_clock_test.gd` | ~L200 | 0.5 | `after_test()` |
| `multi_hit_distance_sort_test.gd` | L127 | SLOW_MO_SCALE | `var prev` + cleanup manuel |
| `single_hit_kill_dedup_test.gd` | L241 | SLOW_MO_SCALE | `var prev` + cleanup manuel |

---

## Décision

**Pas de modification code** — aucun signal CI observé. Risk scores 3 et 5 sont
en-dessous du seuil d'action (politique projet : signal reproductible requis).

**Trigger de réévaluation** : si l'un des 4 tests flappe en CI sur branche future,
appliquer immédiatement le pattern `before_test() Engine.time_scale = 1.0` sur le
test concerné (modèle `death_respawn_lifecycle_test` commit `4228597`).

---

*Généré par qa-lead — audit autonome 2026-05-11*
