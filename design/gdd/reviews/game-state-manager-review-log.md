# Game State Manager — Review Log

> Historique des revues `/design-review` du GDD `design/gdd/game-state-manager.md`.
> Format : entrée par revue, ordre chronologique inverse (plus récente en haut).

---

## Review — 2026-04-24 — Verdict: NEEDS REVISION → APPROVED r1 (revisions appliquées en session)

**Mode** : `--depth lean` (single-session, scope ciblé GDD↔ADR coherence en fresh session, pas de specialist agents spawned)
**Reviewer** : Opus 4.7 (1M context) en auto-mode, fresh /clear session
**Scope signal** : **M** (Foundation system, ~150-300 LOC squelette estimé, API minimaliste, 4 formules simples, 18 ACs testables GUT directement, aucun nouvel ADR requis — ADR-0007 déjà Accepted r2)
**Specialists** : aucun (lean mode, scope ciblé éditorial GDD↔ADR)

### Findings

**Completeness** : 8/8 sections présentes + 3 bonus (Visual/Audio Requirements, UI Requirements, Open Questions).

**Dependency graph** :
- ✓ 5 GDDs upstream/peers existent (input-system, level-system, player-movement-system, camera-system, player-combat-system)
- ✗ 6 GDDs downstream NOT FOUND mais explicitement étiquetés `(inferred, Not Started)` + tracés en "Forward-looking réciprocité" l.345-350 (menu-system, save-load-system, checkpoint-system, shop-system, hud-system, audio-system) — pas un blocker, c'est de la documentation préfigurative attendue pour un Foundation system

**Cohérence GDD ↔ ADR-0007 (focus principal de la mission)** : **12 alignements forts validés**

| Concept | GDD ref | ADR-0007 ref | Verdict |
|---------|---------|--------------|---------|
| Enum State (5 values) | l.74-75, Rule 2 | D-2 | ✅ identique |
| Signal `state_changed(new_state)` 1 param zero-alloc | l.291, Rule 4 | D-3 + REQ-3 | ✅ identique |
| 5 verbes publics API | Rule 3, l.299-320 | D-10 | ✅ identique |
| `get_tree().paused` autorité unique GSM | Rule 5 | D-4 + R-1 | ✅ identique |
| Two-path scene transition (menu container vs étage additive) | Rule 6 | D-5 | ✅ identique |
| Auto-pause focus_lost conditional `PLAYING` only | Rule 9 | D-6 | ✅ identique |
| Respawn observation pure (timing owned Movement) | Rule 10 | D-7 | ✅ identique |
| Pattern pull au boot (no emit) | Rule 12 | D-9 | ✅ identique |
| Process_mode discipline | Rule 5 | D-4 table | ✅ identique |
| Idempotence verbes publics + handlers | Rule 3 + EC-1 | D-3 + REQ-4 | ✅ identique |
| CONNECT_DEFERRED died/respawned post level_active | Rule 10 + EC-5 | D-7 | ✅ identique |
| BOSS_DEFEATED terminal + request_new_run sortie | Rule 2 + matrice | D-8 | ✅ identique |

→ **Cohérence structurelle excellente.** GDD aligné strictement sur D-10 figée API. OQ-6 documente honnêtement le travail de réconciliation post-draft (8 alignements appliqués entre draft initial 9 verbes/10 signaux → ADR-0007 D-10 5 verbes/1 signal).

### Required Before Implementation (BLOCKING)

1. **Status ADR-0007 stale dans le GDD** — GDD l.9 indique `Proposed 2026-04-23` alors que l'ADR est `Accepted 2026-04-23 r2` (promu via `/architecture-review` r2 le même jour). OQ-4 entière obsolète.
2. **Header section non-conforme au standard projet** — GDD utilise `## Detailed Design` ; standard `.claude/rules/design-docs.md` + `design/CLAUDE.md` §3 exige `## Detailed Rules`.

### Recommended Revisions

3. **Référence stale `architecture.yaml l.125`** — La ligne 125 réelle = commentaire d'exemple Health System, pas l'enum State. Confirmé via lecture directe + note `last_updated` 2026-04-23 ligne 40 du registry : "State enum values NON registrés comme entries — ADR-0007 D-2 autorité unique". 3 occurrences à fixer (header l.9, Rule 2 l.42, commentaire bloc API l.287).
4. **Discrepancy `RESPAWN_DELAY` value entre GDD et ADR** — GDD Formula 2 : `0.05 s` (✅ aligné registry entities.yaml l.220 révisée Martin 2026-04-21). ADR-0007 D-6 rationale l.189 : `0.3s` (❌ stale). Fix réciproque côté ADR requis.
5. **Référence "ADR-0011 à venir"** — ADR-0011 existe (Status Proposed). Refs Rule 6 + Rule 8 à corriger.
6. **OQ-4 et OQ-6 closeable** — OQ-4 est la promotion Proposed→Accepted déjà exécutée 2026-04-23 r2. OQ-6 est un changelog historique pas une question ouverte. À marquer RESOLVED.

### Nice-to-Have

- Table mapping AC-GSM-* ↔ ADR-0007 VC-* (visibilité couverture croisée)
- Schéma de séquence respawn complet ASCII/Mermaid (séquence tick-par-tick Player.died → CONNECT_DEFERRED → GSM RESPAWNING → Movement RESPAWN_DELAY → Player.respawned → CONNECT_DEFERRED → GSM PLAYING)
- EC-12 softlock RESPAWNING : choix design délibéré (no safety timeout MVP) à surfacer dans QA test plan comme regression à monitorer en playtest

### Senior Verdict (synthèse single-session)

GDD très solide pour un Foundation system. Structure 8 sections complète + 3 bonus. API publique minimaliste (5 verbes + 1 signal + 1 getter), idiomatique Godot 4.6, **strictement alignée** sur ADR-0007 D-10 — les 12 contrôles d'alignement passent tous. Transparence sur la réconciliation post-draft (OQ-6 log de 8 alignements) exemplaire pour la maintenabilité.

Toutes les divergences détectées sont **artefacts de timing** (GDD drafté pendant que l'ADR était Proposed → promu Accepted r2 le même jour ; le GDD reflète l'ancien état). Aucune divergence substantielle de design ou d'architecture. Fix éditorial < 15 min.

GDD **implementable directement** : pseudocode boot/handlers fourni, process_mode tableau précis, contrats signaux explicites, formulas avec ranges + exemples calculés. Couverture des edge cases (13 ECs) exhaustive. Player Fantasy "système indirect" articulation fine et juste pour un Foundation orchestrator.

### Verdict initial : NEEDS REVISION

2 BLOCKING + 4 RECOMMENDED + 3 Nice-to-Have. Tous fix < 15 min.

### Resolution : APPROVED r1 (revisions accepted en session)

**6 fixes appliqués au GDD `design/gdd/game-state-manager.md`** :
1. ✅ Ligne 9 : Status ADR-0007 `Proposed 2026-04-23` → `Accepted 2026-04-23 r2`
2. ✅ Ligne 36 : Header `## Detailed Design` → `## Detailed Rules` (sous-section `### Core Rules` inchangée)
3. ✅ Ligne 9 + Rule 2 l.42 + commentaire bloc API l.287 : refs `architecture.yaml l.125` → `ADR-0007 D-2` autorité
4. ✅ Rule 6 l.50 + Rule 8 l.54 : `ADR-0011 à venir` → `ADR-0011 (Proposed)`
5. ✅ OQ-4 l.525 : marquée `[RESOLVED 2026-04-23 r2]` avec historique scénario (b)
6. ✅ OQ-6 l.554 : marquée `[RESOLVED — historical appendix]`

**1 fix réciproque appliqué côté ADR `docs/architecture/adr-0007-game-state-manager.md`** :
- ✅ D-6 rationale l.189 : `RESPAWN_DELAY court, 0.3s` → `RESPAWN_DELAY court, 0.05 s = 3 ticks @ 60 Hz, valeur registry canonique entities.yaml l.220` + note explicative correction réciproque

Les 3 Nice-to-Have sont reportés (non-bloquants, peuvent être adressés lors des stories d'implémentation Sprint 1 ou re-review futur).

**Status final** : `Designed r1 (pending fresh /design-review)` → **`APPROVED r1`** — débloque `/create-epics game-state-manager` + consolidation `/architecture-review` (G-6 Gap architecture closed).

**Files modified** :
- `design/gdd/game-state-manager.md` (6 edits)
- `docs/architecture/adr-0007-game-state-manager.md` (1 edit réciproque)
- `design/gdd/systems-index.md` (Last Updated header + ligne 21 Status colonne)
- `design/gdd/reviews/game-state-manager-review-log.md` (NEW — ce fichier)

**Prior verdict resolved** : First review (no prior).

---
