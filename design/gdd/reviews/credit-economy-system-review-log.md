# Credit Economy System — Review Log

> Continuous log of all design reviews on `design/gdd/credit-economy-system.md`.
> Each review entry summarizes verdict, scope, blocking items resolved/added.
> Detailed reports : `credit-economy-system-review-r[N]-[date].md`.

---

## Review — 2026-04-27 — Verdict: NEEDS REVISION

**Scope signal** : M
**Specialists** : economy-designer, qa-lead, game-designer, systems-designer, creative-director (synthèse)
**Blocking items** : 7 ship-blocking | **Pre-impl** : 10 | **Polish** : 9
**Detailed report** : `credit-economy-system-review-r1-2026-04-27.md`

**Summary** :

GDD r1 (596 lignes, 49 ACs, 9 OQ) — **8/8 sections présentes**, qualité comparable à Secret r1 / Shop r1. Pillars (FLOW + PROGRESSION SE VOIT + SECRETS) **intacts**, dette tactique non stratégique. Coïncidence de design avec Shop/HUD/Secret r1 livrés le même jour a créé contradictions cross-GDD attendues.

**7 ship-blocking** : (B-1) Rule 7 multi-kill batching default flip (Pillar 1 FLOW) ; (B-2) combat-only soft-lock 8 cr < 20 cr upgrade — punition playstyle ; (B-3) contradiction tween SPEND_SHOP Credit GDD vs HUD r1 R-6 ; (B-4) F-CRD-3 sanity ligne 370 cassé à N=8 ; (B-5) 6 ACs Lints/Static mal classés Logic BLOCKING ; (B-6) Rule 6 `_credited_this_run` purge checkpoint intra-étage non spec'd ; (B-7) race boot `level_active` vs `state_changed(PLAYING)` AC manquant.

**Adjudications creative-director** : Rule 7 batching `BATCH_MULTI_KILL_EMIT = true` MVP par défaut (Pillar 1 > analytics granularité Tier 2+) ; asymétrie 5:1 viscérale — 1 SFX/VFX différencié MVP minimum, sinon retirer claim Player Fantasy.

**OQ résolutions** : OQ-CRD-1 RESOLVED par Secret r1 (`secret_collected(secret_node: Node, tier: int)` SYNC confirmé) ; OQ-CRD-2 RESOLVED par Shop r1 (`try_spend(amount: int) -> bool` SYNC atomique confirmé). Voir amendement Credit r2 cosmétique.

**Path to APPROVED** : r2 amendment focalisé <1 jour addressing 7 ship-blocking. Pre-impl 10 items batchables seconde passe Sprint A.

**Prior verdict resolved** : First review.

---

## r2 Full Revision — 2026-04-27 — Verdict: Designed r2 (pending fresh re-review)

**Scope signal** : M (Medium — focused fix pass, no new sections)
**Method** : `/design-system credit-economy-system` solo auto-approve, targeted Edit on 7 ship-blockers (no full re-design of approved sections)
**Resolved** : 7 ship-blockers (B-1 through B-7) — all paths to APPROVED unblocked.
**Deferred** : 10 pre-implementation items + 9 polish items reported separately for next batch.

**Changes applied (file-level)** :

1. **Header** — Status `In Design (r2 — full revision)` ; `Last Updated 2026-04-27 (r2 full revision)` ; review history line documents B-1..B-7 résolution one-line each.
2. **Rule 5** (B-7) — Découplage strict connexion ↔ signaux : `enemy_killed.connect(...)` à `level_active` indépendamment de `_is_hydrated` ; guard rejette signaux reçus pas connexions ; contrainte MVP late spawns documentée + cross-ref OQ-CRD-7.
3. **Rule 6** (B-6) — `_credited_this_run` n'est PAS purgé sur checkpoint intra-étage. State-restore via Enemy `_restore_from_snapshot` (EC-ENM-11) ne re-émet pas `enemy_killed` → 0 risque double-crédit. Set IDs morts pré-checkpoint préservé (garde défensive).
4. **Rule 7** (B-1) — Multi-kill simultané : 1 emit batched par défaut MVP. `BATCH_MULTI_KILL_EMIT = true` MVP, creative-director adjudication pillar-driven. Compteur passe par états intermédiaires N→N+1→N+2→N+3 internement, signal final unique `(N+3, +3, KILL)`. Knob `false` Tier 2+ restaure 3 emits séquentiels.
5. **Rule 11** (B-7) — Boot hydration : guard `_is_hydrated == false` sur PREMIÈRE réception PLAYING uniquement ; transitions PLAYING ultérieures (depuis PAUSED/MENU/RESPAWNING) no-op. Découplage hydration ↔ connexion ennemis explicité.
6. **F-CRD-1 worked example** (B-1) — `credits_changed` émis 1 fois batched au lieu de 3 séquentiels.
7. **F-CRD-3** (B-2) — `BASE_UPGRADE_COST` : 20 → **8 cr**. Tables MVP (8/28) + Full Vision (8..148) recalculées. Justification mise à jour : anti soft-lock combat-only étage 1 + atteignable n=7=148 cr en 3-4 sessions.
8. **F-CRD-4 worked examples** (B-2 + B-4) — Combat-only étage 1 : 8 cr → upgrade n=0 atteignable. Run complète recalculée (33+52=85 cr, 2 upgrades + 49 cr résiduel). Sanity check cumulatif Tier 2+ N=8 ajouté (Σ=624 ≤ 680 cr ✅).
9. **EC-CRD-5** (B-1) — Multi-kill batched 1 emit (cohérence Rule 7).
10. **EC-CRD-7** (B-6) — Cross-ref AC-CRD-50 ; `_credited_this_run` non purgé sur checkpoint clarifié.
11. **EC-CRD-11** (B-7) — Cross-ref AC-CRD-51 ; découplage connexion vs signal explicité.
12. **EC-CRD-16** (B-6) — Distinction explicite `request_new_run()` purge / checkpoint ne purge pas.
13. **Tuning Knob `BASE_UPGRADE_COST`** (B-2) — 20→8, safe range [15,40]→[5,15], anti soft-lock noted.
14. **Tuning Knob `BATCH_MULTI_KILL_EMIT`** (B-1) — `false`→**`true`** MVP par défaut, description inversée.
15. **Cross-tuning interactions** (B-2 + B-4 + B-1) — 5 sanity checks raffinés : (i) secret yield ≥ upgrade cost, (ii) NEW BASE_UPGRADE_COST ≤ kill_yield_etage_1 anti soft-lock, (iii) sanity dernière upgrade 1 cycle, (iv) NEW cumulatif Tier 2+ N=8 N_SESSIONS_TARGET ∈ [8,10], (v) si BATCH_MULTI_KILL_EMIT=false alors HUD doit gérer 3 pulses.
16. **AC-CRD-08** (B-1) — Reformulé : 1 emit batched MVP par défaut, variante 3 emits séquentiels Tier 2+ knob.
17. **AC-CRD-31** (B-1) — Reformulé : exactement 1 signal `credits_changed(N+3, +3, KILL)` capturé par spy, états intermédiaires non observables.
18. **AC-CRD-32** (B-5) — Supprimé doublon AC-CRD-42.
19. **AC-CRD-20+21 fusion** (B-5) — Reclassés Lints/Static en AC-CRD-20 unifié : grep statique `try_spend` body, 0 await/emit_signal/call_deferred/Thread.start/WorkerThreadPool. Test `tests/static/credit_economy_lint_test.gd`.
20. **AC-CRD-50** (B-6 — NEW) — Integration test checkpoint purge : Enemy `_restore_from_snapshot` ne re-émet pas, `_credited_this_run` reste à N, compteur stable, 0 emit pendant restore.
21. **AC-CRD-51** (B-7 — NEW) — Integration test race boot 4 phases : `level_active` à T0 → connexions établies + `_is_hydrated == false` ; signal pré-PLAYING rejeté ; `state_changed(PLAYING)` à T1 → hydration + BOOT_HYDRATE 1 emit ; signaux post-PLAYING traités.
22. **Test Coverage Matrix** (B-5) — 11 sous-thèmes recalculés : Sink Shop (3) ; Signal credits_changed (4) ; Lints/Static **ligne dédiée** (6 ACs : 20+41+42+43+44+45) ; Edge cases (5 : 47..51). Total : 42 Logic/Integration/Perf BLOCKING + 6 Lints/Static BLOCKING + 1 ADVISORY = 49 ✅.
23. **Header total ACs note** (B-5) — Décomposition r2 explicite : 49 ACs net (-1 supprimé -1 fusionné +2 ajoutés).
24. **OQ-CRD-5** (B-1) — RESOLVED par adjudication creative-director (multi-kill batching).

**Adjudications retenues r2** :

- **Pillar-driven CD** : `BATCH_MULTI_KILL_EMIT = true` MVP par défaut non-négociable.
- **CD option (a)** anti soft-lock B-2 : `BASE_UPGRADE_COST = 8 cr` (préféré CD vs option B feedback partiel — change le coût plutôt que d'ajouter du UI).

**Reportés batch séparé** :

- **10 pre-implementation items** : P-1 asymétrie 5:1 viscérale audio MVP, P-2 ROOM_CLEAR_BONUS retirer enum MVP, P-3 ambiguïté hydratation premier vs tout PLAYING (RESOLVED inline r2 Rule 11), P-4 AC-CRD-29 mécanisme GUT précis, P-5 AC-CRD-39 perf gate 0.1ms→1ms médiane, P-6 AC-CRD-46 binding HUD testable, P-7 promote ACs provisoires Secret/Shop, P-8 ratio 5:1 brisable knob `kill_credit["grunt"]` safe range [1,1], P-9 anti-grinding non-enforced documenté, P-10 late spawns dynamiques OQ-CRD-10 ajouter (RESOLVED inline r2 Rule 5 contrainte MVP).
- **9 polish items** : N-1 North Star "ticker"→"odomètre", N-2..N-9 cosmetic.

**Prior verdict resolved** : NEEDS REVISION (review r1 2026-04-27) — 7 ship-blockers résolus.

**Next** : fresh `/design-review credit-economy-system` re-review session (parallel session, full mode) pour confirmer Designed r2 → APPROVED. 10 pre-impl + 9 polish batch séparé après confirmation r2.
