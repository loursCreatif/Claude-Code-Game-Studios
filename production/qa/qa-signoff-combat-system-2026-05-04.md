## QA Sign-Off Report: Epic Player Combat System (Sprint 1 CLOSE-OUT)

**Date**: 2026-05-04
**Branche**: chore/story-014-tech-debt-cleanup
**Commit milestone**: `907a25c` (`feat(combat/perf): story-018 integration soak frametime + Apple M4 baseline (4/4 PASS)`)
**Stage**: Pre-Production
**Review mode**: Solo MVP
**QA Lead sign-off**: Solo (Claude assist 2026-05-04)

---

### Smoke Check Result

**PASS WITH WARNINGS** — 3 warnings non-bloquants documentés.

| # | Warning | Impact | Tracking |
|---|---------|--------|----------|
| W-1 | Tier 1 hardware sign-off DEFERRED — stories 017+018 baselines Apple M4 INFORMATIONAL | Sign-off officiel CI infra requis avant gate Pre-Production → Production | Backlog CI infra dédié |
| W-2 | draw_calls full-stack gate DEFERRED — headless RenderingServer dummy retourne 0 | Gate strict ≤500 draw calls requis sur runner non-headless Tier 1 | Backlog CI infra dédié + story-018 (e) |
| W-3 | Save/Load smoke checks #6 #7 SKIP — SaveLoad Epic non démarré | Activer quand SaveLoad Epic démarre | Sprint SaveLoad futur |

Zéro warning BLOCKING. Build stable. Sortie exit 0 sur tous les runs Combat (32/32 PASS post-018).

---

### Test Coverage Summary

| Story | Type | Auto Test | Manual QA | Result |
|-------|------|-----------|-----------|--------|
| 001 — Scene skeleton + structural invariants | Logic | `scene_skeleton_invariants_test.gd` | — | PASS (doc sync — couvert downstream) |
| 002 — State machine + cooldown + active_tick lifecycle | Logic | `state_machine_lifecycle_test.gd` | — | PASS (doc sync — couvert downstream) |
| 003 — Death/respawn lifecycle full reset | Logic | `death_respawn_lifecycle_test.gd` (6/6) | — | PASS |
| 004 — `attacked()` handler + buffer single-slot 80ms | Logic | `attacked_handler_buffer_test.gd` (9/9) | — | PASS |
| 005 — `_build_capsule_basis()` helper + 100-sample sphere | Logic | `build_capsule_basis_test.gd` (6/6) | — | PASS |
| 006 — ShapeCast3D node config + collision layers | Logic | `shapecast_collision_layers_test.gd` (4/4) | — | PASS |
| 007 — Sweep position + aim_forward + NaN guards | Logic | `sweep_position_aim_guards_test.gd` (8/8) | — | PASS |
| 008 — `_prev_position` per-tick + REACH constant | Logic | `prev_position_per_tick_test.gd` (7/7) | — | PASS |
| 009 — Anti-tunneling N=3 substeps + Jolt margin | Logic | `anti_tunneling_substeps_test.gd` (8/8) | — | PASS |
| 010 — Tick-0 overlap mitigation Gap 2 | Logic | `shapecast_overlap_origin_test.gd` (empirical verdict B) + `tick_0_overlap_mitigation_regression_test.gd` (2/2) | — | PASS — 0 prod code (Godot 4.6+Jolt natively detects) |
| 011 — Single-hit kill + dedup `_hit_this_swing` | Logic | `single_hit_kill_dedup_test.gd` | — | PASS |
| 012 — Multi-hit + tri distance + MAX_KILLS + multi_kill | Logic | `multi_hit_distance_sort_test.gd` | — | PASS |
| 013 — Slow-mo wall-clock + Callable injection | Logic | `slow_mo_wall_clock_test.gd` (7/7) | — | PASS |
| 014 — Mutual kill Hybrid M1 Option C `_death_pending` | Integration | `mutual_kill_death_pending_test.gd` (4/4) | — | PASS |
| 015 — Mid-swing transitions + race Idle + pause spam | Integration | `mid_swing_transitions_test.gd` (3/3) | — | PASS |
| 016 — Invariants runtime `_validate_invariants()` smoke | Logic | `invariants_runtime_validation_test.gd` (5/5) | — | PASS |
| 017 — ShapeCast microbench p99 ≤5ms | Performance | `combat_shapecast_microbench_test.gd` (1/1, p99=0.005ms M4) | Tier 1 sign-off ADVISORY DEFERRED CI infra | PASS (×3320 sous seuil baseline) |
| 018 — Integration soak frametime + memory + OBJECT_COUNT | Integration | `integration_soak_test.gd` (4/4, p99=0.014ms / mem ≤500KB / object Δ ≤+5) | (f) zero warnings + draw_calls full-stack DEFERRED | PASS (×1166 sous seuil) |
| 019 — Combat feel playtest protocol Visual/Feel ACs | Visual/Feel ADVISORY | — | Panel ≥5 testeurs × 3 sessions Martin (~10h coordination) | PENDING (protocole publié, recrutement pending) |
| 020 — Swoosh fade + multi-kill clac + ducking | Integration | `audio_multi_kill_ducking_test.gd` (11/11 MockAudioHandler) | — | PASS |
| 021 — VFX decal cap pool LRU contract | Integration | — (NON CRÉÉ) | — | **BLOCKED (VFX System GDD absent)** |
| 022 — Accessibility `reduce_motion` Combat impact | Logic | `accessibility_reduce_motion_test.gd` (8/8) | — | PASS |

**~80 unit + ~25 integration + 1 perf + 1 empirical = ~107 cases Combat — exit 0 — zéro régression cross-stories.**

---

### ACs Coverage Summary

**BLOCKING headless : ALL COVERED (sauf story-021 BLOCKING externe VFX GDD)**

| Groupe AC | Couverture |
|-----------|------------|
| AC-CMB-01→04 (State machine + cooldown + active_tick) | ✅ BLOCKING PASS |
| AC-CMB-05→09 (attacked + buffer + clear死 / capsule basis / shapecast layers) | ✅ BLOCKING PASS |
| AC-CMB-10→18 (sweep + aim_forward + prev_position + anti-tunneling + tick-0 + dedup + multi-hit) | ✅ BLOCKING PASS |
| AC-CMB-19→25 (slow-mo wall-clock + accessibility mults + Callable injection) | ✅ BLOCKING PASS |
| AC-CMB-26→30 (mutual kill Hybrid M1 + mid-swing transitions + invariants runtime) | ✅ BLOCKING PASS |
| AC-CMB-31→34 (Visual/Feel — kill mvmt vs static, slow-mo perception, Likert) | 🟡 ADVISORY PENDING (story-019 panel Martin) |
| AC-CMB-35a (microbench p99) | ✅ PASS — baseline INFORMATIONAL Apple M4 |
| AC-CMB-35b (integration soak frametime + soak global) | ✅ PASS — baseline INFORMATIONAL Apple M4 |
| AC-CMB-37 a/b/c/d/e (soak invariants + memory + objects) | ✅ BLOCKING PASS |
| AC-CMB-37 (f) zero warnings stderr | 🟡 ADVISORY DEFERRED instrumentation GdUnit4 |
| AC-CMB-42a (decal cap headless mock contract) | 🔴 BLOCKED — VFX System GDD absent |
| AC-CMB-42b (decal cap GPU Tier 1) | 🟡 ADVISORY DEFERRED Post-Pre-Production |
| AC-CMB-51 + AC-CMB-audio-01/02 (Audio System contract MockAudioHandler) | ✅ BLOCKING PASS (story-020 11/11) |
| AC-CMB-Accessibility (reduce_motion impacts) | ✅ BLOCKING PASS (story-022 8/8) |

---

### Bugs Found

| ID | Story | Severity | Status |
|----|-------|----------|--------|

**Aucun bug ouvert sur le périmètre Combat Epic.**

Note historique : story-018 review (2026-05-04) a appliqué fix `auto_free()` sur instances combat tests pour éliminer risque leak inter-test (qa-tester suggestion code-review APPROVED WITH SUGGESTIONS). 4/4 PASS post-fix, 0 orphans détectés.

---

### Verdict: APPROVED WITH CONDITIONS

**Justification** :

20/22 stories Complete avec tests automatisés passants — coverage 100% des stories code-livrables. Stories 001/002 doc sync appliqué (downstream couvre via stories 003-022 Complete). Baselines performance Apple M4 stories 017+018 ×1166-3320 sous seuils — zéro risque frame budget intra-engine. Lint statiques propres (collision-layers + audio-anti-patterns + movement-emit-physics-only + no-alloc-hot-paths + input-main-thread).

Story 020 Audio Integration (11/11 MockAudioHandler) ferme contrat Combat-Audio.
Story 022 Accessibility Logic (8/8) ferme TR-cmb-016 + ADR-0015.

### Conditions

1. **Story 021 BLOCKED (Integration VFX)** : AC-CMB-42a headless-safe (decal cap mock contract) à créer dès VFX System GDD disponible. Avant gate Pre-Production → Production, `decal_cap_contract_test.gd` doit exister et passer. AC-CMB-42b GPU Tier 1 déféré Post-Pre-Production. **Bloque gate Production formelle, pas le close-out Pre-Release sur le code Combat.**

2. **Story 019 ADVISORY (Visual/Feel panel)** : panel ≥5 testeurs × 3 sessions Martin à exécuter avant gate feel design sign-off creative-director. Protocole publié (`production/qa/protocols/combat-feel-interview.md`) — exécution coordination future. **Ne bloque pas l'avancement code Combat.**

3. **Tier 1 sign-off DEFERRED (W-1, W-2)** : stories 017+018 baselines Apple M4 INFORMATIONAL. Gate officielle draw_calls + hardware certification CI infra requise avant Production. Apple M4 plus puissant que Tier 1 minimum (i3-10100F + GTX 1050) → directionnel uniquement.

4. **Story-018 (f) zero warnings DEFERRED** : pas de hook stderr GdUnit4. Couverture indirecte via invariants a-e. Tracking backlog instrumentation framework.

### Avancement autorisé

**Pre-Production → Pre-Release sur le code Combat est justifié.**

Les 20 stories ayant des tests passants représentent la totalité du code livrable Combat Epic (021 = contrat externe VFX bloqué upstream, 019 = qualitatif feel coordination Martin). La gate Production formelle reste conditionnelle à Tier 1 sign-off + story 021 AC-CMB-42a.

---

### Next Step

**Recommandation** : `/gate-check` pour évaluation formelle Pre-Production → Pre-Release advancement. Si APPROVED par gate-check, paralléliser :
- (a) Recrutement panel testers story-019 (coordination Martin ~10h)
- (b) `/design-system vfx-system` pour débloquer story-021 AC-CMB-42a
- (c) Pickup Sprint 2 next epic (Credit Economy, Shop, Upgrade chain blockers, etc.)

**Alternative** : continuer Pre-Production avec attaque blockers parallèle (option b + c) avant gate-check formelle.

---

### Logs / Evidence

- Tests Combat suite : tous tests verts post-commit `907a25c` (story-018) + history commits 003-018+020+022 sur branche `chore/story-014-tech-debt-cleanup`
- Baseline frametime : `tests/perf/combat-integration-frametime-log.md` (5 runs Apple M4 — p99 stable 0.011-0.020 ms worst case / 0.011-0.015 ms soak global)
- Baseline microbench : `tests/perf/combat-shapecast-microbench-log.md` (story-017 baseline)
- Empirical Gap 2 : `tests/empirical/shapecast_overlap_origin_test.gd` (verdict B — Godot 4.6+Jolt natively detects overlap origin)
- Protocole panel : `production/qa/protocols/combat-feel-interview.md`
- EPIC table à jour : `production/epics/combat-system/EPIC.md` (20 Complete + 1 Ready + 1 Blocked post doc sync 2026-05-04)
- QA Plan : `production/qa/qa-plan-combat-system-2026-05-04.md`
