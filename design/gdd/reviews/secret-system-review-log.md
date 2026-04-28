# Secret System — Review Log

> Continuous log of all design reviews on `design/gdd/secret-system.md`.
> Each review entry summarizes verdict, scope, blocking items resolved/added.
> Detailed reports : `secret-system-review-r[N]-[date].md`.

---

## r3 ciblée editorial — 2026-04-28 — Verdict: pending fresh `/design-review` lean re-pass

**Scope signal** : XS/S (editorial — reformulations + ajouts §Authoring + 4 nouveaux ACs)
**Authoring session** : `/design-system secret-system r3 ciblée` (solo auto-approve, scope-bounded 6 NB-SEC editorial)
**Specialists spawned** : none (solo mode + scope editorial pure — aucun redesign de règle ou formula, aucun ADR à amender)
**Resolution** : 6 NEW BLOCKING r2 → résolus | 0 RECOMMENDED | 0 NICE-TO-HAVE (déférés batch ultérieur)

### Fixes r3 appliqués (6 NB-SEC editorial)

| # | NB | Fix éditorial | Sections touchées | Nouveaux ACs |
|---|----|--------------- |-------------------|--------------|
| 1 | NB-SEC-1 | R-SEC-10 expliciter PULL canonique MVP / PUSH Tier 2+ avec règle d'union (jamais surécrasement) ; clarification ownership purge `request_new_run` (Secret purge `_collected_secret_ids`, Checkpoint purge son snapshot) — résout aussi NR-SEC-4 par cascade | R-SEC-10 (réécrite) | AC-SEC-NB-1 BLOCKING AUTO (union pull+push) |
| 2 | NB-SEC-2 | R-SEC-13 : ajout détection runtime `CollisionShape3D.disabled = true` → `push_warning` + connexion quand même (jamais skip) — défense Pillar 4 silencieuse même sans lint Level (Sprint 1 OQ-SEC-7) | R-SEC-13 (5e bullet ajouté) | AC-SEC-NB-2 BLOCKING AUTO (push_warning runtime) + AC-SEC-NB-2-LINT ADVISORY STATIC (lint Level pré-build) |
| 3 | NB-SEC-3 | AC-SEC-25 reformulé : retrait assertion `is_physics_processing()` (faux pass garanti GUT headless) ; remplacement par espion d'ordre d'appel SYNC dans le call stack ; bridge ADVISORY MANUAL pour la garantie main-thread physics non testable headless | AC-SEC-25 (réécrite) | AC-SEC-NB-3-MANUAL ADVISORY MANUAL (test scène réelle) |
| 4 | NB-SEC-4 | AC-SEC-18 reformulé : retrait simulation overlap synchrone (non viable headless) ; remplacement par test ordre déconnexion-puis-connexion via call_recorder spy ; bridge ADVISORY MANUAL pour overlap réel scène | AC-SEC-18 (réécrite) | AC-SEC-NB-4-MANUAL ADVISORY MANUAL (overlap scène réelle) |
| 5 | NB-SEC-5 | §Tuning Knobs §Authoring : nouvelle section "Règles d'authoring distribution + défi de mouvement" — Règle A distribution : `MAX_SECRETS_PER_ROOM=1`, `MIN_SECRETS_OUTSIDE_NOMINAL_PATH≥1`, `DISTRIBUTION_RECOMMENDED=1 début/1-2 médian/1 fin`, `MIN_SECRETS_REQUIRING_FUTURE_CAPABILITY≥1` (promesse de retour) | §Tuning Knobs §Authoring (nouvelle section avant §Mapping) | AC-SEC-NB-5 ADVISORY STATIC (lint Level Sprint 1) |
| 6 | NB-SEC-6 | §Tuning Knobs §Authoring : Règle B défi de mouvement obligatoire — `REQUIRED_MOVEMENT_CHALLENGE_TYPE` tag obligatoire `{height_gap, wall_gap, timed_sequence, multi_element}` ; cohérences tier=1 height_gap + tier∈{2,3} navmesh sans capability ne connecte pas | §Tuning Knobs §Authoring (Règle B même section que NB-SEC-5) | AC-SEC-NB-6 ADVISORY STATIC (lint Level Sprint 1) |

### Counts r2 → r3 ACs

- Total : 53 → **60** (+7 nouveaux NB)
- BLOCKING : 30 → **33** (+3 ; AC-SEC-NB-1 + AC-SEC-NB-2 + reformulations BLOCKING 18/25 conservées)
- ADVISORY : 23 → **27** (+4 ; AC-SEC-NB-2-LINT + AC-SEC-NB-3-MANUAL + AC-SEC-NB-4-MANUAL + AC-SEC-NB-5 + AC-SEC-NB-6)
- AUTO : 27 → **30** (+3) | MANUAL : 9 → **11** (+2) | STATIC : 8 → **11** (+3)

### Items review r2 NON adressés r3 (déférés)

- **NR-SEC-1..NR-SEC-13** (13 RECOMMENDED) : déférés batch ultérieur ou stories implém — non bloquants pour `/create-epics`. Notables résolus par cascade : NR-SEC-3 (Audio r2.2 promotion gate) **LIVRÉE** par NB-CRD-6 Option A 2026-04-28 commit `731c64c` ; NR-SEC-4 (ownership purge `request_new_run`) **résolu r3** par cascade dans R-SEC-10 (clarification écrite dernière phrase). NR-SEC-10 (renommer `AC-SEC-NEW` → `AC-SEC-53`) éditorial pur, déféré.
- **NN-SEC-1..NN-SEC-4** (4 NICE-TO-HAVE) : polish, déférés post-`/create-epics`.

### Path to APPROVED

1. ✅ r3 ciblée editorial Secret GDD livrée (cette entrée) — ~2h editorial conforme estimation r2.
2. **Next** : fresh `/design-review` lean re-pass single-session 10-15 min (mémoire vide reviewer) sur `design/gdd/secret-system.md` r3 → APPROVED → unlock `/create-epics secret-system`.

### Files touched (3)

1. `design/gdd/secret-system.md` (header bump r2 → r3 + R-SEC-10 réécrite + R-SEC-13 5e bullet + AC-SEC-25 réécrite + AC-SEC-18 réécrite + §Tuning Knobs §Authoring nouvelle section Règles A + B + tableau récap r3 + Groupe NB nouveaux ACs).
2. `design/gdd/reviews/secret-system-review-log.md` (NEW entry top — cette entrée r3).
3. `design/gdd/systems-index.md` (Secret row status r2 NEEDS REVISION → r3 ciblée pending fresh re-pass).

**Solo gates** : CD-GDD-ALIGN skipped (`production/review-mode.txt` = solo).

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

---

## Review — 2026-04-28 — Verdict: NEEDS REVISION (r3 ciblée)

**Scope signal** : XS/S
**Method** : `/design-review secret-system --depth full` fresh session (4 spécialistes adversariaux parallèles + senior synthèse main reviewer)
**Specialists** : game-designer + systems-designer + qa-lead + level-designer
**Blocking items** : 6 NEW BLOCKING | **Recommended** : 13 NEW | **Nice-to-have** : 4 NEW
**Detailed report** : `secret-system-review-r2-2026-04-28.md`

**Summary** :

Re-review fresh du r2 post-revision. **Résolution r1 vérifiée : 2/3 complète (B-2, B-3 exemplaires), 1/3 partielle (B-1 ambiguïté pull/push résiduelle)**. r2 architecturalement plus mature que r1.

**6 NEW BLOCKING** :
- **NB-SEC-1 [2 specialists agree]** : ambiguïté pull/push hydratation Checkpoint — R-SEC-10 décrit deux mécanismes simultanés (`checkpoint.get_collected_secrets()` PULL ligne 132 + `Secret.inject_collected_secrets(ids)` PUSH ligne 133) sans précédence définie. AC-SEC-12 + AC-SEC-33 testent chemins indépendants → risque double-peuplement.
- **NB-SEC-2 [4 specialists agree]** : `CollisionShape3D.disabled = true` non couvert (héritage r1 EC-SEC-MISSING-1) — silent Pillar 4 failure. Volume conforme aux knobs mais inerte. Convergence forte 4/4.
- **NB-SEC-3 [QA]** : AC-SEC-25 assertion `is_physics_processing()` invalide en GUT headless — toujours false → faux pass garanti.
- **NB-SEC-4 [QA]** : AC-SEC-18 mécanisme overlap non viable headless (sans scene tree, callbacks séquentiels jamais en vrai overlap) → faux pass systématique.
- **NB-SEC-5 [Level-designer]** : distribution spatiale intra-étage non contrainte — Level F7 contraint nombre total mais pas distribution. Configurations frontload/cluster conformes au GDD mais cassent Pillar 4.
- **NB-SEC-6 [Level-designer]** : `MIN_LURE_TO_VOLUME_DISTANCE` mesure distance euclidienne, pas défi de traversée. Aucun knob ne garantit obstacle de mouvement entre lure et volume — viole Player Fantasy "chaque cachette est un défi d'exécution".

**Path to APPROVED** : r3 ciblée Secret GDD ~2h editorial (NB-SEC-1 R-SEC-10 PULL canonique MVP / PUSH Tier 2+ ; NB-SEC-2 R-SEC-13 push_warning défensif ; NB-SEC-3+4 reformulation ACs ; NB-SEC-5+6 §Tuning Knobs §Authoring 2-3 nouvelles règles + AC STATIC) → re-review fresh 5-min lean → APPROVED → unlock `/create-epics secret-system`.

**Specialist disagreements** : (DA-SEC-1) NB-SEC-2 BLOCKING vs RECOMMENDED — adjudication BLOCKING (OQ-SEC-7 lint Level Sprint 1, MVP sans lint = ship en prod) ; (DA-SEC-2) NB-SEC-5/6 Secret GDD vs Level GDD — adjudication Secret GDD §Tuning Knobs §Authoring (proximité authoring secret) ; (DA-SEC-3) NB-SEC-1 BLOCKING vs RECOMMENDED — adjudication BLOCKING (ambiguïté écrite explicitement doit être tranchée explicitement).

**Prior verdict resolved** : Designed r2 (review 2026-04-27) — re-review confirme partiel. R-SEC-16 + secret_constants.gd exemplaires. Pull/push Checkpoint résolution introduit nouvelle ambiguïté à trancher r3.
