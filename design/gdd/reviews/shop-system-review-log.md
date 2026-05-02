# Shop System — Review Log

> Suivi historique des reviews du GDD `design/gdd/shop-system.md`.
> Chaque entrée résume verdict + scope + fixes appliqués.
> Détails complets dans les fichiers `shop-system-review-r{N}-{YYYY-MM-DD}.md`.

---

## Review r1 — 2026-04-27 — Verdict : NEEDS REVISION → revisions r2 appliquées

**Mode** : full (4 specialists adversariaux parallèles)
**Specialists** : game-designer, economy-designer, systems-designer, qa-lead
**Solo gates** : CD-GDD-ALIGN skipped (`production/review-mode.txt` solo)
**Re-review** : No — first review (fresh session)
**Scope signal** : L
**Détails** : `shop-system-review-r1-2026-04-27.md`

### Verdicts par specialist

| Specialist | Verdict | Findings P1 |
|------------|---------|-------------|
| game-designer | APPROUVE-AVEC-RÉSERVES | 2 (Player Fantasy temporelle + Tier 2+ grinding) |
| economy-designer | NEEDS REVISION | 2 (n convention 1-based vs 0-based + 1 vs 2 étages MVP) |
| systems-designer | APPROUVE-AVEC-RÉSERVES | 2 (EC-SHP-9 risque admis + EC-SHP-23 atomicité) |
| qa-lead | NEEDS REVISION | 5 (AC-12/46 CONNECT_DEFERRED contradiction + AC-31 fragile + AC-34 CI ref + AC-44 commentaires) |

### Décisions design tranchées par user

1. **MVP scope** : 2 étages playable (cohérent Credit GDD F-CRD-4)
2. **Convention `n`** : 0-based partout (idiomatique GDScript)
3. **ESC pattern** : garder ESC = Continuer direct (Pillar 1 anti-friction prime, EC-SHP-41 documente le risque assumé)
4. **EC-SHP-9 save fail** : Option C buffer retry non-bloquant + fallback quit-to-menu

### Revisions r2 appliquées (20 modifications)

**Header & Overview** :
- Status `Designed r1 (pending fresh /design-review)` → `Designed r2`
- Quick reference Save/Load promu Designed r1 (OQ-SHP-3 RESOLVED via Save/Load r1)
- Overview ligne 11 : "1 étage MVP" → "2 étages playable MVP" (cohérence Credit F-CRD-4)

**Player Fantasy** :
- Réécriture "Tu peux. Mais pas les deux" → "À ta première visite, tu peux. Mais pas les deux — pas encore" + note honnêteté économique 4 profils Q25-Q95
- Référence Hollow Knight Iselda + Ghostrunner upgrade tree → Hotline Miami stats screen + Hades inventory + Dead Cells unlocks passifs

**Detailed Rules** :
- R-SHP-6 step 6 : retrait flash cyan post-achat (cohérence anti-fantasy "sobre")
- R-SHP-9 : note CONNECT_DEFERRED OBLIGATOIRE + VERROUILLÉ (AC-SHP-4 invariant testable)

**Formulas** :
- F-SHP-1 : note convention 0-based unifiée (Credit GDD F-CRD-3 amendée r2)
- F-SHP-3 : explicite cumul 2 étages MVP + table affordability par profil Q25-Q95
- F-SHP-4 : atténuation "premier saut révélation" + dépendance level design soft documentée
- Roadmap Tier 2+ : note anti-grinding MVP-only (Full Vision 720 cr accumulation cross-session assumée)
- Sanity checks : re-run d'étage = grinding mou documenté honnêtement (pas de level seal MVP, OQ-SHP-12 nouveau)

**Edge Cases** :
- EC-SHP-9 : réécriture Option C buffer retry non-bloquant 3× exponentiel + fallback quit-to-menu (95% couverture, "Risque Tier 1 admis" éliminé)
- EC-SHP-19 : double-couche défense + ouvre OQ-SHP-11 (audit GSM ADR-0007 paused lifecycle)
- EC-SHP-23 : note explicite atomicité dépend de CONNECT_DEFERRED (R-SHP-9)
- **6 nouveaux EC-SHP-36 à 41** : double `etage_completed`, `Player.died` LOADING, ordering BuyButton+Continue déterministe, String→StringName cast safety, réentrance CONNECT_DEFERRED non-risque, ESC réflexe sans achat MVP assumé

**Dependencies** :
- Save/Load promu LOCKED ✅ Designed r1 (OQ-SHP-3 RESOLVED)
- Upgrade pattern `_pending_upgrades` queue contrainte normative
- Atomicité SaveLoad MVP best-effort + fallback EC-SHP-9 documentée

**Acceptance Criteria** :
- AC-SHP-12 + AC-SHP-46 : corrigés contradiction CONNECT_DEFERRED ("idle frame suivante" pas "même frame")
- AC-SHP-31 : mécanisme robuste (spy mock OR count check)
- AC-SHP-34 : CI runner baseline (Ubuntu 22.04 4-core < 200 ms tolérance)
- AC-SHP-44 : robustesse exclusion commentaires + strings littérales
- AC-SHP-48/49 : workflow PENDING-ACTIVATION Sprint 1 (mocks puis re-test impl réelle)
- AC-SHP-49 : promu BLOCKING (Save/Load r1 RESOLVED, plus PROVISIONAL chain-blocked)
- AC-SHP-50/51/52 : abaissés à 2 sessions internes MVP (5 externes pre-Alpha)
- **3 nouveaux AC-SHP-53/54/55** : focus initial ContinueButton, state isolation entre instances, méta-propagation Credit r2+

**Open Questions** :
- OQ-SHP-3 ✅ RESOLVED via Save/Load r1
- OQ-SHP-4 ✅ RESOLVED MVP zéro SFX (Tier 2+ open)
- OQ-SHP-5 ✅ RESOLVED autoload RunContext Tier 2+ pattern
- OQ-SHP-11 nouveau (audit GSM ADR-0007 paused)
- OQ-SHP-12 nouveau (Tier 2+ level seal anti-replay grinding)

**Bidirectional updates** :
- Credit GDD : OQ-CRD-2 ✅ RESOLVED + F-CRD-3 amendée r2 0-based (table MVP/Full Vision réindexée)

### Métriques r1 → r2

| Métrique | r1 | r2 | Δ |
|----------|-----|-----|---|
| Lignes GDD | 1009 | ~1130 | +121 |
| Edge cases | 35 | 41 | +6 |
| ACs | 52 | 55 | +3 |
| Open Questions | 10 | 12 | +2 (11 + 12) |
| OQ critiques résolus | 0/4 | 3/4 (OQ-2 reste chain-blocked) | +3 |
| PROVISIONAL chain-blocked | 3 | 1 (OQ-SHP-2 only) | -2 |

### Status post-r2

`Designed r2` — débloque /create-epics shop-system avec stub UpgradeSystem Sprint 1 documenté workflow PENDING-ACTIVATION (AC-SHP-48 PROVISIONAL chain-blocked OQ-SHP-2 reste seul).

**Prior verdict resolved** : First review (no prior verdict).

**Recommandation suite** :
1. (Recommandé) `/create-epics shop-system` — backlog Sprint 1 avec stub UpgradeSystem
2. OU `/design-system upgrade-system` Sprint A continuation pour résoudre OQ-SHP-2 avant epics
3. OU `/review-all-gdds` consistency sweep cross-GDD pré-/create-epics

---

## Amendement r2.1 — 2026-04-28 — Cosmetic propagation Credit r2 B-2

**Mode** : amendement direct (sans /design-review re-run) — cosmétique factuel
**Trigger** : NB-CRD-1 SHIP-CRITICAL identifié par fresh /design-review credit-economy-system r2 (3 specialists convergents : game-designer + economy-designer + systems-designer) — contradiction cross-GDD `BASE_UPGRADE_COST` Credit r2=8 vs Shop r2=20.
**Scope signal** : XS (propagation factuelle constante + recalculs économiques dérivés, zéro changement structurel)
**Re-review** : No — amendement non-éligible review (aucune décision design nouvelle)

### Justification

Credit r2 B-2 (2026-04-27) a abaissé `BASE_UPGRADE_COST` de 20 → 8 cr pour résoudre soft-lock Pillar 2 anti combat-only étage 1 (`8 kills × 1 cr = 8 cr ≥ BASE_UPGRADE_COST = 8 cr` ✅ pile-poil). La constante n'a **pas été propagée** dans Shop r2 GDD lors de la session Credit, créant une contradiction cross-GDD bloquante avant `/create-epics credit + secret`. Shop r2 référençait encore `BASE_UPGRADE_COST=20` et `cost_n=1=40` à 11 endroits (Quick Reference, R-SHP-3, F-SHP-1, F-SHP-2, F-SHP-3 worked example, F-SHP-4 ordering, EC-SHP-14/15, Dependencies table, ACs, UI examples).

### Modifications appliquées (cosmétiques + recalculs dérivés)

**Constantes propagées** :
- `BASE_UPGRADE_COST` : 20 → 8 cr (r2 B-2)
- `cost_n=0` (`double_jump`) : 20 → 8 cr
- `cost_n=1` (`dash_horizontal`) : 40 → 28 cr
- Range MVP : `[20, 40]` → `[8, 28]`
- Range Full Vision (8 upgrades) : `[20, 160]` → `[8, 148]`

**Recalculs économiques F-SHP-3** :
- `total_cost_MVP` : 60 → 36 cr
- `margin` (Q95 expert) : 25 → 49 cr
- Roadmap Tier 2+ : Full Vision total 720 → 624 cr (cohérent Credit r2 ligne 254 : `Σ (8 + 20 × i)` i ∈ [0, 7] = 64 + 560)
- Indicatifs Tier 2+ : n=2 60→48, n=3 80→68, n=4-7 100-160 → 88-148

**Profils joueur révisés** :
- Q25 (combat-only) : `n=0 affordable étage 1 ?` NON → **OUI pile-poil** (8 = 8) — anti soft-lock B-2 livré
- Q50/Q75 confort : recalcul "OUI confortable" sur deux upgrades
- Q95 marge : 25 → 49 cr résiduels — note non-trivialité Tier 2+ : Q95 peut financer n=2 (48 cr) en 1 session, friction à rétablir par contenu Tier 2+ (yield ↑) plutôt que coût

**ACs ajustés** :
- AC-SHP-5 : "(15<40)" → "(15<28)"
- AC-SHP-6/9 : `try_spend(40)` → `try_spend(28)`
- AC-SHP-7/10 : `try_spend(20)` → `try_spend(8)`
- AC-SHP-11 : solde 15/cost 20 → solde 7/cost 8 (sinon double_jump deviendrait affordable)
- AC-SHP-12 : `credits_changed(15, -5)` → `credits_changed(7, -3)` (préserver invariant deux disabled)
- AC-SHP-16 : solde 19 → solde 7
- AC-SHP-17 : solde 20, try_spend(20) → solde 8, try_spend(8)
- AC-SHP-18 : solde 60, debit 20 → solde 36, debit 8 (préserver dash devient affordable post-achat)
- AC-SHP-19 : solde 60 → solde 36 (= total_cost_MVP exact)

**Player Fantasy retouches** :
- "Saut Double — 20 ₵" → "Saut Double — 8 ₵"
- "Dash Horizontal — 40 ₵" → "Dash Horizontal — 28 ₵"
- "compteur tombe de 33 à 13" → "compteur tombe de 33 à 25"
- Réécriture "tu peux mais pas les deux" : 33 cr < 36 cr (8+28) — tension préservée
- Note honnêteté économique : Q25 combat-only désormais ligne anti soft-lock B-2 (pas friction Pillar 2 punitive)

**Dependencies + UI examples** :
- Table deps Credit Economy : `BASE_UPGRADE_COST=20` → `BASE_UPGRADE_COST=8` (r2 B-2)
- Tooltip exemple : "20 crédits manquants" → "8 crédits manquants"
- Screen reader : "Saut Double, coût 20 crédits" → "Saut Double, coût 8 crédits"

### Status post-r2.1

`Designed r2.1` — NB-CRD-1 ship-critical RÉSOLU côté Shop. Credit r3 (NEEDS REVISION ciblée) peut désormais référencer un Shop GDD aligné. Aucune action additionnelle requise sur Shop tant que Credit r3 ne ré-amende pas la formule F-CRD-3.

### Propagations encore PENDING (hors scope D)

- **production/epics/shop-system/EPIC.md** : peut contenir des montants 20/40 cr hérités de r2 — à auditer avant `/create-epics shop-system` re-run OU au moment du `/create-stories shop-system`. Sprint A backbone non-affecté tant que stories shop ne sont pas implémentées.
- **production/epics/shop-system/story-XXX.md** : 16 stories existantes potentiellement avec montants 20/40 — refresh à faire avant Sprint shop activation.
- **Test fixtures `tests/unit/shop/`** (futurs) : aucun test implémenté à ce jour, pas de risque immédiat.

**Recommandation suite** :
1. (Recommandé) Continuer batch B/C : `/design-system credit-economy-system` r3 (résout 6 NB-CRD restants) puis `/design-system secret-system` r3
2. Audit Shop epic + stories avant Sprint shop (pas Sprint A backbone)
3. Skip review log r2.1 — amendement cosmétique non-éligible /design-review
