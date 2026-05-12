# Story 008: Visual/Feel Playtest — "Court / Sec / Désaturé / Percussif" (Pillar 2 Verbatims)

> **Epic**: VFX System
> **Status**: **Blocked** (panel ≥ 5 testeurs Martin pending recrutement)
> **Layer**: Presentation
> **Type**: Visual/Feel ADVISORY
> **Manifest Version**: 2026-05-04
> **Estimate**: M (1 jour session × 5 testeurs + analyse verbatims + sign-off creative-director + game-designer)

> **Blocked** : panel ≥ 5 testeurs × 1 session 10 min combat room focus pending recrutement Martin. Pattern combat story-019 (`combat-feel-playtest-protocol.md`) protocole calque.

## Context

**GDD**: `design/gdd/vfx-system.md` (Designed r1)
**Requirements** :
- §Player Fantasy — North Star : *"Le sang gicle court, sec, désaturé. La salle se ride à peine — c'est le mouvement du joueur qui peint, pas l'effet qui s'étale."*
- §Player Fantasy — Pillar 2 (LA PROGRESSION SE VOIT) primaire — decals = mémoire physique de chaque run, salle "marquée" au respawn
- §Player Fantasy — Pillar 1 (FLOW AVANT TOUT) garde-fou par soustraction radicale — pas de slow-motion VFX additionnel, pas d'effet persistant > 400 ms

**ADR Governing**: aucun ADR-spécifique — Visual/Feel ADVISORY orientée verbatims qualitatifs.

**Engine**: Godot 4.6 | **Risk**: LOW (validation qualitative humaine)
**Engine Notes**: N/A — playtest manuel.

**Control Manifest Rules (Presentation layer)**:
- Required : panel ≥ 5 testeurs (anti-référence Mirror's Edge / Hotline Miami / Ghostrunner — testeurs aware genre FPS staccato) ; session 10 min combat room focus minimal (1-2 salles avec 8-15 enemies) ; questions ouvertes verbatim collection ; sign-off creative-director + game-designer.
- Forbidden : leading questions ("c'était spectaculaire ?", "c'était satisfaisant ?") — biais confirmation banni ; testeurs aware Pillar 2 / Chrome Zen avant playtest (biais Hawthorne — interroger AVANT de mentionner refs).
- Guardrail : si lexique attendu absent OU mots BANNIS présents → calibrage VFX atténué (réduire `BLOOD_SPURT_PARTICLE_COUNT` 6 → 4, réduire `KATANA_TRAIL_OPACITY_MAX` 0.7 → 0.5, raccourcir `PARTICLE_LIFETIME_MS` 400 → 300).

---

## Acceptance Criteria

*From GDD §Acceptance Criteria r1 — Visual/Feel ADVISORY :*

- [ ] **AC-VFX-28** [ADVISORY][PLAYTEST] **GIVEN** un panel de 5 testeurs joue 10 minutes de gameplay actif (combat room focus), **WHEN** ils sont interrogés sur les effets de kill avec des mots ouverts, **THEN** le lexique attendu inclut : **"court", "sec", "désaturé", "percussif"** (≥ 3/4 verbatims présents dans ≥ 4/5 testeurs) ; les **mots BANNIS** absents des verbatims : **"spectaculaire", "satisfaisant", "juteux", "gore", "flashy", "impressionnant"** (0/5 testeurs présents).
- [ ] **AC-VFX-29** [ADVISORY][PLAYTEST] **GIVEN** un testeur termine une salle de 10 enemies, **WHEN** il revient dans la salle après respawn, **THEN** il reconnaît visuellement les traces de combat précédent (decals) et peut décrire la salle comme **"marquée"** ou **"parcourue"** sans tutoriel (≥ 4/5 testeurs).

---

## Implementation Notes

### Protocole playtest (calque combat story-019 `combat-feel-playtest-protocol.md`)

**Setup environnement** :
- Build MVP avec stories 001-007 implémentées + smoke test pass
- Salle test : 1-2 salles standard avec 8-15 enemies (cohérent Combat tutorial / mid-game density)
- Hardware : laptop entry-level Steam Deck-tier (target perf VFX ≤ 50 draw calls)
- Recording : screencap + audio commentaire (think-aloud protocol)
- Reduce_flash + reduce_motion **OFF** par défaut (test la version "full intensity")

**Recrutement** : 5 testeurs minimum
- Profil : aware genre FPS / parkour (Mirror's Edge / Ghostrunner / Hotline Miami refs)
- Mix : 2 expérimentés FPS + 2 casual + 1 dev pair (peer review)
- Pas d'aware Pillar 2 / Chrome Zen / VFX design intent avant playtest

**Sessions individuelles** : 10 minutes par testeur
1. **Brief intro** (1 min) : "Tu vas jouer 5 minutes dans une salle de combat. Concentre-toi sur les sensations. Tu peux parler à voix haute (think-aloud)."
2. **Playtest libre** (5-7 min) : combat room avec 8-15 enemies (kills répétés, multi-kills, decals s'accumulent visuellement)
3. **Respawn intentionnel** (1 min) : tester `respawned` — tester revient salle déjà combattue
4. **Interview ouverte** (2-3 min) : questions sans leading

**Questions ouvertes (verbatim collection)** :
1. "Décris-moi en quelques mots ce que tu ressens quand tu tues un ennemi."
2. "Comment décrirais-tu visuellement les effets ? (couleurs, durée, intensité)"
3. "Quand tu reviens dans la salle après être mort, qu'est-ce que tu remarques ?"
4. "Sur une échelle 1-10, à quel point l'effet est-il **spectaculaire** ? (ne pas demander si c'est satisfaisant — laisser émerger spontanément)"
5. "Si tu devais comparer à un autre jeu, lequel viendrait à l'esprit ?"

**Verbatim analysis** :
- Lister tous les adjectifs prononcés (≥ 2× par testeur ou explicitement nommés)
- Compter occurrences "court", "sec", "désaturé", "percussif", "propre", "staccato", "minimaliste" — lexique attendu
- Compter occurrences "spectaculaire", "satisfaisant", "juteux", "gore", "flashy", "impressionnant", "épique" — mots BANNIS
- Cross-référencer mention "Mirror's Edge" / "Hotline Miami" / "Ghostrunner" — anti-référence positive (Pillar 2)
- Cross-référencer mention "DOOM Eternal" / "Shadow Warrior 3" / "glory kill" — anti-référence négative (anti-Pillar 1)

**Sign-off matrix** :

| Critère | Threshold | Status |
|---------|-----------|--------|
| AC-VFX-28 lexique attendu présent | ≥ 3/4 mots dans ≥ 4/5 testeurs | TBD |
| AC-VFX-28 mots BANNIS absents | 0/5 testeurs | TBD |
| AC-VFX-29 salle "marquée" reconnue | ≥ 4/5 testeurs | TBD |
| Reference Mirror's Edge / Ghostrunner | ≥ 2/5 testeurs | bonus |
| Reference DOOM Eternal / glory kill | 0/5 testeurs | red flag |

**Calibrage si fail** :

Si AC-VFX-28 fail (lexique attendu absent OU mots BANNIS présents) :
- Réduire `BLOOD_SPURT_PARTICLE_COUNT` 6 → 4 (Tuning Knob safe range [0, 16])
- Réduire `KATANA_TRAIL_OPACITY_MAX` 0.7 → 0.5 (Tuning Knob safe range [0.3, 1.0])
- Raccourcir `PARTICLE_LIFETIME_MS` 400 → 300 (Tuning Knob safe range [200, 800])
- Re-test sur 2-3 testeurs (mini-panel)

Si AC-VFX-29 fail (salle pas reconnue "marquée") :
- Augmenter `MAX_DECALS_PER_ROOM` 32 → 48 (safe range [8, 64])
- OU augmenter `DECAL_SIZE` 0.6 → 0.8 m (safe range [0.3, 1.2])
- Re-test

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Stories 001-007 : implémentation VFX production (cette story-008 valide qualitativement le résultat)
- Performance budget runtime (60 s × 30 kills MEMORY_STATIC) — peut être validé par run manuel post-impl stories 002-006
- Accessibility playtest dédié (reduce_flash / reduce_motion) — différer story future ou couvert par accessibility-system epic 1/1 Complete + ADR-0015 D-1 contrats vérifiés
- Boss VFX (OQ-VFX-5 Tier 3) — hors scope MVP
- Cross-room decal persistence (OQ-VFX-1 Tier 2+) — hors scope MVP
- Trail technique decision Trail3D vs ImmediateMesh (OQ-VFX-3) — décision lead-programmer Sprint 1, orthogonal au playtest qualitatif

---

## QA Test Cases

*Visual/Feel ADVISORY — playtest manuel + sign-off humain :*

**AC-VFX-28** : Lexique attendu vs mots BANNIS
- Setup : panel ≥ 5 testeurs, build MVP stories 001-007 implémentées, salle combat room 8-15 enemies, recording screencap + audio.
- Action : 5 sessions × 10 min playtest + interview ouverte.
- Verify : verbatim analysis — lexique attendu "court / sec / désaturé / percussif" présent ≥ 3/4 mots dans ≥ 4/5 testeurs ; mots BANNIS "spectaculaire / satisfaisant / juteux / gore / flashy / impressionnant" absents 0/5 testeurs.
- Pass : sign-off creative-director + game-designer dans `production/qa/evidence/vfx-feel-playtest-{date}.md`.

**AC-VFX-29** : Salle "marquée" reconnue post-respawn
- Setup : 5 testeurs jouent salle 10 enemies puis respawn intentionnel (Pillar 3 — 50 ms wall-clock).
- Action : "Quand tu reviens dans la salle, qu'est-ce que tu remarques ?" question ouverte.
- Verify : ≥ 4/5 testeurs décrivent salle comme "marquée", "parcourue", "déjà visitée", "ensanglantée" SANS tutoriel — Pillar 2 progression visible.
- Pass : sign-off cross-référence creative-director + game-designer.

---

## Test Evidence

**Story Type**: Visual/Feel ADVISORY
**Required evidence**:
- `production/qa/evidence/vfx-feel-playtest-{date}.md` (NEW) — verbatim analysis 5 testeurs + sign-off matrix + calibrage decisions si applicable.
- Recordings screencap + audio (gitignored, optionnel — référence cross-team)
- Sign-off creative-director (`docs/sign-offs/{date}-vfx-feel.md` ou commentaire commit) + game-designer.

**Status**: [ ] Blocked — pending recrutement panel Martin (≥ 5 testeurs).

---

## Dependencies

- **Hard upstream** : stories 001-007 implémentées + smoke test pass (build MVP fonctionnel pour playtest).
- **Cross-system** :
  - **Combat 20/22 Complete** + **Enemy 6/6 Complete** + **Camera 13/13 Complete** + **AccessibilityService Ready** — disponibles production ✅.
  - **GameStateManager autoload Not Started** — peut être stub minimal pour playtest (state PLAYING fixé) ; non-bloquant tant que combat room playable.
- **Cross-references** :
  - Pattern combat story-019 `combat-feel-playtest-protocol.md` — calque protocole playtest panel ≥ 5 testeurs (pending recrutement Martin commun aux deux stories).
  - Pattern HUD story-006 `visual-feel-frame-perfect-playtest.md` — calque structure ADVISORY MANUAL.
- **Unlocks** : aucune downstream — close-out Pillar 2 (LA PROGRESSION SE VOIT) verbatims qualitatifs pour VFX.

---

## Notes

**Pourquoi Blocked** : Recrutement panel Martin (≥ 5 testeurs) est un goulot d'étranglement commun à plusieurs stories Visual/Feel ADVISORY (combat-019, HUD-006, VFX-008, futures playtest stories). Pattern : ces stories restent "Blocked" jusqu'à session panel Martin organisée — déférée build MVP. Les 7 autres stories VFX (001-007) peuvent être livrées sans dépendre de ce panel.

**Mots BANNIS — pourquoi exclure "satisfaisant"** : Le terme "satisfaisant" est commun aux jeux glory-kill (DOOM Eternal, Shadow Warrior 3) qui célèbrent le kill comme récompense cathartique. CHROME://ASCENT positionne le kill comme **constatation rythmique** (Pillar 1 staccato), pas célébration. Si testeurs disent "satisfaisant", il y a calibrage drift vers anti-Pillar 1.

**Mots attendus — pourquoi inclure "désaturé"** : "Désaturé" prouve que le testeur perçoit la palette Chrome Zen (rouge sang `#C8232C` 60% saturation, pas rouge pur) — vocabulary visual literacy → Pillar 2 vision design réussie.
