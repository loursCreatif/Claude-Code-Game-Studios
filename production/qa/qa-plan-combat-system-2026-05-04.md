# QA Plan — Epic Player Combat System (Sprint 1 Combat CLOSE-OUT) — 2026-05-04

> **Pipeline** : `/team-qa sprint` Phase 3
> **Branche** : `chore/story-014-tech-debt-cleanup`
> **Commit milestone** : `907a25c` (story-018 integration soak Apple M4 baseline 4/4 PASS)
> **Stage projet** : Pre-Production
> **Review mode** : Solo MVP

---

## 1. Scope

| Field | Value |
|-------|-------|
| Sprint | Combat System CLOSE-OUT (Sprint 1) |
| Stories | 22 (story-001 → story-022) |
| Period | 2026-04-23 (Foundation) → 2026-05-04 (Integration soak baseline + doc sync) |
| Engine | Godot 4.6 + GDScript + Jolt physics |
| ADR governing | ADR-0001 (Physics 60Hz) + ADR-0002 (Camera aim_forward) + ADR-0005 (Movement signals) + ADR-0006 (Combat Tick Model) + ADR-0008 (Collision layers) + ADR-0015 (Accessibility) |
| GDD reference | `design/gdd/player-combat-system.md` (TR-cmb-001 → TR-cmb-017, AC-CMB-01 → AC-CMB-37) |

---

## 2. Story Classification Table

| Story | Title (court) | Type | Automated test path | Manual scope | Blocker |
|-------|---------------|------|---------------------|--------------|---------|
| 001 | Scene skeleton + structural invariants | Logic | `tests/unit/combat/scene_skeleton_invariants_test.gd` | — | NON |
| 002 | State machine + cooldown + active_tick lifecycle | Logic | `tests/unit/combat/state_machine_lifecycle_test.gd` | — | NON |
| 003 | Death/respawn lifecycle full reset | Logic | `tests/unit/combat/death_respawn_lifecycle_test.gd` (6/6) | — | NON |
| 004 | `attacked()` handler + buffer single-slot 80ms | Logic | `tests/unit/combat/attacked_handler_buffer_test.gd` (9/9) | — | NON |
| 005 | `_build_capsule_basis()` helper + 100-sample sphere | Logic | `tests/unit/combat/build_capsule_basis_test.gd` (6/6) | — | NON |
| 006 | ShapeCast3D node config + collision layers | Logic | `tests/unit/combat/shapecast_collision_layers_test.gd` (4/4) | — | NON |
| 007 | Sweep position + aim_forward + NaN guards | Logic | `tests/unit/combat/sweep_position_aim_guards_test.gd` (8/8) | — | NON |
| 008 | `_prev_position` per-tick + REACH constant | Logic | `tests/unit/combat/prev_position_per_tick_test.gd` (7/7) | — | NON |
| 009 | Anti-tunneling N=3 substeps + Jolt margin | Logic | `tests/unit/combat/anti_tunneling_substeps_test.gd` (8/8) | — | NON |
| 010 | Tick-0 overlap mitigation Gap 2 | Logic | `tests/empirical/shapecast_overlap_origin_test.gd` + `tests/integration/combat/tick_0_overlap_mitigation_regression_test.gd` (2/2) | — | NON (Variante B empirique — Godot 4.6+Jolt natively detects) |
| 011 | Single-hit kill + dedup `_hit_this_swing` | Logic | `tests/unit/combat/single_hit_kill_dedup_test.gd` | — | NON |
| 012 | Multi-hit + tri distance + MAX_KILLS + multi_kill | Logic | `tests/unit/combat/multi_hit_distance_sort_test.gd` | — | NON |
| 013 | Slow-mo wall-clock + Callable injection | Logic | `tests/unit/combat/slow_mo_wall_clock_test.gd` (7/7) | — | NON |
| 014 | Mutual kill Hybrid M1 Option C `_death_pending` | Integration | `tests/integration/combat/mutual_kill_death_pending_test.gd` (4/4) | — | NON |
| 015 | Mid-swing transitions + race Idle + pause spam | Integration | `tests/integration/combat/mid_swing_transitions_test.gd` (3/3) | — | NON |
| 016 | Invariants runtime `_validate_invariants()` smoke | Logic | `tests/unit/combat/invariants_runtime_validation_test.gd` (5/5) | — | NON |
| 017 | ShapeCast microbench p99 ≤5ms | Performance | `tests/perf/combat_shapecast_microbench_test.gd` (1/1, p99=0.005ms M4) | Tier 1 hardware sign-off ADVISORY DEFERRED CI infra | NON |
| 018 | Integration soak frametime + memory + OBJECT_COUNT | Integration | `tests/integration/combat/integration_soak_test.gd` (4/4, p99=0.014ms) | (f) zero warnings + draw_calls full-stack DEFERRED | NON |
| 019 | Combat feel playtest protocol Visual/Feel ACs | Visual/Feel ADVISORY | — (protocole publié) | Panel ≥5 testeurs × 3 sessions Martin (~10h coordination) | OUI ADVISORY (panel pending) |
| 020 | Swoosh fade + multi-kill clac + ducking | Integration | `tests/integration/combat/audio_multi_kill_ducking_test.gd` (11/11 MockAudioHandler contract-only) | — | NON |
| 021 | VFX decal cap pool LRU contract | Integration | — (NON CRÉÉ) | — | **OUI BLOCKING (VFX System GDD absent)** |
| 022 | Accessibility `reduce_motion` Combat impact | Logic | `tests/unit/combat/accessibility_reduce_motion_test.gd` (8/8) | — | NON |

**Bilan** : 20/22 stories Complete | 19 tests automatisés (unit + integration + perf + empirical) | 1 story Visual/Feel ADVISORY pending panel Martin (story-019) | 1 story Integration BLOCKING (story-021 VFX GDD).

---

## 3. Automated Test Requirements

**Suite Combat complète** :
```bash
godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add tests/unit/combat/ \
  --add tests/integration/combat/ \
  --add tests/perf/combat_shapecast_microbench_test.gd \
  --ignoreHeadlessMode
```

| Catégorie | Path | Tests | Status |
|-----------|------|-------|--------|
| Unit Logic | `tests/unit/combat/` | ~80 cases (stories 001-013, 016, 022) | ALL PASS |
| Integration | `tests/integration/combat/` | ~25 cases (stories 014-015, 017-018, 020) | ALL PASS |
| Performance | `tests/perf/combat_shapecast_microbench_test.gd` | 1 case (baseline p99 M4) | PASS |
| Empirical | `tests/empirical/shapecast_overlap_origin_test.gd` | 1 verdict run (story-010) | PASS verdict B |

**Régressions historiques cleared** :
- Mac Finder dupes ` 2.gd` parsing : ignorés via `.gdignore` + run-time isolation des dupes (production cmdtool path-list explicite)
- GdUnit4 v5 lambda capture-by-value : commit `4881c1e` correctif global
- Storage 117/117 + Camera 16/16 + Movement 65/65 + Combat 32/32 (post-018) → suite globale ≥230 PASS

---

## 4. Manual QA Scope

### Story 019 — Combat feel playtest (BLOQUÉ panel Martin)

**Protocole** : `production/qa/protocols/combat-feel-interview.md` (15 questions × 5 axes : description spontanée → kill mvmt vs static → slow-mo perception → Likert r6 REC-02 → open-ended).

**Pass criteria quantifiés** :
- AC-CMB-31 : ≥4 lexèmes IN-FLOW × ≥80% panel + 0 lexème BANNED
- AC-CMB-32 : ≥80% panel mentionne contexte kill-mvmt vs static
- AC-CMB-33 : ≥80% panel mentionne lexèmes VIDE-OU-MANQUE pour absence slow-mo
- AC-CMB-34 : médiane Likert ≥4/5 + ≥70% testeurs note ≥4/5

**Effort** : recrutement ≥5 testeurs naïfs francophones × 3 sessions × ~30 min = ~10h coordination Martin.

**Evidence** : `production/qa/evidence/combat-feel-playtest-{date}.md` (1 par session).

### Story 022 — Accessibility manual (Polish P3)

**Status** : Complete (8/8 auto tests). Aucune action manuelle requise pour close-out — validation Visual/Feel optionnelle Polish phase.

---

## 5. Out of Scope

| Item | Raison |
|------|--------|
| Tier 1 hardware sign-off (stories 017+018) | DEFERRED CI infrastructure dédiée. Apple M4 dev laptop = INFORMATIONAL BASELINE (×1666-3320 sous seuils). |
| draw_calls full-stack gate (story-018) | Headless RenderingServer dummy retourne 0. Requires Forward+ runner non-headless Tier 1. |
| story-018 (f) zero warnings stderr | Pas de hook GdUnit4 stderr instrumentation. Couverture indirecte via invariants a-e. |
| story-021 VFX decal cap test | Bloqué VFX System GDD (créer `decal_cap_contract_test.gd` AC-CMB-42a quand GDD disponible). |
| story-019 manual sessions | Bloqué recrutement Martin. Protocole prêt, exécution coordination future. |
| Save/Load smoke checks #6 #7 | SaveLoad Epic non-démarré — SKIP conditionnel. |

---

## 6. Entry Criteria

- [x] Smoke check `tests/smoke/critical-paths.md` PASS WITH WARNINGS (W1 Tier 1 hardware, W2 draw_calls, W3 SaveLoad SKIP — non-bloquants)
- [x] Tous tests automatisés Combat ≥230 PASS suite globale
- [x] Lint statiques propres : `lint-collision-layers`, `lint-audio-anti-patterns`, `movement-emit-physics-only`, `no-alloc-hot-paths`, `lint-input-main-thread`
- [x] ADRs Combat ratifiés : ADR-0001/0002/0005/0006/0008/0015 ALL Accepted
- [x] GDD player-combat-system.md à jour (manifest 2026-04-23+)

---

## 7. Exit Criteria

- [x] 19/22 tests automatisés PASS (Logic + Integration + Performance baselines documentées)
- [x] Stories 001+002 doc sync Status `Ready → Complete` (downstream couvre)
- [ ] Story 019 panel Martin executé (BLOQUÉ recrutement) — ADVISORY, ne bloque pas gate Pre-Production → Pre-Release sur le code
- [ ] Story 021 `decal_cap_contract_test.gd` créé (BLOQUÉ VFX System GDD) — bloque gate Pre-Production → Production
- [x] Sign-off report écrit (`production/qa/qa-signoff-combat-system-2026-05-04.md`)

---

## 8. Risks & Conditions

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Tier 1 hardware divergence vs Apple M4 baseline | LOW | MEDIUM (gate sign-off) | Apple M4 plus puissant que Tier 1 minimum (i3-10100F + GTX 1050) → directionnel. Re-run testbed Tier 1 avant gate Production formelle. |
| Story 019 panel impossible à recruter sous 4 sem. | MEDIUM | LOW (ADVISORY) | Protocole publié réutilisable post-MVP. Combat feel sign-off creative-director peut être déféré sans bloquer code. |
| VFX System GDD non créé sous 4 sem. | MEDIUM | MEDIUM (story-021 BLOCKED) | Scinder AC-CMB-42a (headless mock) vs AC-CMB-42b (GPU Tier 1) dans VFX GDD quand publié. AC-CMB-42a peut être livré indépendamment. |
| Régression Combat post-Audio MUSIC sidechain (story-020) | LOW | HIGH | Suite intégration `audio_multi_kill_ducking_test.gd` 11/11 PASS gate. Re-run avant chaque commit touchant CombatSystem. |

---

## 9. References

- Sign-off attendu : `production/qa/qa-signoff-combat-system-2026-05-04.md`
- EPIC : `production/epics/combat-system/EPIC.md` (20 Complete + 1 Ready + 1 Blocked post doc sync 2026-05-04)
- GDD : `design/gdd/player-combat-system.md`
- ADR-0006 Combat Tick Model : `docs/architecture/adr-0006-combat-tick-model.md`
- Smoke check master : `tests/smoke/critical-paths.md`
- Protocole feel : `production/qa/protocols/combat-feel-interview.md`
