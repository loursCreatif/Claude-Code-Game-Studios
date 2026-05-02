# QA Evidence — EC-8 Jolt CCD Playtest Sign-Off

**Story** : story-014 (AC-LVL-41)
**Type** : Playtest manual (gate final AC-LVL-41)
**Prérequis** : Runner headless EC-8 exit 0 (sub-gate automatisé)
**Source** : ADR-0001 EC-8, TR-lvl-039, story-014 AC-LVL-41

---

## Protocole QA

### Condition de pass

≥ 76 passes sans clip sur 80 totales (95% sur 8 murs × 10 passes chacun).

### Préparation

1. Confirmer que `perf-level-ccd` CI est en statut PASS (exit 0).
2. Charger `etage_01.tscn` en mode Play (Godot editor ou build export).
3. Identifier 5 à 8 murs critiques avec le level designer :
   - Surfaces wall-run (`wall_run_enabled = true`).
   - Angles et couloirs à haute vitesse.
   - Zones avec murs thin (épaisseur proche de 0.3 m).
4. Pour chaque mur : noter la position, l'orientation, l'épaisseur authoring.

### Procédure par mur

Pour chaque mur sélectionné, effectuer 10 passes à vitesse max :

1. Positionner le joueur à 5 m du mur, face au mur, sprint actif.
2. Déclencher le dash (vitesse ≈ 21 m/s) en direction du mur.
3. Observer : le joueur doit s'arrêter contre le mur (pas de traversée).
4. Cocher PASS ou FAIL dans le tableau ci-dessous.

**Définition CLIP** : le joueur traverse le mur et se retrouve de l'autre côté
sans collision response visible (corps visible dans la géométrie ou au-delà).

---

## Tableau de résultats

> Remplir lors de la session QA.

| Mur | Position | Épaisseur | P1 | P2 | P3 | P4 | P5 | P6 | P7 | P8 | P9 | P10 | Total PASS |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Mur 1 | | | | | | | | | | | | | /10 |
| Mur 2 | | | | | | | | | | | | | /10 |
| Mur 3 | | | | | | | | | | | | | /10 |
| Mur 4 | | | | | | | | | | | | | /10 |
| Mur 5 | | | | | | | | | | | | | /10 |
| Mur 6 | | | | | | | | | | | | | /10 |
| Mur 7 | | | | | | | | | | | | | /10 |
| Mur 8 | | | | | | | | | | | | | /10 |
| **Total** | | | | | | | | | | | | | **/80** |

**Condition de pass** : Total PASS ≥ 76 / 80 (95%)

---

## Verdict

- [ ] Total PASS ≥ 76 / 80 → **AC-LVL-41 PASS**
- [ ] Total PASS < 76 / 80 → **AC-LVL-41 FAIL** — escalader vers godot-specialist + technical-director

**Date de la session** : _______________
**Résultat total** : ___ / 80

**Clips observés** (description si FAIL) :
> _Décrire ici les clips observés, mur concerné, conditions exactes._

---

## Sign-Off

| Rôle | Nom | Date | Signature |
|---|---|---|---|
| Level Designer | | | |
| Producer | | | |

---

## Statut EC-8 post-playtest

- [ ] PASS → ADR-0001 EC-8 : `CLAIM-UNVERIFIED` → `VERIFIED Sprint 1`
- [ ] FAIL → Fallback R-5.6 requis (voir `docs/architecture/benchmarks/level-ccd-sweep-2026-04-27.md`)

---

## Liens

- Benchmark headless : `docs/architecture/benchmarks/level-ccd-sweep-2026-04-27.md`
- Story : `production/epics/level-system/story-014-wall-run-surface-door-width-ccd-bench.md`
- ADR : `docs/architecture/adr-0001-physics-rate-60hz.md` (EC-8)
