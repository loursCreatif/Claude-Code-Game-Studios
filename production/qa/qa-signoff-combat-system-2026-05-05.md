## QA Sign-Off Report: Epic Player Combat System (per-epic re-affirmation)

**Date**: 2026-05-05
**Branche**: chore/story-014-tech-debt-cleanup
**Commit milestone**: `bcca032` (`docs(epics/index): combat 18→20/22 — story-018 soak shippé + story-020 status sync`)
**Stage**: Pre-Production (Combat slice → eligible Pre-Release)
**Review mode**: Solo MVP
**QA Lead sign-off**: Solo (Claude assist 2026-05-05)
**Précédent**: `production/qa/qa-signoff-combat-system-2026-05-04.md` (APPROVED WITH CONDITIONS)
**Trigger**: `/team-qa sprint` per-epic — option B post-`smoke-check-2026-05-05` FAIL global infra (Combat scope isolé PASS)

---

### Contexte de la re-affirmation

`/smoke-check sprint` 2026-05-05 a retourné **FAIL global** dont la cause root est **infrastructure de test** (autoload reuse cross-suite GdUnit4 v5 quand 290+ tests dans une seule invocation cmdtool) — **pas une régression code Combat**. Combat suite **isolée** confirme 100% PASS. Cette sign-off applique la stratégie per-epic : valider l'Epic Combat en isolation pour débloquer son advancement Pre-Production → Pre-Release indépendamment du fix infra (tracké comme tech-debt séparé).

Trois mises à jour matérielles depuis 2026-05-04 :
1. **Story-021 fermée par migration** vers Epic VFX System (AC-CMB-42 résolu via VFX story-003 ; MAX_DECALS_PER_ROOM révisé 12 → 32 R-VFX-4 LRU ring buffer). Plus de blocage VFX GDD côté Combat.
2. **Cleanup infra** : 281 fichiers Mac Finder dupes purgés (zéro impact git).
3. **Re-confirmation Combat isolated** : 118 cases / 20 suites / 0 errors / 0 fails / 0 orphans / exit 0 / 1.5s (run `report_398/results.xml`).

---

### Smoke Check Result

**PASS WITH WARNINGS** (Combat scope) — re-affirmation périmètre par-epic.

| # | Warning | Impact | Tracking |
|---|---------|--------|----------|
| W-1 | Tier 1 hardware sign-off DEFERRED — stories 017+018 baselines Apple M4 INFORMATIONAL | Sign-off officiel CI infra requis avant gate Pre-Production → Production | Backlog CI infra dédié |
| W-2 | draw_calls full-stack gate DEFERRED — headless RenderingServer dummy retourne 0 | Gate strict ≤500 draw calls requis sur runner non-headless Tier 1 | Backlog CI infra dédié + story-018 (e) |
| W-3 | Save/Load smoke checks #6 #7 SKIP — SaveLoad Epic non démarré | Activer quand SaveLoad Epic démarre | Sprint SaveLoad futur |
| **W-4 (NEW)** | **Test infra cross-pollution autoload reuse — full-suite cmdtool unique fail (290+ tests)** | **NE bloque PAS Combat scope (isolé PASS) ; bloque advancement /smoke-check sprint global tant que pattern non corrigé** | **Tech-debt story dédiée requise — voir `production/qa/smoke-2026-05-05.md` recommandation A** |

Combat scope : **ZÉRO warning BLOCKING**. Build Combat stable. Sortie exit 0 sur run isolé 2026-05-05.

---

### Test Coverage Summary (re-affirmation)

| Story | Type | Auto Test | Manual QA | Result |
|-------|------|-----------|-----------|--------|
| 001 — Scene skeleton + structural invariants | Logic | `scene_skeleton_invariants_test.gd` | — | PASS |
| 002 — State machine + cooldown + active_tick lifecycle | Logic | `state_machine_lifecycle_test.gd` | — | PASS |
| 003 — Death/respawn lifecycle full reset | Logic | `death_respawn_lifecycle_test.gd` (6/6) | — | PASS |
| 004 — `attacked()` handler + buffer single-slot 80ms | Logic | `attacked_handler_buffer_test.gd` (9/9) | — | PASS |
| 005 — `_build_capsule_basis()` helper + 100-sample sphere | Logic | `build_capsule_basis_test.gd` (6/6) | — | PASS |
| 006 — ShapeCast3D node config + collision layers | Logic | `shapecast_collision_layers_test.gd` (4/4) | — | PASS |
| 007 — Sweep position + aim_forward + NaN guards | Logic | `sweep_position_aim_guards_test.gd` (8/8) | — | PASS |
| 008 — `_prev_position` per-tick + REACH constant | Logic | `prev_position_per_tick_test.gd` (7/7) | — | PASS |
| 009 — Anti-tunneling N=3 substeps + Jolt margin | Logic | `anti_tunneling_substeps_test.gd` (8/8) | — | PASS |
| 010 — Tick-0 overlap mitigation Gap 2 | Logic | `shapecast_overlap_origin_test.gd` empirical + `tick_0_overlap_mitigation_regression_test.gd` (2/2) | — | PASS |
| 011 — Single-hit kill + dedup `_hit_this_swing` | Logic | `single_hit_kill_dedup_test.gd` | — | PASS |
| 012 — Multi-hit + tri distance + MAX_KILLS + multi_kill | Logic | `multi_hit_distance_sort_test.gd` | — | PASS |
| 013 — Slow-mo wall-clock + Callable injection | Logic | `slow_mo_wall_clock_test.gd` (7/7) | — | PASS |
| 014 — Mutual kill Hybrid M1 Option C `_death_pending` | Integration | `mutual_kill_death_pending_test.gd` (4/4) | — | PASS |
| 015 — Mid-swing transitions + race Idle + pause spam | Integration | `mid_swing_transitions_test.gd` (3/3) | — | PASS |
| 016 — Invariants runtime `_validate_invariants()` smoke | Logic | `invariants_runtime_validation_test.gd` (5/5) | — | PASS |
| 017 — ShapeCast microbench p99 ≤5ms | Performance | `combat_shapecast_microbench_test.gd` (1/1, p99=0.005ms M4) | Tier 1 sign-off ADVISORY DEFERRED CI infra | PASS (×3320 sous seuil) |
| 018 — Integration soak frametime + memory + OBJECT_COUNT | Integration | `integration_soak_test.gd` (4/4, p99=0.014ms / mem ≤500KB / object Δ ≤+5) | (f) zero warnings + draw_calls full-stack DEFERRED | PASS (×1166 sous seuil) |
| 019 — Combat feel playtest protocol Visual/Feel | Visual/Feel ADVISORY | — | Panel ≥5 testeurs × 3 sessions Martin (~10h) | PENDING (protocole publié, recrutement pending) |
| 020 — Swoosh fade + multi-kill clac + ducking | Integration | `audio_multi_kill_ducking_test.gd` (11/11 MockAudioHandler) + `swoosh_fade_wall_clock_test.gd` | — | PASS |
| 021 — VFX decal cap pool LRU contract | Integration | **CLOSED — Migrated to Epic VFX System 2026-05-04** (AC-CMB-42 → AC-VFX-01/02/03/30) | — | **N/A — owned VFX** |
| 022 — Accessibility `reduce_motion` Combat impact | Logic | `accessibility_reduce_motion_test.gd` (8/8) | — | PASS |

**Re-confirmation 2026-05-05** : `godot --headless --script GdUnitCmdTool.gd --add tests/unit/combat --add tests/integration/combat --ignoreHeadlessMode` → **118 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans** | **PASSED** | exit 0 | 1s 543ms | report `reports/report_398/results.xml`.

---

### ACs Coverage Summary

**BLOCKING headless : ALL COVERED** (story-021 ex-blocker fermé via migration VFX).

| Groupe AC | Couverture |
|-----------|------------|
| AC-CMB-01→04 (State machine + cooldown + active_tick) | ✅ BLOCKING PASS |
| AC-CMB-05→09 (attacked + buffer + clear / capsule basis / shapecast layers) | ✅ BLOCKING PASS |
| AC-CMB-10→18 (sweep + aim_forward + prev_position + anti-tunneling + tick-0 + dedup + multi-hit) | ✅ BLOCKING PASS |
| AC-CMB-19→25 (slow-mo wall-clock + accessibility mults + Callable injection) | ✅ BLOCKING PASS |
| AC-CMB-26→30 (mutual kill Hybrid M1 + mid-swing transitions + invariants runtime) | ✅ BLOCKING PASS |
| AC-CMB-31→34 (Visual/Feel — kill mvmt vs static, slow-mo perception, Likert) | 🟡 ADVISORY PENDING (story-019 panel Martin) |
| AC-CMB-35a (microbench p99) | ✅ PASS — baseline INFORMATIONAL Apple M4 |
| AC-CMB-35b (integration soak frametime + soak global) | ✅ PASS — baseline INFORMATIONAL Apple M4 |
| AC-CMB-37 a/b/c/d/e (soak invariants + memory + objects) | ✅ BLOCKING PASS |
| AC-CMB-37 (f) zero warnings stderr | 🟡 ADVISORY DEFERRED instrumentation GdUnit4 |
| AC-CMB-42 (decal cap) | ✅ MIGRATED → Epic VFX System (AC-VFX-01/02/03/30) — Combat scope no longer blocks |
| AC-CMB-51 + AC-CMB-audio-01/02 (Audio System contract) | ✅ BLOCKING PASS (story-020 11/11) |
| AC-CMB-Accessibility (reduce_motion impacts) | ✅ BLOCKING PASS (story-022 8/8) |

---

### Bugs Found

| ID | Story | Severity | Status |
|----|-------|----------|--------|

**Aucun bug ouvert sur le périmètre Combat Epic.**

Note historique : pas de nouveau bug depuis 2026-05-04. Re-confirmation isolée 2026-05-05 confirme intégrité (118/118 PASS).

---

### Verdict: APPROVED WITH CONDITIONS (re-affirmé)

**Justification** :

- **Code Combat 100% couvert tests passants** : 20/22 stories implémentées + 1 migrée (021 → VFX) + 1 Visual/Feel pending panel (019). Combat isolated 118 cases exit 0 reconfirmé 2026-05-05.
- **Aucune régression** introduite par les commits récents (`907a25c` story-018 + `bcca032` index sync).
- **Smoke FAIL global = root cause infra** (autoload reuse cross-suite), zéro impact périmètre Combat (isolated PASS prouvé).
- **Lint statiques propres** : collision-layers + audio-anti-patterns + movement-emit-physics-only + no-alloc-hot-paths + input-main-thread.
- **Baselines performance Apple M4** : ×1166-3320 sous seuils — zéro risque frame budget intra-engine.
- **Story 021 ex-blocker** : fermé par migration VFX 2026-05-04. Combat scope ne bloque plus sur VFX GDD.

### Conditions (mises à jour vs 2026-05-04)

1. ~~**Story 021 BLOCKED**~~ → **RÉSOLU** par migration vers Epic VFX System (AC-CMB-42 → AC-VFX-01/02/03/30).
2. **Story 019 ADVISORY (Visual/Feel panel)** : panel ≥5 testeurs × 3 sessions Martin à exécuter avant gate feel design sign-off creative-director. Protocole publié (`production/qa/protocols/combat-feel-interview.md`). **Ne bloque pas advancement code Combat.**
3. **Tier 1 sign-off DEFERRED (W-1, W-2)** : stories 017+018 baselines Apple M4 INFORMATIONAL. Gate officielle draw_calls + hardware certification CI infra requise avant Production. Apple M4 plus puissant que Tier 1 minimum (i3-10100F + GTX 1050) → directionnel uniquement.
4. **Story-018 (f) zero warnings DEFERRED** : pas de hook stderr GdUnit4. Couverture indirecte via invariants a-e. Tracking backlog instrumentation framework.
5. **NEW — Test infra autoload reuse (W-4)** : NE bloque pas le périmètre Combat (isolated PASS), mais bloque `/smoke-check sprint` global. Story tech-debt dédiée à créer (option A `smoke-2026-05-05.md`) avant que la suite full-stack puisse à nouveau tourner d'un coup. **Ne bloque pas advancement Combat Pre-Production → Pre-Release.**

### Avancement autorisé

**Pre-Production → Pre-Release sur le code Combat est justifié** (re-affirmé 2026-05-05).

Les 20 stories code-livrables Combat passent toutes leurs tests automatisés en isolation. Le seul bloqueur résiduel sur Combat est qualitatif (story-019 panel Martin) — ne bloque pas advancement code. Story-021 closed via migration VFX résout le bloqueur AC-CMB-42 sans dépendance VFX GDD côté Combat. La gate Production formelle reste conditionnelle à Tier 1 hardware sign-off + AC-VFX-01/02/03/30 implementation côté VFX Epic.

Test infra cross-pollution (W-4) est traité comme tech-debt **séparé** : ne touche pas Combat slice integrity.

---

### Next Step

**Recommandation primaire** : `/gate-check` pour évaluation formelle Pre-Production → Pre-Release advancement Combat slice (Opus tier multi-doc synthesis).

**Recommandations secondaires en parallèle** :
- (a) Story tech-debt `test-infra-autoload-reset-between-suites` (option A `smoke-2026-05-05.md`) — déblocage `/smoke-check sprint` full-stack futur
- (b) Recrutement panel testers story-019 (coordination Martin ~10h)
- (c) Pickup Sprint 2 next epic (Credit Economy 008 = HUD blocked, Shop close-out, VFX system stories AC-VFX-01/02/03/30, Audio System Epic Complete 12/12 → next epic)

**Alternative** : commit batch close-out 2026-05-05 (smoke report + signoff today + cleanup docs) puis `/gate-check`.

---

### Logs / Evidence

- **Re-confirmation 2026-05-05** : `reports/report_398/results.xml` — 118/118 PASS exit 0
- **Smoke check 2026-05-05** : `production/qa/smoke-2026-05-05.md` — verdict FAIL global / Combat isolated PASS
- **Précédent signoff 2026-05-04** : `production/qa/qa-signoff-combat-system-2026-05-04.md`
- **QA plan référence** : `production/qa/qa-plan-combat-system-2026-05-04.md`
- **Tests Combat suite** : 20 suites / 118 cases / 0 errors-failures-orphans (`tests/unit/combat/` + `tests/integration/combat/`)
- **Baselines** : `tests/perf/combat-integration-frametime-log.md` + `tests/perf/combat-shapecast-microbench-log.md`
- **Empirical** : `tests/empirical/shapecast_overlap_origin_test.gd` (Gap 2 verdict B)
- **Protocole panel** : `production/qa/protocols/combat-feel-interview.md`
- **EPIC table** : `production/epics/combat-system/EPIC.md` (header `20 Complete + 1 Ready (019) + 1 Closed - Migrated to VFX (021)`)
