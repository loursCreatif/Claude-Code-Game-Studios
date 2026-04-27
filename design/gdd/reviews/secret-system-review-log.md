# Secret System — Review Log

> Continuous log of all design reviews on `design/gdd/secret-system.md`.
> Each review entry summarizes verdict, scope, blocking items resolved/added.
> Detailed reports : `secret-system-review-r[N]-[date].md`.

---

## Review — 2026-04-27 — Verdict: NEEDS REVISION

**Scope signal** : S (Small — ciblage architectural cross-GDD, pas re-design)
**Reviewer** : game-designer (fresh session — aucune mémoire de la session de design productrice)
**Specialists** : none (solo mode auto-approve)
**Blocking items** : 3 | **Recommended** : 4 | **Nice-to-have** : 5
**Detailed report** : `secret-system-review-r1-2026-04-27.md`

**Summary** :

GDD r1 (779 lignes, 52 ACs effectifs, 10 OQ) — qualité architecturale exceptionnelle, Player Fantasy meilleure du studio. 8/8 sections + 5 bonus présentes. Pillars (Pillar 4 primaire + Pillar 1 + Pillar 3) intacts.

**3 BLOCKING** :

- **B-1 — Contrat Checkpoint unilateral** : Secret R-SEC-10 référence `checkpoint.get_collected_secrets() / restore_collected_secrets(ids)` mais Checkpoint GDD r1 (In Design) §Interactions ne liste pas Secret System ni ces verbes. AC-SEC-12 + AC-SEC-33 non-testables. Pipeline "secret survit à mort" (Pillar 3) non-fonctionnel. Verbe `restore_collected_secrets` ambigu directionellement — recommandation rename `inject_collected_secrets`.
- **B-2 — `instance_id` invalide pour persistance cross-étage** : R-SEC-06 + Tuning Knob G-1 utilisent `volume.get_instance_id()` comme clé, or Godot réassigne les ids au boot. Risque : comportement correct par hasard pour les nouveaux étages, faux positifs/négatifs sur respawn intra-étage si Level recharge la scène. R-SEC-12 admet implicitement la limitation MVP "session-only" mais sans documenter l'invariant requis (Level/VFX ne doit jamais `queue_free()` un volume pendant un run actif). Migration `uuid_export` Tier 2+ correcte mais MVP fragile sans invariant explicite.
- **B-3 — Tuning Knobs non data-driven** : 2 knobs runtime (`IDEMPOTENCE_KEY_STRATEGY`, `IGNORE_BODY_ENTERED_BEFORE_LEVEL_ACTIVE`) documentés sans référence à fichier `assets/data/` ou `.tres` ou `.gd` constants externe. Viole CLAUDE.md « Gameplay values must be data-driven (external config), never hardcoded ». Premier GDD du studio où la règle CLAUDE.md est BLOCKING (Enemy r1 N-2 l'avait signalé sans bloquer).

**Adjudications** : aucune (solo mode, reviewer seul).

**OQ résolutions r1** :
- OQ-CRD-1 (Credit) RESOLVED par Secret r1 (`secret_collected` SYNC confirmé).
- OQ-SEC-1 BLOCKED → BLOCKING B-1 (amendement Checkpoint r2 requis).
- OQ-SEC-2 DEFERRED Tier 2+ avec action MVP immédiate (R-SEC-16 invariant — couvert par B-2).
- OQ-SEC-3 DEFERRED Tier 2+ (pitch-shift par tier).
- OQ-SEC-4 RESOLVED option (c) bus dédié `SECRET_COLLECT` parented à SFX (amendement Audio r2.2 requis).
- OQ-SEC-5 RESOLVED MVP éteint complet (anti-Pillar 4 grayed-out).
- OQ-SEC-6 DEFERRED Tier 2+ (capability-aware glow).
- OQ-SEC-7 RECOMMENDED Sprint 1 (lint Level pré-build).
- OQ-SEC-8 RESOLVED partiel — coordination HUD r2 amendement (différenciation amplitude tween par SourceKind).
- OQ-SEC-9 / OQ-SEC-10 DEFERRED Tier 3.

**Path to APPROVED** : r2 amendment focalisé S (small) — 3 fixes BLOCKING + 4 RECOMMENDED batchables. Pre-impl 4 + polish 5 reportés.

**Prior verdict resolved** : First review.

---

## r2 Full Revision — 2026-04-27 — Verdict: Designed r2 (pending fresh re-review)

**Scope signal** : S (Small — focused fix pass, no new sections)
**Method** : `/design-system secret-system` solo auto-approve, targeted Edit on 3 BLOCKING (no full re-design of approved sections)
**Resolved** : 3 BLOCKING (B-1, B-2, B-3) — all paths to APPROVED unblocked.
**Deferred** : 4 RECOMMENDED items + 5 NICE-TO-HAVE items reported separately for next batch.

**Changes applied (file-level)** :

1. **Header** — Status `In Design (r2 — full revision)` ; review history line documents B-1..B-3 résolution one-line each.
2. **R-SEC-10** (B-1) — Interface Checkpoint clarifiée : 3 verbes nommés (`checkpoint.get_collected_secrets()` lecture pull, `Secret.inject_collected_secrets(ids)` push depuis Checkpoint, `Secret.get_collected_ids()` lecture par Checkpoint). Verbe `restore_collected_secrets` renommé `inject_collected_secrets` pour clarifier direction d'appel. Note **[GATE r2 B-1]** ajoutée — amendement Checkpoint r2 requis avant `/create-epics`.
3. **R-SEC-16** (B-2 — NEW) — Invariant instance_id stability documenté comme **pré-contrat externe** : Level/VFX/tout consumer interdit de `queue_free()` ou réinstancier `SecretCollectVolume_NN` pendant `_is_active == true`. Cas légitimes (state_changed MENU, request_scene_transition) explicités. Migration Tier 2+ `uuid_export` rend invariant caduc.
4. **§Interactions table** (B-1) — Row Checkpoint mise à jour avec 3 verbes nommés + flag [GATE].
5. **§Soft dependencies** (B-1) — Row Checkpoint mise à jour idem.
6. **§Provisional contracts** (B-1 + B-2) — Verbes Checkpoint listés ; gate B-1 explicite ; invariant R-SEC-16 référencé pour VFX anti-dep.
7. **§Gates pré-`/create-epics`** (B-1 + R-SEC-16 — NEW table) — 3 gates listés : Checkpoint r2 (B-1), Level r5 (R-SEC-16), VFX GDD futur (R-SEC-16).
8. **§Tuning Knobs runtime** (B-3) — Externalisation vers `src/gameplay/secret/secret_constants.gd` (pattern aligné `input_constants.gd`/`level_constants.gd` du studio). Snippet GDScript `class_name SecretConstants` exposé. Migration Tier 2+ vers `assets/data/secret_config.tres` documentée.
9. **AC-SEC-12** (B-1) — Conditioned to Checkpoint r2 amendment. Reformulation GIVEN explicite + statut `[BLOCKING | AUTO — pending Checkpoint r2 amendment]` + Pre-condition AC documentée (PENDING non-FAIL si gate non levée).
10. **AC-SEC-33** (B-1) — Verbe renommé `inject_collected_secrets` + conditioned to Checkpoint r2 amendment. Même statut PENDING.
11. **OQ-SEC-1** (B-1) — Reformulation complète : 3 verbes listés, gate B-1 explicite, statut [BLOCKING] préservé jusqu'à amendement Checkpoint r2.
12. **§Tableau récapitulatif ACs** (B-3 + N-1 review) — Recompte r2 : 53 ACs total (52 r1 effectifs + 1 nouveau AC-SEC-NEW r2 B-3 lint constants), 30 BLOCKING + 23 ADVISORY (recompte r1 corrigé via review N-1). 8 STATIC (7 r1 + 1 r2).
13. **AC-SEC-NEW** (B-3 — NEW) — Lints/Static lint constants externalization : grep statique `tests/static/secret_constants_lint_test.gd` vérifie qu'aucune valeur magique n'apparaît hardcodée dans `src/gameplay/secret/*.gd` hors `secret_constants.gd`. Conformité CLAUDE.md.

**Reportés batch séparé** :

- **4 RECOMMENDED** : R-1 gate formelle GSM r2, R-2 EC-SEC-11 propagation Credit r2 §Edge Cases, R-3 conditional clause AC-SEC-12 (déjà partiellement fait via B-1), R-4 ADR-0008 dans §Dependencies.
- **5 NICE-TO-HAVE** : N-1 comptage ACs cohérent (déjà partiellement fait via B-3 récap), N-2 reformulation F-SEC-2 cap théorique, N-3 flag `CONNECT_ONE_SHOT` body_entered explicite, N-4 hypothèse `request_scene_transition` repositionnement, N-5 Pillar 4 design test AC bonus.

**Prior verdict resolved** : NEEDS REVISION (review r1 2026-04-27) — 3 BLOCKING résolus.

**Cross-GDD propagation requise (post-r2)** :

| GDD | Amendement | Priorité | Bloque |
|-----|-----------|----------|--------|
| Checkpoint r2 | Ajouter Secret §Interactions + Published API 3 verbes (B-1 [GATE]) | BLOCKING | `/create-epics secret-system` |
| Level r5 | §Anti-dependencies "interdit `queue_free()` SecretCollectVolume_NN run actif" (R-SEC-16) | RECOMMENDED | Implémentation Level r5 |
| VFX GDD futur | Même invariant R-SEC-16 | RECOMMENDED | `/create-epics vfx-system` |
| Audio r2.2 | Bus `SECRET_COLLECT` parented SFX + handler secret_collected + sample spec (OQ-SEC-4) | RECOMMENDED | `/create-epics secret-system` |
| Credit r2 | EC `secret_node == null` dans §Edge Cases (R-2 review) | RECOMMENDED | Sprint 1 |
| HUD r2 | Différencier amplitude tween KILL vs SECRET par SourceKind (OQ-SEC-8) | RECOMMENDED | Avant impl HUD Rule 5 |

**Next** : fresh `/design-review secret-system` re-review session (parallel session, full mode) pour confirmer Designed r2 → APPROVED. Amendement Checkpoint r2 cosmetic ajout Secret §Interactions + Published API 3 verbes débloque le [GATE B-1]. Pré-impl + polish batch séparé après confirmation r2.
