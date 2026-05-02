# Credit Economy System — Review r1 — 2026-04-27

> **Reviewer** : main session (fresh, 4 specialists adversarial + creative-director synthèse)
> **Review mode** : solo (`production/review-mode.txt` = "solo")
> **GDD cible** : `design/gdd/credit-economy-system.md` — In Design r1 — 596 lignes
> **Date** : 2026-04-27
> **CD-GDD-ALIGN gate** : skipped — solo mode
> **Specialists consultés** : economy-designer, qa-lead, game-designer, systems-designer, creative-director (synthèse senior)

---

## 1. Verdict Global

**NEEDS REVISION**

Credit r1 est un GDD solide en surface (596 lignes, 49 ACs, 9 OQ structurées) avec **8/8 sections** présentes et un niveau de précision implémentable comparable à Secret r1 / Shop r1. Les **pillars (FLOW + PROGRESSION SE VOIT + SECRETS)** restent intacts ; la dette est tactique, pas stratégique. Cependant, la review adversariale identifie **7 ship-blocking** issues — la plupart liées à la **coïncidence de design** : Credit r1 a été livré le même jour que Shop r1, HUD r1, Secret r1, ce qui a créé des contradictions cross-GDD sur la première synthèse multi-systèmes. Ces problèmes sont fixables en **<1 jour de revision r2** focalisée, sans nouvelle ADR.

**Adjudication décisive** (creative-director) :
- **Rule 7 multi-kill batching** : `BATCH_MULTI_KILL_EMIT = true` au MVP par défaut — Pillar 1 FLOW > analytics granularité Tier 2+. Game-designer overrules GDD r1.
- **Asymétrie 5:1 viscérale** : 1 SFX/VFX différenciés MVP minimum, sinon retirer claim Player Fantasy + North Star.

---

## 2. Scope Signal

- **Review mode** : solo (CD-GDD-ALIGN skipped)
- **Specialists consultés** : 4 adversariaux + 1 senior synthèse
- **Ship-blocking items** : 7
- **Pre-implementation items** : 10
- **Polish items** : 9
- **Scope estimation** : **M** (Medium) — un système data-pure, 4 formules, 6 dépendances directes, <1 jour r2 amendment

---

## 3. Completeness Check

### 8 sections obligatoires

| Section | Présente | Qualité | Notes |
|---------|----------|---------|-------|
| 1. Overview | ✅ | Excellente | Scope clair, "data-pure autoload" bien positionné, North Star ligne 31 (mais voir Polish #18 — "ticker" vs "odomètre") |
| 2. Player Fantasy | ✅ | Très bonne | 5 paragraphes denses, anti-fantasy explicite (lignes 28-30), références concurrentielles précises (Ghostrunner gems / Hollow Knight geo / Hades darkness). **Lacune** : asymétrie 5:1 "viscérale" (ligne 27) non livrée MVP côté audio (voir Pre-impl #8) |
| 3. Detailed Rules | ✅ | Très bonne | 13 rules, States/Transitions table propre, Interactions table avec 6 systèmes. **Contradiction interne** : Rule 11 hydratation ambiguë premier PLAYING vs tout PLAYING (Pre-impl #10) |
| 4. Formulas | ✅ | Bonne | F-CRD-1/2/3/4 avec variables, worked examples, validation économique. **Bug** : sanity check ligne 370 cassé à N=8 (Ship-blocking #4) |
| 5. Edge Cases | ✅ | Bonne | 16 EC runtime. **Gaps** : late spawns (#17), checkpoint purge (#6), race boot AC (#7) |
| 6. Dependencies | ✅ | Très bonne | Hard/Soft/Cousins/Bidirectional check structurés. **Stale** : Shop/HUD/Secret listés "Not Started" alors que Designed r1 le même jour (cosmétique) |
| 7. Tuning Knobs | ✅ | Très bonne | 5 knobs MVP + 5 latents Tier 2+. **Risque** : `kill_credit["grunt"]` safe range [1,3] casse Pillar 4 si tuner passe à 2 (Pre-impl #15) |
| 8. Acceptance Criteria | ✅ | Bonne distribution mais classification | 49 ACs, 48 BLOCKING + 1 ADVISORY. **Misclassification** : 6 ACs Lints/Static mal classés Logic BLOCKING (Ship-blocking #5) |

### Sections bonus

- **Visual/Audio Requirements** ✅ — bien fait, mais contradiction tween SPEND_SHOP avec HUD r1 (Ship-blocking #3)
- **UI Requirements** ✅ — délégation HUD claire, contrat ligne 425-441 cohérent
- **Cross-References** ✅ — table exhaustive avec types de dépendance (State trigger / Rule dependency / Data dependency / Ownership handoff)

---

## 4. Dependency Graph

### Hard dependencies

| Système | Status | Référencé dans | Verdict |
|---------|--------|----------------|---------|
| Enemy System | Designed r1 ✅ | Rule 5, F-CRD-1, registry `grunt` | OK — bidirectional check confirmé Enemy ligne 167+312 |
| Game State Manager | APPROVED r1 ✅ | Rule 10/11/12, ADR-0007 D-10 | OK |
| Save/Load System | Not Started ❌ | Rule 11/12, EC-CRD-8 | **Bloqueur Sprint 1** documenté — Save/Load doit être designé MVP |
| Shop System | **Designed r1** ✅ (stale dans Credit GDD) | Rule 4, R-SHP-6 confirme `try_spend` SYNC atomique | **OQ-CRD-2 RESOLVED** — voir amendement r2 |

### Soft dependencies

| Système | Status | Référencé dans | Verdict |
|---------|--------|----------------|---------|
| Secret System | **Designed r1** ✅ (stale dans Credit GDD) | Rule 9, R-SEC-08 confirme `secret_collected(node, tier: int)` | **OQ-CRD-1 RESOLVED** — voir amendement r2 |
| HUD System | **Designed r1** ✅ (stale dans Credit GDD) | UI Requirements §J, R-6 | **CONTRADICTION détectée** : Credit GDD ligne 384 spec tween HUD 200-400 ms, HUD r1 R-6 délègue à Shop (hard-set silencieux) |
| Audio System | APPROVED r2.1 ✅ | §Audio | OK — couplage minimal MVP |

---

## 5. Findings — Ship-Blocking (7)

### B-1 [game-designer] Rule 7 multi-kill batching default

> Inverser default `BATCH_MULTI_KILL_EMIT` à `true` au MVP. 3 emits séquentiels en 16.6 ms = imperceptible/saturation, viole Pillar 1 FLOW. Granularité analytics Tier 2+ doit céder au FLOW joueur.

**Décision creative-director (adjudication)** : pillar-driven non-négociable. Rule 7 doit être réécrite : single emit `credits_changed(N+3, +3, KILL)` MVP par défaut. Granularité 3 emits déférée à Tier 2+ avec knob `BATCH_MULTI_KILL_EMIT = false` activable post-playtest si analytics requise.

**Impact GDD** : Rule 7 + AC-CRD-08 + AC-CRD-31 + EC-CRD-5 + Tuning Knob `BATCH_MULTI_KILL_EMIT` à amender.

### B-2 [game-designer + economy-designer] Combat-only soft-lock

> F-CRD-4 worked example étage 1 combat-only = 8 cr < 20 cr upgrade n=0. Punition playstyle déguisée en "incitation à explorer". Pillar 2 ("la progression se voit") cassé pour combat-focused players sur 2-3 sessions.

**Options** :
- (A) `BASE_UPGRADE_COST` à 8-10 cr → première upgrade atteignable en 1 session combat-only (préféré creative-director).
- (B) Feedback partiel : barre progression vers upgrade visible même sans achat (Pillar 2 partiel mais préserve coût Y=85 sanity).

**Impact GDD** : F-CRD-3 table MVP + Tuning Knob safe range + F-CRD-4 worked examples + AC-CRD-16 sanity ratio.

### B-3 [game-designer + main] Contradiction tween SPEND_SHOP

> Credit GDD ligne 384 spec "HUD counter tween 200-400 ms" pour `delta < 0, SPEND_SHOP`. HUD r1 R-6 spec hard-set silencieux côté HUD, Shop owns le tween 300 ms.

**Décision** : HUD r1 (designed plus tard, ownership-clear) prime. Credit GDD doit retirer durées de tween de §Visual ligne 384 et déléguer ownership UI à HUD GDD.

**Impact GDD** : §Visual table ligne 379-384 — colonne "VFX requirement" → "voir HUD GDD R-6".

### B-4 [economy-designer] F-CRD-3 sanity check ligne 370 cassé à N=8

> Formule `BASE_UPGRADE_COST + TIER_COST_STEP × (N_UPGRADES - 1) ≤ session_yield × 5` teste seulement la dernière upgrade (160 cr ≤ 165-260 cr ✅) mais pas le coût cumulatif (720 cr → 22 sessions étage 1 normal pour tout acheter).

**Fix** : ajouter check cumulatif `Σ cost_n ≤ session_yield × N_SESSIONS_TARGET` où `N_SESSIONS_TARGET = 8-10` (Pillar 2 — la progression doit aboutir avant fatigue).

**Impact GDD** : §Cross-tuning interactions ligne 367-371 + worked example Tier 2+ N=8.

### B-5 [qa-lead] 6 ACs Lints/Static mal classés Logic BLOCKING

> AC-CRD-20, 21, 32, 42, 44, 45 sont des greps source / lint statiques, pas des tests GUT runtime.

**Fix** : créer `tests/static/credit_economy_lint_test.gd` parallèle à `movement_lint_test.gd`. Reclasser dans matrice Test Coverage : ajouter ligne "Lints / Static" séparée. Recompte : **42 Logic/Integration/Perf BLOCKING + 6 Lints/Static BLOCKING + 1 ADVISORY**.

**Impact GDD** : §Acceptance Criteria — réorganiser sous-thèmes + Test Coverage Matrix ligne 561-578. Fusionner AC-CRD-20+21 (doublon `await` dans `try_spend`). Supprimer AC-CRD-32 (doublon AC-CRD-42).

### B-6 [systems-designer] Rule 6 `_credited_this_run` purge sur checkpoint intra-étage

> Pas spec'd : réinstanciation vs state-restore de l'ennemi non documenté côté Level System. Risque double-crédit ou dedup faux-positif. Aucun AC ne couvre ce scénario.

**Fix** : Rule 6 doit préciser le pattern Level (state-restore via `_restore_from_snapshot` confirmé par Enemy GDD EC-ENM-11). Ajouter AC-CRD-50 (numérotation continue) couvrant checkpoint respawn intra-étage.

**Impact GDD** : Rule 6 + EC-CRD-7/16 + nouveau AC-CRD.

### B-7 [systems-designer] Race boot `level_active` vs `state_changed(PLAYING)`

> EC-CRD-11 mentionne le race mais `_on_level_active()` peut connecter signaux ennemis avant hydratation, ou skip connexion si `_is_hydrated == false` → niveau entier sans crédits. Spec explicite + AC manquant.

**Fix** : Rule 5 doit clarifier — connexion aux ennemis se fait à `level_active` indépendamment de `_is_hydrated`. Le guard `_is_hydrated` rejette les *signaux reçus*, pas les *connexions établies*. Ajouter AC-CRD-51 race boot.

**Impact GDD** : Rule 5 + Rule 11 + EC-CRD-11 + nouveau AC-CRD.

---

## 6. Findings — Pre-Implementation (10)

| # | Source | Item | Action |
|---|--------|------|--------|
| P-1 | game-designer | Asymétrie 5:1 viscérale non livrée MVP (audio identique kill vs secret) | Soit imposer 1 SFX minimal Credit MVP (pitch-shift sur clac), soit rétrograder claim ligne 27/31 |
| P-2 | game-designer | ROOM_CLEAR_BONUS dans enum réservé = anti-pattern Pillar 4 documenté sans clôture | Retirer de `SourceKind` MVP (Rule 13), déplacer en OQ-CRD-4 uniquement |
| P-3 | game-designer | Rule 11 ambiguïté hydratation premier PLAYING vs tout PLAYING | Spec explicite : `_on_state_changed(PLAYING)` n'hydrate que si `_is_hydrated == false` |
| P-4 | qa-lead | AC-CRD-29 mécanisme GUT ambigu | Préciser : appel direct `_physics_process(delta)` + flag booléen lambda |
| P-5 | qa-lead | AC-CRD-39 perf gate 0.1 ms irréaliste sur CI (variance ±2-5 ms) | Reformuler `< 1 ms` médiane sur N=100, exclure CI ou marquer ADVISORY |
| P-6 | qa-lead | AC-CRD-46 "même frame perceptible" invérifiable humain 60 fps | Reformuler sur binding HUD testable (intégration HUD + Credit signal spy) |
| P-7 | qa-lead | Promouvoir ACs provisoires post Shop r1 + Secret r1 | AC-CRD-12..16 (Secret) + AC-CRD-17..21 (Shop) → plus PROVISIONAL |
| P-8 | economy-designer | Ratio 5:1 brisable par knob `kill_credit["grunt"]` ∈ [1,3] | Restreindre safe range à [1, 1] OU AC-CRD-16 reformulé indépendamment |
| P-9 | economy-designer | Anti-grinding non enforced (`total_credits` uncapped) | Documenter explicitement comme "promesse non-enforced MVP, dépend du level design" — OQ-CRD-3 reste Tier 2+ |
| P-10 | systems-designer | Rule 5 late spawns dynamiques non couverts | Documenter contrainte MVP "tous les ennemis présents au `level_active`" + assert debug + ajouter OQ-CRD-10 EventBus Tier 2+ |

---

## 7. Findings — Polish (9)

| # | Source | Item |
|---|--------|------|
| N-1 | game-designer | North Star ligne 31 "ticker silencieux" → "odomètre permanent" (cohérence métaphorique avec ligne 25) |
| N-2 | economy-designer | tier=0 / tier=99 silent ignore → `push_error` debug, `push_warning` release |
| N-3 | economy-designer | Dictionary `_credited_this_run` instance_id reuse risk → garde-fou défensif |
| N-4 | qa-lead | AC-CRD-32/42 doublon → supprimer 32, garder 42 reclassé Lints/Static |
| N-5 | qa-lead | AC-CRD-15 push_warning non interceptable GUT → reformuler comportement observable seul |
| N-6 | qa-lead | AC-CRD-11 doublon Combat → reformuler sur défense dedup côté Credit |
| N-7 | qa-lead | AC-CRD-04 mécanisme "journal" trompeur → clarifier inline test pattern |
| N-8 | systems-designer | Rule 12 PAUSED→MENU non explicitement couvert → ajouter mention handler state-agnostic |
| N-9 | systems-designer | EC-CRD-12 JSON int64 risk → contrainte Save/Load à imposer lors design Save/Load |

---

## 8. Specialist Disagreements

**Aucun désaccord direct entre specialists.** Convergences principales :

- **Combat-only soft-lock** (game-designer + economy-designer) : 2 specialists indépendants identifient le même problème → forte évidence.
- **Contradiction tween SPEND_SHOP** (game-designer + main reviewer pre-spec) : aligned avec HUD r1 — contradiction rare mais structurelle.
- **ACs Lints/Static** (qa-lead seul) : profondément technique, qa-lead est l'autorité.
- **Rule 7 batching** (game-designer seul, mais pillar-aligned) : creative-director adjudique pillar-driven.

Aucune adjudication contradictoire requise.

---

## 9. Bidirectional Update Required

Quand Credit r2 sera publié (pour résoudre les 7 ship-blocking), les GDDs suivants doivent vérifier leurs cross-références :

- **Shop GDD r1** : ligne ~7 quick-ref `try_spend` confirme déjà — pas d'update.
- **HUD GDD r1** : §Interactions ligne 108 confirme `credits_changed` SYNC + `get_total()` — pas d'update.
- **Secret GDD r1** : R-SEC-08 confirme `secret_collected(secret_node: Node, tier: int)` — pas d'update.
- **Enemy GDD r1** : §Dependencies ligne 312 mentionne Credit "Not Started" → à promouvoir "Designed r1 — pending review r2" (mineur, optionnel).
- **GSM GDD r1** : pas d'update (consumer pur Credit→GSM).

---

## 10. Verdict Final

**NEEDS REVISION** — 7 ship-blocking, 10 pre-implementation, 9 polish.

**Pillars intacts** (FLOW + PROGRESSION SE VOIT + SECRETS) — **dette tactique, pas stratégique**.

**Path to APPROVED** : r2 amendment focalisé <1 jour adressant les 7 ship-blocking + adjudication Rule 7 batching + adjudication asymétrie audio MVP. Les 10 pre-impl batchables en seconde passe parallèle Sprint A.

**Recommandation Sprint A planning** :

1. **Immédiat (parallèle session)** : amendement cosmétique r2 OQ-CRD-1/OQ-CRD-2 RESOLVED (utilisateur option E courante, ne fixe PAS les 7 ship-blocking — distinct).
2. **Court terme (1-2 sessions)** : `/design-system save-load-system` (débloque Sprint 1 Credit + Shop + Secret persistance).
3. **r2 amendment Credit complet** : session dédiée `/design-system credit-economy-system` ou édition manuelle ciblée — ~1 jour pour adresser les 7 ship-blocking + 10 pre-impl + 9 polish.
4. **Post-r2** : re-review fresh session pour confirmer APPROVED → `/create-epics` débloqué.

---

*Generated by /design-review on 2026-04-27 (solo mode, fresh session, full depth).*
*4 specialists adversariaux + creative-director synthèse senior.*
*Total findings : 26 (7 ship-blocking + 10 pre-impl + 9 polish).*
