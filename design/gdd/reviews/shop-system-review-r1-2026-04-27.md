# Shop System — Design Review r1 → revisions r2

**Date** : 2026-04-27
**Skill** : `/design-review shop-system` fresh session full mode
**Author** : Martin + main session (Opus 4.7)
**Mode** : full (4 specialists adversariaux parallèles + Phase 4 verdict + Phase 5 revisions inline solo auto-approve)
**Re-review** : No — first review of shop-system r1
**Source GDD reviewed** : `design/gdd/shop-system.md` r1 (1009 lignes)
**Output GDD post-revisions** : r2 (~1130 lignes)

---

## Phase 1 — Documents loaded

- `design/gdd/shop-system.md` (full read, 1009 lignes)
- `design/gdd/credit-economy-system.md` (verification F-CRD-3 convention)
- `design/CLAUDE.md` + `.claude/rules/design-docs.md` (8-section standard)
- `production/review-mode.txt` = `solo` (CD-GDD-ALIGN gate skip)
- Dependency graph audit : 9/12 dependencies existent en GDD ; 3 manquants (save-load-system existait Designed r1 — verified ; upgrade-system + menu-system Not Started)

---

## Phase 2 — Completeness

| Section | Présence | Notes |
|---------|----------|-------|
| Overview | ✅ | 1 paragraphe dense |
| Player Fantasy | ✅ | 4 sous-sections (moment shop, pacte crédit, pacte Pillar 4, anti-fantasy) + référence sentimentale |
| Detailed Rules | ✅ | 16 R-SHP + States and Transitions table 6 états + Interactions 10 systèmes |
| Formulas | ✅ | 5 formules (F-SHP-1 à F-SHP-5) |
| Edge Cases | ✅ | 35 EC-SHP r1 (41 r2 post-revisions) |
| Dependencies | ✅ | Hard×3 + Soft×4 + Cousins×4 + Anti-deps×4 + Bidirectional check + Provisional contracts |
| Tuning Knobs | ✅ | MVP design-active 9 + structurel 4 + visual tokens 10 + Tier 2+ hooks 5 |
| Acceptance Criteria | ✅ | 52 ACs r1 (55 r2 post-revisions) |

**Bonus sections** : Visual/Audio Requirements, UI Requirements §J (10 sous-sections J.1-J.10), Open Questions (10 OQ-SHP r1 → 12 r2).

**Score completeness : 8/8 + 3 bonus**

---

## Phase 3 — Consistency and Implementability

### Internal consistency
- Formules cohérentes inter-elles (F-SHP-1 délégation F-CRD-3 ; F-SHP-2 utilise F-SHP-1 ; F-SHP-3 dérive F-SHP-1 × N)
- États 6-states cohérents avec cycle d'achat R-SHP-6 (PURCHASE_PENDING sous-état ACTIVE)
- Idempotence triple-niveau bien spec (UI guard + Save re-entry + UpgradeSystem idempotent)

### Cross-GDD consistency
- ⚠️ **Convention `n` divergente** : Credit F-CRD-3 ligne 155 utilise `n ∈ [1, N_UPGRADES]` (1-based, rang) ; Shop F-SHP-1 ligne 247 utilise `n ∈ [0, MAX_UPGRADE_INDEX]` (0-based, index). Arithmétiquement équivalent mais bug d'impl garanti.
- ⚠️ **Contradiction MVP scope** : Shop ligne 11 dit "1 étage MVP" ; Credit ligne 210 dit yield range `[8, 100] cr cumul étage 1+2 MVP`. F-SHP-3 utilise yield 85 cr (2 étages).

### Implementability
- 35 EC-SHP couvrent boot, credit, save, affordability, UpgradeSystem failures, GSM, lifecycle, re-entry, resize, inputs, security, audio, i18n, accessibility, anti-stuck. Très complet.
- 52 ACs avec mécanismes spec'd (GUT unit, integration scene, lint static, performance test, manual playtest). Quelques mécanismes fragiles identifiés.

---

## Phase 3b — Adversarial Specialist Review (full mode parallel)

4 specialists spawned in parallel via Task tool. Tous returns reçus :

### game-designer (APPROUVE-AVEC-RÉSERVES)

**P1 findings** :

1. **Player Fantasy "tu peux mais pas les deux" mensongère pour Q25 explorer** : la tension décisionnelle n'est vraie qu'à la première visite shop d'un joueur explorateur étage 1+2. Pour Q25 (combat-only 8 cr), aucun achat possible. Pour Q95 + run complète, achète les deux confortablement. Le GDD ne mentionne jamais cette temporalité. Fix : "À ta première visite, tu peux. Mais pas les deux — pas encore."

2. **Tier 2+ courbe Full Vision = grinding par construction** : 8 upgrades × cost = 720 cr ; yield max ~85 cr/run + persistance cross-session = 8-9 runs. Contradiction directe avec anti-pillar grinding. Soit déclarer anti-grinding MVP-only (Option A), soit retuner courbe.

**P2/P3** :
- R-SHP-6 step 6 pulse + flash cyan contredit anti-fantasy "achat silencieux" — soit retirer flash cyan, soit reformuler "sobre" pas "silencieux"
- F-SHP-4 ordering double_jump n=0 suppose level design non garanti
- R-SHP-11 ESC=Continuer perte de fenêtre achat — pattern alternatif "1er ESC focus + 2nd trigger"
- OQ-SHP-2/3/4/5 : seules OQ-4 et OQ-5 résolubles ici (OQ-2/3 chain-blocked)
- Refs Hollow Knight Iselda + Ghostrunner upgrade tree imprécises

### economy-designer (NEEDS REVISION)

**P1 findings** :

1. **Convention `n` divergente F-CRD-3 (1-based) vs F-SHP-1 (0-based)** : bug d'impl garanti si dev mélange. Credit `n=1 → 20cr`, Shop `n=1 → 40cr`. Choisir une convention unique.

2. **F-SHP-3 yield_max 85 cr suppose 2 étages, mais Shop ligne 11 dit "1 étage MVP"** : marge réelle si MVP=1 étage = 3 cr (pas 25 cr) → Pillar 2 cassé. Q50 médian (~21 cr) ne peut acheter que n=0 ; n=1 inatteignable en 1 étage. Doit trancher avant /create-epics.

**P2** :
- Analyse profils Q25-Q50-Q75-Q95 affordability réelle
- Sink non-pur : re-run étage = grinding via game-concept (Enemy `_credited_this_run` reset au level_active)
- F-SHP-4 ordering sans métrique testable

### systems-designer (APPROUVE-AVEC-RÉSERVES)

**P1 findings** :

1. **EC-SHP-9 "Risque Tier 1 admis" trop permissif** : crédits débités + save fail = upgrade perdue au redémarrage. Recommandation Option C buffer retry non-bloquant + fallback quit-to-menu (95% couverture).

2. **EC-SHP-23 atomicité face à NOTIFICATION_EXIT_TREE** : "aucun await" insuffisant si CONNECT_SYNC sur credits_changed. Documenter explicitement DEFERRED obligatoire + audit chain rule.

**P2** :
- EC-SHP-19 "à confirmer ADR-0007" trou de spec → ouvrir OQ-SHP-11
- EC-SHP-32 save tampering = upgrades gratuites (acceptable solo offline mais log warning recommandé)
- PURCHASE_PENDING < 1 tick non-observable test
- 5 nouveaux EC-SHP-36 à 40 proposés (double etage_completed, Player.died LOADING, ordering BuyButton+Continue, String→StringName cast, réentrance DEFERRED)

### qa-lead (NEEDS REVISION)

**P1 findings** :

1. **AC-SHP-12 + AC-SHP-46 contradiction CONNECT_DEFERRED** : AC-SHP-4 impose DEFERRED ; AC-12 + AC-46 affirment "même frame". Impossible à passer tels que rédigés. Réécriture obligatoire.

2. **AC-SHP-31 mécanisme grep fragile** ("5 lignes suivantes" — fragile si variable intermédiaire)

3. **AC-SHP-34 "machine référence" non reproductible CI** (laptop entrée gamme vs runner GitHub Actions)

**P2/P3** :
- AC-SHP-35 ambiguïté prod vs test (mocks vs SaveLoad async potential)
- AC-SHP-48/49 PROVISIONAL workflow Sprint 1 non spécifié
- AC-SHP-44 lint robustesse commentaires
- AC-SHP-50/51/52 5 sessions playtest irréaliste MVP
- 3 ACs manquants AC-SHP-53/54/55 (focus initial, state isolation, méta-propagation Credit r2)

---

## Phase 4 — Output Review

### Specialist disagreements
Aucun désaccord matériel. Tous convergent : GDD techniquement solide, calibrage économique nécessaire, ACs P1 reword obligatoires.

### Senior Verdict
Pas de creative-director synthesis spawned (solo mode + auto-approve + skill `--full` Phase 3b done — main session synthétise directement les 4 specialists alignés).

**Verdict : NEEDS REVISION**

2/4 specialists return NEEDS REVISION (economy-designer, qa-lead) sur P1 factuels. game-designer + systems-designer return APPROUVE-AVEC-RÉSERVES. **6 BLOCKING (B1-B6) + 10 RECOMMENDED (R1-R10)** identifiés.

### Scope Signal
**Rough scope signal : L** (5+ dependencies dont 3 hard ; 5 formulas ; provisional contracts vers Save/Load + Upgrade GDDs ; 35 EC ; 52 ACs ; intégration GSM transitions + Credit signaux + HUD architecture).

---

## Phase 5 — Revisions r2 inline (solo auto-approve + 4 décisions design tranchées par user)

### Décisions matérielles tranchées (AskUserQuestion)

1. **MVP scope** : 2 étages playable MVP (cohérent Credit GDD F-CRD-4)
2. **Convention `n`** : 0-based partout (idiomatique GDScript)
3. **ESC pattern** : garder ESC = Continuer direct (Pillar 1 anti-friction prime)
4. **Save fail strategy** : Option C buffer retry non-bloquant

### Revisions r2 appliquées

Voir `shop-system-review-log.md` pour la liste exhaustive (20 modifications).

### OQ critiques résolutions

| OQ | Status r1 | Status r2 |
|----|-----------|-----------|
| OQ-SHP-2 (Upgrade contract) | OPEN bloquant Sprint 1 | CHAIN-BLOCKED Sprint 1 — workflow PENDING-ACTIVATION AC-SHP-48 documenté ; exigence Upgrade GDD avant Sprint 2 |
| OQ-SHP-3 (SaveLoad API) | OPEN bloquant Sprint 1 | ✅ **RESOLVED** via Save/Load r1 (vérification : Save/Load Designed r1 commit Sprint A avec save/load_string_array LOCKED) |
| OQ-SHP-4 (Audio bus) | OPEN Tier 2+ | ✅ **RESOLVED MVP** zéro SFX (Tier 2+ amendement Audio r2.2 reste open) |
| OQ-SHP-5 (next_etage_id) | OPEN Tier 2+ | ✅ **RESOLVED** autoload RunContext Tier 2+ pattern tranché |

**Score résolution : 3/4 OQ critiques résolus dans la review r2.**
**OQ-SHP-2 reste seule chain-blocked** — non-résoluble dans Shop GDD seul (attend Upgrade GDD).

### Bidirectional updates appliquées

- ✅ Credit GDD F-CRD-3 amendée r2 0-based + table MVP/Full Vision réindexée
- ✅ Credit GDD OQ-CRD-2 marquée RESOLVED
- ✅ Systems-index : Shop System row promue Designed r2
- ⚠️ GSM r1 §Dependencies update `ShopSystem (inferred, Not Started) → Designed r2` reste à propager au prochain commit GSM-touching (note dans Bidirectional updates section Shop GDD)

### Files modified

- `design/gdd/shop-system.md` (Designed r1 → Designed r2, ~120 lignes ajoutées net)
- `design/gdd/credit-economy-system.md` (F-CRD-3 amendement r2 + OQ-CRD-2 RESOLVED)
- `design/gdd/systems-index.md` (Last Updated paragraph + Shop row r2)
- `design/gdd/reviews/shop-system-review-log.md` (créé)
- `design/gdd/reviews/shop-system-review-r1-2026-04-27.md` (ce fichier)

---

## Final status

**Shop System Designed r2** — débloque `/create-epics shop-system`.

Sprint 1 stories Shop peuvent commencer avec stub UpgradeSystem (mock SYNC idempotent dans `tests/unit/shop/mocks/mock_upgrade_system.gd`). AC-SHP-48 marqué PENDING-ACTIVATION jusqu'à Upgrade GDD r1 → mergé. Story Shop Done-Provisional jusqu'alors.

**Recommandation Phase 5 closing** :
1. `/create-epics shop-system` (recommandé) — backlog Sprint 1
2. OU `/design-system upgrade-system` Sprint A continuation pour résoudre OQ-SHP-2 avant epics
3. OU `/review-all-gdds` consistency sweep cross-GDD pré-/create-epics
