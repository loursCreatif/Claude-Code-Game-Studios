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
