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
