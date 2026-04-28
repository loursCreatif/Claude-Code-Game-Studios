# Credit Economy System — Review Log

> Continuous log of all design reviews on `design/gdd/credit-economy-system.md`.
> Each review entry summarizes verdict, scope, blocking items resolved/added.
> Detailed reports : `credit-economy-system-review-r[N]-[date].md`.

---

## Review — 2026-04-28 (lean re-pass) — Verdict: **APPROVED r3**

**Scope signal** : M (inchangé depuis r2 — single system, 4 formulas, 6 hard deps, 49 ACs)
**Method** : `/design-review credit-economy-system --depth lean` single-session fresh, no Phase 3b specialist spawn (lean mode)
**Specialists** : none (lean mode)
**Blocking items** : 0 BLOCKING | **Recommended** : 1 NEW (éditorial cosmétique non-bloquant) | **Nice-to-have** : 0 NEW

**Summary** :

Fresh lean re-pass post r3 ciblée editorial. **Les 4 NB-CRD résiduels post r2 sont effectivement résolus**, vérifiés ligne par ligne contre le GDD r3 :

- **NB-CRD-2 RESOLVED** : §Tuning Knobs l.384-397 — invariant `BASE_UPGRADE_COST ≤ N_KILLS_ETAGE_1_MIN × kill_credit["grunt"]` documenté + plancher conservatif `N_KILLS_ETAGE_1_MIN = 6` (R-2.6 Level) + cas nominal `8` + 3 garde-fous opérationnels (test balance-check + tuner alert + coordination Level GDD futur) + pillar impact.
- **NB-CRD-3 RESOLVED** : §UI Requirements l.448-449 — rows VFX gain + Animation soustraction délèguent durées et styles à HUD §J + Rule 5 r1.1 (cross-réf cascade NB-CRD-6 Option A).
- **NB-CRD-4 RESOLVED** : AC-CRD-10 l.515 reformulé sur `request_new_run()` (GSM ADR-0007 D-10 — handler `_on_request_new_run()` aligné Rule 6) + AC-CRD-49 l.588 reformulé sur `level_active` (Level GDD R-2 — premier signal connexion + suivants purge). Notes explicites que les triggers r2 étaient non-canoniques.
- **NB-CRD-5 RESOLVED** : AC-CRD-39 l.568 reformulé `< 1 ms médiane N=100`, P95 `< 3 ms`, outliers exclus, gate **BLOCKING dev hardware / ADVISORY CI** + rationale inline.

**Aucune régression r2** : 7/7 fixes B-1..B-7 r2 préservés intacts (vérifiés Rule 5/6/7/11 + EC-CRD-5/7/11 + F-CRD-3/4 + AC-CRD-08/31/50/51 + Tuning Knobs `BASE_UPGRADE_COST`/`BATCH_MULTI_KILL_EMIT`).

**Cross-system consistency vérifiée** : Shop r2.1 (`BASE_UPGRADE_COST = 8` propagé NB-CRD-1), Audio r2.2 (Rule 17 + Formula 7 cascade NB-CRD-6), HUD r1.1 (Rule 5 différenciation tween cascade NB-CRD-6), Secret r3 (`secret_collected` SYNC LOCKED), GSM ADR-0007 D-10 (`request_new_run()` + `state_changed`), Level R-2/R-2.6, Combat `MAX_KILLS_PER_SWING = 3`. Aucune référence cassée. Dependency graph 9/9 GDDs présents.

**Completeness** : 8/8 sections présentes.

**Compteurs ACs r3 stables** : 49 ACs (48 BLOCKING + 1 ADVISORY) — 42 Logic/Integration/Perf BLOCKING + 6 Lints/Static BLOCKING + 1 Visual/Feel ADVISORY. Test Coverage Matrix cohérente.

**1 RECOMMENDED non-bloquant** :

- **REC-CRD-r3-1 [editorial]** : §Tuning Knobs l.392 — l'invariant runtime balance-check est exprimé sous deux formes différentes dans la même section :
  - Ligne canonique l.392 : `assert(BASE_UPGRADE_COST ≤ floor(0.8 × N_KILLS_ETAGE_1_NOMINAL × kill_credit["grunt"]))` = `floor(0.8 × 8 × 1) = 6 cr` → assert échouerait littéralement avec MVP r3 `BASE_UPGRADE_COST = 8`.
  - Garde-fou opérationnel l.394 (test Sprint 1) : `BASE_UPGRADE_COST ≤ N_KILLS_ETAGE_1_NOMINAL × kill_credit["grunt"]` = `8 ≤ 8 ✓`.
  - Le texte reconnaît le mismatch comme "invariant relaxé MVP exceptionnel" mais conserve les deux formulations dans une même phrase. Risque pour l'implémenteur Sprint 1 : écrire l'assert avec le facteur 0.8 → boot crash.
  - **Suggestion** : promouvoir le facteur 0.8 en sous-bullet séparé "objectif Tier 2+" (recalibrage si `N_UPGRADES > 2` ou playtest révèle joueurs bloqués) ; clarifier que l'invariant **runtime exécuté au boot Sprint 1** est `BASE_UPGRADE_COST ≤ N_KILLS_ETAGE_1_NOMINAL × kill_credit["grunt"]` (sans facteur).
  - **Niveau** : RECOMMENDED — non-bloquant `/create-epics`. Adressable en story Sprint 1 (AC-CRD-39 + balance-check test) ou amendement éditorial isolé < 5 min.

**Path to /create-epics** : unlocked immédiatement. Le RECOMMENDED ci-dessus est cosmétique et n'empêche pas la décomposition stories.

**Prior verdict resolved** : NEEDS REVISION r2 (2026-04-28 fresh full review — 6 BLOCKING NB-CRD-1..6) → 6/6 RESOLVED (NB-CRD-1 cascade Shop r2.1 commit antérieur, NB-CRD-6 cascade Audio r2.2 + HUD r1.1 Option A commit `731c64c`, NB-CRD-2/3/4/5 r3 ciblée editorial commit `ba6ddfe`). **r2 → APPROVED r3**.

---

## r3 Targeted Revision — 2026-04-28 — Verdict: Designed r3 (pending fresh lean re-pass)

**Scope signal** : XS-S (focused editorial — 4 BLOCKING ciblés, ~1h éditorial, 0 nouvelle section, 0 nouvelle Rule structurelle)
**Method** : `/design-system credit-economy-system` r3 solo auto-approve, targeted Edit on 4 BLOCKING résiduels post r2 (NB-CRD-1 et NB-CRD-6 résolus par cascade externe avant r3).
**Trigger** : verdict r2 NEEDS REVISION (6 BLOCKING). NB-CRD-1 (cross-GDD `BASE_UPGRADE_COST` Shop) RESOLVED par Shop r2.1 amendement cosmetic propagation `8 cr` (commit antérieur). NB-CRD-6 (Pillar 4 viscéralité asymétrie 5:1) RESOLVED par cascade Audio r2.2 + HUD r1.1 Option A LIVRÉE 2026-04-28 (commit `731c64c`). Reste 4 BLOCKING editorial pour r3 ciblée.

**Resolved (4 BLOCKING NB-CRD-2/3/4/5)** :

- **NB-CRD-2 — Anti soft-lock B-2 pile-poil : `N_KILLS_ETAGE_1` borne minimale Level non blindée** : Cross-tuning §Tuning Knobs reformulé avec invariant explicite `BASE_UPGRADE_COST ≤ N_KILLS_ETAGE_1_MIN × kill_credit["grunt"]` ; documente `N_KILLS_ETAGE_1_MIN = 2 × 3 = 6` (plancher conservatif R-2.6 Level GDD) vs `N_KILLS_ETAGE_1_NOMINAL = 8` (cas nominal MVP) ; ajoute garde-fous opérationnels (test `tests/integration/balance/credit_anti_softlock_test.gd`, tuner alert balance-check, coordination cross-GDD Level GDD futur amendement) ; marge Pillar 2 absorbée par persistance cross-session `total_credits` (joueur qui rate 1 grunt n'est pas soft-locked définitif).
- **NB-CRD-3 — §UI Requirements l.436 conserve tween hardcodé après délégation B-3** : Tableau §UI Requirements rows "Pulse VFX gain" + "Animation soustraction" reformulés pour déléguer durées et styles à HUD GDD §J + Rule 5 r1.1 (cross-référence Audio/HUD r1.1 cascade NB-CRD-6 Option A) ; Credit ne fixe plus que les requirements pillar-driven (KILL court Pillar 1, SECRET visiblement plus marqué Pillar 4) ; pattern aligné §Visual l.402 corrigé en r2 B-3.
- **NB-CRD-4 — AC-CRD-10 + AC-CRD-49 : triggers `_on_level_unloaded()` / `_on_level_loaded()` non spec Detailed Rules** : AC-CRD-10 reformulé sur trigger canonique `request_new_run()` (GSM ADR-0007 D-10) — handler `_on_request_new_run()` aligné Rule 6 ; AC-CRD-49 reformulé sur trigger canonique `level_active` (Level GDD R-2) — premier signal session pour connexion event-driven Rule 5, second signal pour purge `_credited_this_run` Rule 6 ; ACs maintenant testables et alignés sur signaux documentés Detailed Rules (zéro contrat invisible).
- **NB-CRD-5 — AC-CRD-39 perf gate 0.1 ms intestable en CI** : Reformulé `< 1 ms médiane N=100`, P95 `< 3 ms`, outliers exclus si plateforme non-reproductible ; gate level explicité **BLOCKING dev hardware** / **ADVISORY CI** (cohérent DA-CRD-2 r2 adjudication) ; rationale documenté inline (seuil r2 produisait test fantôme rouge permanent).

**No blocking added** : 0 nouveaux BLOCKING introduits par r3. Couverture ACs stable (49 → 49, count inchangé, AC-CRD-10/39/49 reformulés sur place).

**Files changed** :
- `design/gdd/credit-economy-system.md` (header status r2 → r3 ; Cross-tuning §Tuning Knobs invariant blindé ; §UI Requirements rows VFX gain + Animation soustraction délégation HUD ; AC-CRD-10 + AC-CRD-39 + AC-CRD-49 reformulés ; Acceptance Criteria header note changements r3).
- `design/gdd/reviews/credit-economy-system-review-log.md` (this entry).
- `design/gdd/systems-index.md` (Credit row status `Designed r2 — NEEDS REVISION (r3 ciblée)` → `Designed r3 (pending fresh lean re-pass)`).

**Path to APPROVED** : `/design-review credit-economy-system --depth lean` single-session 5-15 min pour valider non-régression r2 + résolution effective des 4 BLOCKING NB-CRD-2/3/4/5 → APPROVED → unlock `/create-epics credit-economy-system`.

**Prior verdict resolved** : r2 NEEDS REVISION (6 BLOCKING) → 6/6 RESOLVED (NB-CRD-1 cascade Shop r2.1, NB-CRD-6 cascade Audio r2.2 + HUD r1.1 Option A, NB-CRD-2/3/4/5 éditorial r3).

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

---

## Review — 2026-04-28 — Verdict: NEEDS REVISION (r3 ciblée)

**Scope signal** : S/M
**Method** : `/design-review credit-economy-system --depth full` fresh session (4 spécialistes adversariaux parallèles + senior synthèse main reviewer)
**Specialists** : game-designer + economy-designer + systems-designer + qa-lead
**Blocking items** : 6 NEW BLOCKING | **Recommended** : 13 NEW | **Nice-to-have** : 3 NEW
**Detailed report** : `credit-economy-system-review-r2-2026-04-28.md`

**Summary** :

Re-review fresh du r2 post-revision. **Résolution r1 vérifiée : 3/7 complète, 4/7 partielle**. Pattern dominant : corrections ciblées mathématiquement correctes mais propagation cross-GDD non honorée + adjudication CD r1 sur asymétrie viscérale oubliée.

**6 NEW BLOCKING** :
- **NB-CRD-1 SHIP-CRITICAL [3 specialists agree]** : contradiction `BASE_UPGRADE_COST` cross-GDD — Credit r2 = 8 cr vs Shop r2 = 20 cr (Quick Reference l.7 + R-SHP-3 l.98 + Player Fantasy l.21 stale). Shop r2 non-propagé après B-2 → revert factuel anti soft-lock à l'implémentation.
- **NB-CRD-2 [2 specialists agree]** : anti soft-lock B-2 pile-poil — `BASE_UPGRADE_COST(8) ≤ kill_yield_etage_1(8)` égalité stricte, marge zéro. `N_KILLS_ETAGE_1` borne minimale Level non blindée dans Cross-tuning l.384. Si Level r4 ajuste à 6 grunts, soft-lock revient.
- **NB-CRD-3 [2 specialists agree]** : §UI Requirements l.436 conserve "Counter tween 200-400 ms" hardcodé après B-3 délégation HUD r1 R-6 — contradiction interne, implémenteur HUD code mauvais tween.
- **NB-CRD-4 [2 specialists agree]** : AC-CRD-10 + AC-CRD-49 testent triggers `_on_level_unloaded()` / `_on_level_loaded()` non spécifiés dans Detailed Rules. Rule 6 dit `request_new_run()` ou `level_active` suivant — ACs incohérents.
- **NB-CRD-5 [2 specialists agree]** : AC-CRD-39 perf gate 0.1 ms intestable CI (hérité r1 P-5). Variance ±2-5 ms → flaps permanents. AC fantôme.
- **NB-CRD-6 [Pillar 4 critical]** : asymétrie 5:1 viscérale — Player Fantasy claim non livré ET non retiré MVP. Adjudication CD r1 (livrer SFX/VFX MVP minimum OU retirer claim) non honorée. HUD r1 ne différencie pas pulse KILL vs SECRET. Boucle de renvoi Credit→Secret→Audio futurs.

**Path to APPROVED** : (1) amendement cosmétique Shop r2 propagation `BASE_UPGRADE_COST = 8` ~30 min ; (2) décision NB-CRD-6 Option A/B/C (1-3h) ; (3) r3 ciblée Credit GDD (~1h editorial NB-CRD-2/3/4/5) ; (4) re-review fresh 5-min lean → APPROVED → unlock `/create-epics credit-economy-system`.

**Specialist disagreements** : (DA-1) `kill_credit["grunt"]` safe range [1,1] vs [1,3] — adjudication maintenue [1,3] avec invariant runtime AC-CRD-16 reformulé ; (DA-2) AC-CRD-39 BLOCKING vs ADVISORY — adjudication BLOCKING dev hardware, ADVISORY CI si non-reproductible.

**Prior verdict resolved** : Designed r2 (review 2026-04-27) — re-review confirme partiel. r2 a fait travail substantiel sur autonomie système (B-1, B-6, B-7 exemplaires) mais propagation cross-GDD + Pillar 4 viscéral non honorés.
