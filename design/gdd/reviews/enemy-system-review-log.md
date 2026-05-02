# Enemy System — Review Log

Fichier d'historique des reviews pour `design/gdd/enemy-system.md`. Chaque entrée documente un passage `/design-review`.

---

## Review — 2026-04-27 — Verdict: NEEDS REVISION

**Scope signal**: S (changements ciblés — pas de redesign architectural)
**Specialists consultés**: game-designer seul (fresh session, mode solo)
**Blocking items**: 4 | **Recommended**: 7 | **Nice-to-have**: 5
**Prior verdict resolved**: First review (r1 In Design)
**Completeness**: 8/8 sections + 5 bonus (Visual/Audio, UI, OQs, States, Interactions)
**Dependency graph**: 4 upstream DESIGNED (Level ✅, Combat ✅, Movement ⚠️, GSM ✅) / 5 downstream not-started (contrats one-way OK)

### Summary

La Player Fantasy est **exceptionnelle** — la meilleure du studio à ce jour. La philosophie "ennemi comme panneau indicateur de chorégraphie" est parfaitement alignée sur les pillars. La structure 8 sections est irréprochable avec 16 edge cases et 28 ACs bien typés.

Cependant, 4 BLOCKING identifiés :
- **B-1 (OQ-ENM-1)** : conflit cross-GDD sur l'autorité d'émission de `enemy_killed` (Combat r6 APPROVED vs Enemy r1). Résolution : Enemy émet. Amendement Combat r7 requis.
- **B-2** : typo sur numéro layer collision LAYER_ENEMY_HITBOX (table Rule 4 dit "layer 4" au lieu de "layer 3"). Éditorial pur mais potentiellement catastrophique à l'implémentation.
- **B-3** : tween wall-clock vs pause — `create_tween()` est `TWEEN_PAUSE_BOUND` par défaut en Godot 4.6, ce qui contredit la spécification wall-clock absolu de F-ENM-3. Requiert `tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)` explicite.
- **B-4** : bidirectionalité Movement non confirmée (ligne 327 "À confirmer") — gate sur re-review Movement r4.

10 OQs tranchées : OQ-ENM-1 RESOLVED (Enemy émet), OQ-ENM-2 RESOLVED (LevelSystem spawne directement), OQ-ENM-3 RESOLVED (BoxShape3D MVP), OQ-ENM-5 RESOLVED (sample universel Audio r2.1), OQ-ENM-8 RESOLVED (aucune animation MVP). OQ-ENM-4/6/7/9/10 DEFERRED avec sprint cibles.

Amendement Combat r7 tracé formellement (voir review `enemy-system-review-r1-2026-04-27.md` §9 et §14).

**Rapport complet** : [enemy-system-review-r1-2026-04-27.md](enemy-system-review-r1-2026-04-27.md)

### 4 BLOCKING

| # | Item | Lines |
|---|------|-------|
| B-1 | OQ-ENM-1 cross-GDD signal authority conflict | enemy:128, combat:177/270/286 |
| B-2 | Layer collision typo "layer 4" → "layer 3" (LAYER_ENEMY_HITBOX) | enemy:76, AC-ENM-06 |
| B-3 | Tween wall-clock vs TWEEN_PAUSE_BOUND Godot 4.6 | enemy:129, enemy:228, enemy:278 |
| B-4 | Movement bidirectionality not confirmed (À confirmer) | enemy:327 |

### Corrections à appliquer (scope S)

1. enemy:76 — typo "layer 4" → "layer 3 (1-indexed Godot)"
2. Rule 11.d — ajouter `tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)` 
3. F-ENM-3 — noter dépendance `TWEEN_PAUSE_PROCESS` pour wall-clock garanti
4. Interactions table — clarifier Enemy comme source de `enemy_killed` (pas Combat)
5. Note gate : "approbation finale conditionnée à Movement re-review r4 confirmant die() contract"
6. Tuning Knobs — aligner `death_tween_duration_ms = 400` reduce_motion avec registry entities.yaml
7. +3 ACs manquants : `is_dead()` getter, `_restore_from_snapshot` sur DYING, orthonormalisation spawn

### Amendement Combat r7 (tracé, à appliquer session Combat)

- Retirer `enemy_killed` des signaux émis par CombatSystem (Published API)
- Rule 9 : Combat appelle `enemy.die()` → Enemy émet `enemy_killed`
- Interactions table Enemy : Consumer de `enemy_killed` ← pas émetteur
- Credit Economy/VFX consumer : se connecter à `Enemy.enemy_killed`

---

## Revision r2 — 2026-04-27 — Status: In Design r2 (corrections review-r1 appliquées)

**Scope**: S (corrections éditoriales + clarifications, pas de redesign architectural)
**Trigger**: Application des 6 corrections issues de la review-r1 NEEDS REVISION
**Modifs**: 528 → 558 lignes (+30 lignes nettes — clarifications API, ACs ajoutés, notes amendement Combat r7)

### Corrections appliquées (6/6)

| # | Correction | Fichier:lignes |
|---|-----------|---------------|
| 1 | **B-2** typo layer collision | `enemy-system.md:77` "layer 4" → "layer 3 (LAYER_ENEMY_HITBOX, 1-indexed Godot convention = bit `0b00000100`)" |
| 2 | **B-3** tween wall-clock vs pause — séparation API correcte | Rule 11.d : `set_ignore_time_scale(true)` (pour Engine.time_scale) + default `TWEEN_PAUSE_BOUND` (pour pause GSM). Note explicite séparation API. F-ENM-3 + EC-ENM-9 mis à jour pour cohérence. **Déviation reviewer** : la review recommandait `set_pause_mode(TWEEN_PAUSE_PROCESS)` mais cela aurait cassé EC-ENM-9 (pause behavior). L'API correcte Godot 4.6 sépare time_scale (`set_ignore_time_scale`) et pause_mode (`set_pause_mode`) — appliqué |
| 3 | **B-4** gate condition Movement | Header GDD ligne 6 : "ENEMY APPROVED conditionnel à confirmation contrat bidirectionnel `Player.die()` lors re-review fresh Movement GDD r4". Tracé bidirectional check table ligne 332 |
| 4 | **OQ-ENM-1 + R-2** Enemy autorité d'émission | Interactions table : 5 consumers (Combat/Credit/VFX/Audio/HUD) clarifiés se connecter à `Enemy.enemy_killed`. Note cross-system §Dependencies : 5 justifications + amendement Combat r7 explicit (rules 9, 270, 286 listés). API `LevelSystem.get_etage_enemy_slots()` retirée (LevelSystem = factory directe). OQ-ENM-1 + OQ-ENM-2 marqués ✅ RESOLVED |
| 5 | **R-4** registry/GDD align reduce_motion 400ms | Tuning Knobs : `DEATH_TWEEN_DURATION_MS` documente le variant 400 ms `reduce_motion=true` comme dépendance conditionnelle Accessibility System (Tier 3 latent, pas activable MVP) |
| 6 | **3 ACs manquants** | AC-ENM-07b (`is_dead()` getter contract 3 states), AC-ENM-07c (orthonormalisation spawn EC-ENM-6), AC-ENM-18b (`_restore_from_snapshot(true)` sur DYING — kill tween + DEAD direct, pas de signal ré-émis) |

### Status post-r2

- 6/6 BLOCKING addressed
- OQ-ENM-1 + OQ-ENM-2 RESOLVED
- 3 ACs ajoutés (28 → 31)
- Header GDD : `In Design → In Design r2`
- **Next** : `/design-review enemy-system` fresh session pour APPROVED verdict, puis `/create-epics enemy-system` Sprint A (conditionnel à amendement Combat r7 + Movement r4 confirmation)

---

## Revision r2 re-review — Verdict: APPROVED

**Date** : 2026-04-27
**Reviewer** : game-designer (fresh session, mode solo)
**Scope** : re-review ciblée — 4 BLOCKING + 3 ACs + R-4

### B-1 à B-4 — Statut

| # | Blocking | Statut | Référence GDD |
|---|---------|--------|---------------|
| B-1 | OQ-ENM-1 autorité `enemy_killed` | RESOLVED | Lignes 129, 180-186, 346-354, 549 |
| B-2 | Layer collision typo "layer 4" → "layer 3" | RESOLVED | Ligne 77 |
| B-3 | Tween wall-clock vs TWEEN_PAUSE_BOUND | RESOLVED (déviation correcte) | Lignes 131-145, 244, 294 |
| B-4 | Gate condition Movement bidirectionalité | RESOLVED | Lignes 6, 343 |

**Note B-3** : la review-r1 recommandait `set_pause_mode(TWEEN_PAUSE_PROCESS)`. La r2 applique `set_ignore_time_scale(true)` + default `TWEEN_PAUSE_BOUND`. La déviation est confirmée correcte — `TWEEN_PAUSE_PROCESS` aurait cassé EC-ENM-9 (tween continue pendant pause GSM). Les deux APIs Godot 4.6 sont distinctes : `set_ignore_time_scale` gère Engine.time_scale, `set_pause_mode` gère tree.paused.

### ACs ajoutés — Statut

| AC | Contenu | Statut |
|----|---------|--------|
| AC-ENM-07b | `is_dead()` getter 3 states | PRESENT ET CORRECT |
| AC-ENM-07c | Orthonormalisation spawn EC-ENM-6 | PRESENT ET CORRECT |
| AC-ENM-18b | `_restore_from_snapshot(true)` sur DYING | PRESENT ET CORRECT |

### R-4 — Statut

RESOLVED — `DEATH_TWEEN_DURATION_MS` documente les deux valeurs (150 ms MVP, 400 ms reduce_motion) avec dépendance conditionnelle Accessibility System Tier 3 explicite.

### Prochaine étape

`/create-epics enemy-system` avec gates tracées : (A) Amendement Combat r7, (B) Confirmation Movement r4.

**Rapport complet** : [enemy-system-review-r2-2026-04-27.md](enemy-system-review-r2-2026-04-27.md)
