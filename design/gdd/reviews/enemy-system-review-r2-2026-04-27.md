# Enemy System — Review r2 — 2026-04-27

> **Reviewer** : game-designer (fresh session — aucune mémoire de la session de design ni de la review-r1)
> **Review mode** : solo (CD-GDD-ALIGN skipped, QL-TEST-COVERAGE skipped, LP-CODE-REVIEW skipped)
> **GDD cible** : `design/gdd/enemy-system.md` — In Design r2 — 558 lignes
> **Date** : 2026-04-27
> **Scope** : re-review ciblée — vérification des 4 BLOCKING r1 + 3 ACs ajoutés + R-4 reduce_motion

---

## Verdict

**APPROVED**

Les 4 BLOCKING de la review-r1 sont correctement résolus. Les 3 ACs manquants identifiés ont été ajoutés avec un contenu correct. R-4 est documenté de façon adéquate. Aucun nouveau BLOCKING détecté dans le scope de la re-review.

---

## Vérification des 4 BLOCKING r1

### B-1 — OQ-ENM-1 : Autorité d'émission `enemy_killed`

**Statut : RESOLVED**

La résolution est complète et cohérente sur l'ensemble du GDD :

- **Rule 11.c** (ligne 129) : `enemy_killed.emit(self, global_position)` est explicitement dans le corps de `die()` côté Enemy. L'émission Enemy est le comportement canonique.
- **Interactions table** (lignes 180-186) : les 5 consumers (Combat, Credit Economy, VFX, Audio, HUD) indiquent tous `Enemy.enemy_killed` comme source. Formulation explicite "Enemy est l'autorité d'émission" présente ligne 180. Mention "pas CombatSystem.enemy_killed" en ligne 183.
- **§Dependencies cross-system note** (lignes 346-354) : note 🚨 avec "RÉSOLU review-r1", 5 justifications architecturales développées, amendement Combat r7 listé avec les 4 règles de modifications précises.
- **Bidirectional check table** (ligne 343) : statut "✅ Bidirectionnel post-résolution OQ-ENM-1".
- **OQ-ENM-1** (ligne 549) : marqué "✅ RESOLVED review-r1" avec résumé de la résolution.

Note additionnelle : la note §Dependencies précise correctement que l'amendement Combat r7 est un "prerequisite gate avant `/create-epics enemy-system`" — ce framing de gate est la bonne façon de tracer la dépendance sans bloquer le GDD Enemy lui-même.

### B-2 — Layer collision LAYER_ENEMY_HITBOX

**Statut : RESOLVED**

Ligne 77 (Rule 4, collision table) :

```
LaserCone: Area3D (hitbox lethal) | 3 (LAYER_ENEMY_HITBOX, 1-indexed Godot convention = bit 0b00000100) | ...
```

Le typo "layer 4" de r1 est corrigé en "layer 3". La convention 1-indexed Godot est explicitement mentionnée dans la cellule et dans la note ⚠️ ligne 79. La cohérence AC-ENM-06 (ligne 477) est maintenue : `LaserCone.collision_layer == 0b00000100` (bit 2 = layer 3 1-indexed). Cohérence parfaite avec Combat GDD r6 LAYER_ENEMY_HITBOX = 3.

### B-3 — Tween wall-clock vs TWEEN_PAUSE_BOUND

**Statut : RESOLVED — déviation par rapport à la recommandation r1 CORRECTE**

La review-r1 recommandait `set_pause_mode(TWEEN_PAUSE_PROCESS)`. Le GDD r2 applique `set_ignore_time_scale(true)` avec `TWEEN_PAUSE_BOUND` (default). La déviation est justifiée et correcte.

**Analyse de la déviation** :

La review-r1 identifiait correctement que le tween devait être "wall-clock absolu" mais confondait deux problèmes distincts dans Godot 4.6 :

1. **Protection contre `Engine.time_scale`** : géré par `set_ignore_time_scale(true)`. Sans ça, le slow-mo Combat (0.3×) ralentirait le tween de 150 ms à 500 ms wall-clock perçu.

2. **Comportement lors de `tree.paused = true`** : géré par `set_pause_mode()`. Le default `TWEEN_PAUSE_BOUND` gèle le tween quand la scène est pausée — ce qui est le comportement attendu par EC-ENM-9 (pause GSM gèle le tween, resume reprend).

Si `set_pause_mode(TWEEN_PAUSE_PROCESS)` avait été appliqué comme recommandé en r1, le tween **aurait continué de tourner pendant la pause GSM** — ce qui casse EC-ENM-9 et est sémantiquement incorrect (le joueur quitte le jeu via ESC, il s'attend à tout geler, y compris les animations ennemies).

**La r2 sépare correctement les deux APIs** : `set_ignore_time_scale(true)` pour time_scale uniquement, `TWEEN_PAUSE_BOUND` (default) pour pause tree. C'est la résolution canonique Godot 4.6.

Le GDD documente cette distinction explicitement aux lignes 140-145 (note "séparation pause vs time_scale"), F-ENM-3 lignes 244 et EC-ENM-9 ligne 294. La documentation est suffisamment précise pour qu'un programmeur Godot 4.6 implémente sans ambiguïté.

**Verdict déviation** : confirmée correcte. La review-r1 était en erreur sur le choix de l'API. Le GDD r2 est plus juste que la recommandation initiale.

### B-4 — Gate condition Movement bidirectionalité

**Statut : RESOLVED**

Deux points d'ancrage présents :

1. **Header GDD ligne 6** : "ENEMY APPROVED conditionnel à confirmation contrat bidirectionnel `Player.die()` lors de la re-review fresh Movement GDD r4 (cf §Dependencies bidirectional check + B-4 review-r1)".

2. **Bidirectional check table ligne 343** : "⚠️ **Gate condition** : ENEMY APPROVED conditionnel à confirmation Movement r4 documente `Player.die()` comme appelé par Enemy LaserCone (cf review-r1 BLOCKING-4). Tracé header GDD ligne 6. Non-bloquant pour design r2 mais bloquant pour `/create-epics enemy-system`".

La formulation est précise et correctement scopée : non-bloquant pour l'approbation du GDD (design r2), bloquant pour le démarrage de l'implémentation (`/create-epics`). Ce framing est la bonne façon de gérer une dépendance sur un GDD "In Review".

---

## Vérification des 3 ACs ajoutés

### AC-ENM-07b — `is_dead()` getter 3 states

**Statut : PRESENT ET CORRECT**

Ligne 481-482 : AC bien formulé GIVEN/WHEN/THEN, couvre les 3 states (ALIVE → false, DYING → true, DEAD → true). La justification "DYING+DEAD = dead garantit qu'un kill mid-tween est bien capturé au snapshot Checkpoint" est pertinente et justifie l'existence de cet AC.

Type [Logic], donc BLOCKING. Testable unit.

### AC-ENM-07c — Orthonormalisation spawn EC-ENM-6

**Statut : PRESENT ET CORRECT**

Ligne 483-484 : AC couvre le cas exact d'EC-ENM-6 (EnemySlot avec scale non-uniforme). La vérification `FacingPivot.global_basis.is_normalized() == true` est le bon critère de validation. Cohérence avec EC-ENM-6 ligne 288 ("normalisation forcée : `FacingPivot.global_basis = EnemySlot.global_basis.orthonormalized()`").

Type [Logic], testable unit.

### AC-ENM-18b — `_restore_from_snapshot(true)` sur DYING

**Statut : PRESENT ET CORRECT**

Lignes 515-516 : AC couvre le second variant d'EC-ENM-13 (le premier étant AC-ENM-18 qui couvre `_restore_from_snapshot(false)` sur DYING). Spécifie : kill() du tween, state DEAD direct, scale EPSILON, monitoring=false, **aucun `enemy_killed` ré-émis**. La précision "le kill original a déjà été crédité — le restore ne re-crédite pas" est architecturalement critique et correctement documentée.

Type [Integration], testable.

---

## Vérification R-4 — reduce_motion 400 ms

**Statut : RESOLVED**

Tuning Knobs section (ligne 369) : la ligne `DEATH_TWEEN_DURATION_MS` documente maintenant les deux valeurs :

- `150 ms` (default MVP)
- `400 ms` si `reduce_motion = true` (Accessibility System Tier 3 — latent)

Le registre entities.yaml:69 et le GDD sont désormais cohérents. La dépendance conditionnelle "Accessibility System (Not Started, Tier 3)" est explicitement mentionnée, avec la note "pas activable au MVP (pas d'API `reduce_motion`)". Safe range différencié : `[100, 300]` MVP vs `[300, 600]` reduce_motion.

---

## Notes complémentaires

Aucun nouveau BLOCKING détecté dans ce scope de re-review.

Une observation mineure hors-scope (ne ré-ouvre pas de BLOCKING) : OQ-ENM-3 (ligne 551) reste ouvert dans la table mais avait été marqué "RESOLVED (BoxShape3D MVP)" dans la review-r1 §8. Le GDD garde OQ-ENM-3 sans le marqueur ✅ RESOLVED. Cela n'est pas bloquant — l'OQ est résolu dans le sens où la recommandation BoxShape3D est documentée dans Rules et Formulas. Un futur auteur pourrait marquer "✅ RESOLVED review-r1" pour cohérence avec OQ-ENM-1 et OQ-ENM-2, mais c'est du polish non-bloquant.

---

## Recommandation suite

**GDD Enemy System approuvé pour implémentation sous conditions de gate.**

Prochaine étape : **`/create-epics enemy-system`** pour Sprint A, avec les deux gate conditions restantes tracées dans le backlog :

1. **Gate A** — Amendement Combat r7 : retirer `enemy_killed` des signaux émis par CombatSystem (prerequisite avant `/create-epics`). Corrections listées dans §Dependencies cross-system note.
2. **Gate B** — Confirmation Movement r4 : re-review fresh Movement GDD r4 doit confirmer que `Player.die()` est documenté comme appelé par Enemy LaserCone (non-bloquant pour APPROVED du GDD Enemy, bloquant pour démarrage Sprint A implémentation).

Ces deux gates sont connues et tracées — elles n'empêchent pas `/create-epics` d'être lancé, mais les stories issues de ce sprint doivent être séquencées après résolution des gates.
