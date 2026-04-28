# Upgrade System — Review Report r1 SUPPLEMENTAL — 2026-04-27

> **Source** : `/design-review upgrade-system` (parallel session, full mode, fresh)
> **Status** : COMPLEMENTARY to `upgrade-system-review-r1-2026-04-27.md` (NOT a replacement)
> **Verdict** : NEEDS REVISION (cohérent r1 verdict initial) — 12 BLOCKING + 17 RECOMMENDED + 8 NICE-TO-HAVE identifiés
> **Conflit r1 ↔ r1-supplemental** : r1.1 cosmetic fixes appliqués par session parallèle ANTÉRIEURE PRÉSERVÉS (8 changes). r1.2 supplemental ajoute UNIQUEMENT des amendements non-conflictuels (10 changes appliqués en r1.2 + 7 structural BLOCKING r1 inchangés en attente r2 design session distincte).

---

## Contexte multi-session

Cette review a été exécutée en **session parallèle** au moment où une autre session Claude Code finissait elle-même un `/design-review upgrade-system` (r1 → r1.1). Les deux sessions ont opéré en isolation — différents specialists adversariaux, différents creative-directors comme synthétiseurs.

| Aspect | Session r1 (antérieure) | Session r1-supplemental (cette review) |
|--------|-------------------------|----------------------------------------|
| **Specialists** | game-designer, systems-designer, qa-lead, godot-specialist | game-designer, systems-designer, qa-lead, godot-specialist + **economy-designer** (5e) |
| **Findings totaux** | 15 BLOCKING + 18 RECOMMENDED + 7 NICE-TO-HAVE | 12 BLOCKING + 17 RECOMMENDED + 8 NICE-TO-HAVE |
| **Cosmetic fixes appliqués** | 8 (r1.1) | 10 supplémentaires (r1.2) — non-conflictuels avec r1.1 |
| **Adjudications creative-director divergentes** | EC-UPG-14 wins ; helper `_apply_flag()` ; reorder autoload pos 2 optionnel | R-UPG-4 wins (initial) → ré-aligné sur r1.1 EC-UPG-14 wins (preserved) ; pas de reorder (cf. ADR-0007 D-9) ; OWNED card Shop suffit Pillar 2 |
| **Findings UNIQUES** | R-UPG-12 reframe Hollow Knight ; R-UPG-3 ADR catalogue ; F-UPG-2 save bloat ; AC-UPG-22 coercion silencieuse | EC-UPG-32 `Engine.set_singleton` API fix ; F-UPG-3 bidirectionnel ; F-UPG-4 retrait `can_secret_radar` Pillar 4 ; AC-UPG-12 grep+wallclock ; AC-UPG-3 contrainte stricte ; AC-UPG-34/35/36 word-boundary ; AC-UPG-37 scope concret + AC-UPG-37-bis playtest novice ; affordability marge 25 cr ; no-confirm Pillar 1 |

**Stratégie adoptée** : honorer r1.1 + appliquer SEULEMENT les findings UNIQUES de r1-supplemental qui ne contredisent pas les adjudications r1.1. Les conflits explicites (EC-UPG-14, set() helper) restent reportés à la r2 design session distincte selon plan r1.1.

---

## Specialists et adversariats

5 specialists ont été spawned en parallèle (8-15 min wall-clock chacun) :

1. **game-designer** — anchor Player Fantasy B.1/B.2/B.3 + pillar alignment
2. **systems-designer** — formula boundary tests F-UPG-1/2/3/4 + contradictions internes
3. **qa-lead** — review 43 ACs (testabilité, granularité, sub-spec)
4. **economy-designer** — F-UPG-1 délégation Credit + intégration Shop + catalog ownership
5. **godot-specialist** — Godot 4.6 specifics (autoload, const Dict, Object.set, register_singleton, hot-reload)

Puis **creative-director** comme senior reviewer (synthèse + 3 adjudications clés).

---

## Adjudications creative-director (r1-supplemental session)

**A1. R-UPG-4 vs EC-UPG-14 — sémantique idempotence vs re-sync** : ma synthèse initiale recommandait **R-UPG-4 wins (idempotence pure)**. Découverte post-synthèse : la session parallèle r1.1 a tranché **EC-UPG-14 wins** (re-sync forcé `not _owned.has(id) OR not get(flag_name)` avec assert post-set). **Décision r1-supplemental** : ré-aligner sur r1.1 (EC-UPG-14 wins) pour éviter conflit multi-session. La résolution complète reste reportée à r2 design session distincte.

**A2. Ordre autoload Upgrade ↔ GSM** : godot-specialist signalait que EC-UPG-2 r1 affirme "UpgradeSystem._ready() est terminé avant que GSM s'exécute" alors que R-UPG-11 met GSM en position 2 et Upgrade en position 5 (donc l'inverse). **Décision r1-supplemental** : ne pas reorder l'autoload (préserve ADR-0007 D-1). Reformuler EC-UPG-2 pour expliciter que la garantie repose sur **ADR-0007 D-9** : GSM init MENU au boot sans transition synchrone, donc aucun risque réel même avec l'ordre actuel.

**A3. Feedback premier usage post-achat (Pillar 1 vs Pillar 2)** : game-designer flagaait que sans feedback in-world au premier double-jump réussi post-unlock, un joueur novice peut traverser plusieurs salles sans faire le lien. **Décision r1-supplemental** : pas de feedback in-world supplémentaire (Pillar 1 prime). La carte OWNED dans le Shop (cyan désaturé, pulse, déjà spec Shop r1 R-SHP-9/10) + le moveset visible suffisent. Mais ajouter **AC-UPG-37-bis playtest novice** pour valider que les playtesters comprennent l'unlock en moins de 30 secondes post-shop sans aide visuelle. Si playtest échoue, réévaluer.

---

## Findings UNIQUES r1-supplemental (10 amendements appliqués + 7 reportés r2)

### Appliqués r1.2 (10 amendements éditoriaux non-conflictuels)

| # | Item | Section/AC | Source specialist | Statut |
|---|------|------------|-------------------|--------|
| 1 | `Engine.register_singleton` fix API | EC-UPG-32 | godot-specialist | ✅ Appliqué r1.2 |
| 2 | Invariant bidirectionnel | F-UPG-3 | systems-designer + economy-designer | ✅ Appliqué r1.2 |
| 3 | Retrait `can_secret_radar` (Pillar 4 violation) | F-UPG-4 + Tuning Knobs + Anti-deps Secret | game-designer + creative-director | ✅ Appliqué r1.2 |
| 4 | Reformulation ordre autoload + ADR-0007 D-9 reference | EC-UPG-2 | godot-specialist | ✅ Appliqué r1.2 |
| 5 | Contrainte stricte vs ordre canonique | AC-UPG-3 + AC-UPG-3-bis | qa-lead | ✅ Appliqué r1.2 |
| 6 | Grep statique await/yield + wall-clock | AC-UPG-12 + AC-UPG-12-bis | qa-lead + godot-specialist | ✅ Appliqué r1.2 |
| 7 | Word-boundary + filtre commentaires | AC-UPG-34/35/36 | qa-lead | ✅ Appliqué r1.2 |
| 8 | Scope concret + playtest novice | AC-UPG-37 + AC-UPG-37-bis | game-designer + qa-lead | ✅ Appliqué r1.2 |
| 9 | No-confirm = intentionnel anti-friction Pillar 1 | R-UPG-12 corollaire | economy-designer + creative-director | ✅ Appliqué r1.2 |
| 10 | 3 nouvelles OQ-UPG-11/12/13 | OQ section | economy-designer + game-designer | ✅ Appliqué r1.2 |

### Reportés à r2 design session distincte (7 structural BLOCKING r1 inchangés)

| # | Item | Source r1 | Statut |
|---|------|-----------|--------|
| B-1 | R-UPG-12 reframe (anti-pilier "NOT skill tree" + Ghostrunner ref, retirer Hollow Knight) | r1 game-designer | ⏳ R2 design session |
| B-2 | R-UPG-3 retirer requirement ADR catalogue (F-UPG-3 CI suffit) | r1 systems-designer | ⏳ R2 design session |
| B-3 | Helper `_apply_flag()` design + R-UPG-4 step 4 amendement | r1 godot-specialist | ⏳ R2 design session |
| B-4 | EC-UPG-14 reconciliation R-UPG-4 + AC ajouté pour resync test | r1 systems-designer | ⏳ R2 design session |
| B-6 | Save bloat defense `owned_array.size() > MAX_CATALOG_SIZE × 2 → tronquer + warning` | r1 systems-designer | ⏳ R2 design session |
| B-8 | F-UPG-4 cross-ref EC-UPG-9 + note "vars must be declared before _CATALOG add" | r1 godot-specialist | ⏳ R2 design session |
| B-9-15 | ACs rewrite session (qa-lead + godot-specialist) | r1 qa-lead | ⏳ R2 design session |

### Cross-system flagged (hors scope Upgrade r2)

- **OQ-UPG-11 NEW** — Affordability marge 25 cr → cross-GDD coordination Credit r2 + Shop r2 (economy-designer)
- **B-5 r1** — F-UPG-1 bound check `n >= 0` documentation côté Credit r3 amendement ou /consistency-check

---

## Convergences cross-specialist (r1-supplemental seul)

3 axes où ≥2 specialists r1-supplemental ont convergé sur le même finding :

1. **F-UPG-3 unidirectionnel** : systems-designer + economy-designer ont indépendamment flagué que l'invariant ne couvre que Shop ⊆ Upgrade, manquant Upgrade ⊆ Shop. Drift silencieux possible. Résolu r1.2.

2. **`Object.set()` no-op silencieux + `const Dictionary` faux immutable** : godot-specialist + qa-lead convergents. Le test AC-UPG-6 r1 prétend "GDScript lève une erreur de compilation/runtime" mais c'est faux : `const Dictionary` rend la référence const mais autorise mutation interne `_CATALOG[k] = v`. Résolution : `make_read_only()` dans `_ready()`. **Reporté à r1.1 + r2 design session (B-3 + B-15)**.

3. **EC-UPG-14 vs R-UPG-4 contradiction** : game-designer + systems-designer + economy-designer + godot-specialist tous convergent sur l'incohérence. **Adjudication r1.1 (session antérieure) tranche EC-UPG-14 wins** ; r1-supplemental ré-aligne pour éviter conflit. Résolution finale en r2 design session distincte.

---

## Verdict final r1-supplemental

**NEEDS REVISION** (cohérent verdict r1) — pas de promotion à APPROVED. Les 10 amendements r1.2 supplemental sont éditoriaux et closent une partie des dettes r1 RECOMMENDED + ajoutent 3 OQ. Mais 7 structural BLOCKING r1 + 7 ACs rewrite restent en attente de la r2 design session distincte (≈3-4h focalisée selon plan r1.1).

**Path to APPROVED** : r2 design session distincte address 7 structural BLOCKING r1 + 7 ACs rewrite + valide 3 nouvelles OQ-UPG-11/12/13. Re-review fresh r3 attendue avant `/create-epics upgrade-system` Sprint 1.

---

## Files touched r1.2 supplemental (3)

1. `design/gdd/upgrade-system.md` — 10 amendements éditoriaux (header status r1.1→r1.2 ; EC-UPG-32 ; F-UPG-3 ; F-UPG-4 ; Tuning Knobs ; Anti-deps Secret ; EC-UPG-2 ; AC-UPG-3 + 3-bis ; AC-UPG-12 + 12-bis ; AC-UPG-34/35/36 ; AC-UPG-37 + 37-bis ; R-UPG-12 corollaire ; OQ-UPG-11/12/13 NEW)
2. `design/gdd/reviews/upgrade-system-review-r1-supplemental-2026-04-27.md` — NEW (ce fichier)
3. `design/gdd/reviews/upgrade-system-review-log.md` — append entry r1-supplemental

---

## Adjudications creative-director r1-supplemental (5 décisions explicites + 3 alignées r1.1)

1. **R-UPG-4 vs EC-UPG-14** : ALIGNÉ r1.1 (EC-UPG-14 wins). Pas d'override.
2. **Reorder autoload** : NON-REORDER. EC-UPG-2 reformulé pour clarifier ADR-0007 D-9 garantit la sécurité même avec ordre actuel.
3. **Pillar 2 feedback premier usage** : Pas de feedback in-world. AC-UPG-37-bis ajouté pour validation playtest novice.
4. **`can_secret_radar` Pillar 4** : RETIRÉ du catalog Tier 2+ par défaut. Réintégration conditionnelle via revalidation Pillar 4 explicite.
5. **No-confirm achat** : DOCUMENTÉ intentionnel anti-friction Pillar 1 dans R-UPG-12 corollaire.
6. **Affordability marge 25 cr** : FLAGGÉ en OQ-UPG-11 NEW (cross-GDD coord Credit/Shop). Pas de modification unilatérale des coûts depuis Upgrade.
7. **Helper `_apply_flag()` (B-3 r1)** : ALIGNÉ r1.1 (reporté r2 design session distincte).
8. **R-UPG-12 reframe Hollow Knight (B-1 r1)** : ALIGNÉ r1.1 (reporté r2 design session distincte).

---

**Prior verdict resolved** : First review (parallel session ; r1 antérieure documentée séparément `upgrade-system-review-r1-2026-04-27.md`).
