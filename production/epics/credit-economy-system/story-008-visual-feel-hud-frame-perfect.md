# Story 008: Visual/Feel HUD frame-perfect (ADVISORY)

> **Epic**: Credit Economy System
> **Status**: **Ready** (Unblocked 2026-05-04)
>
> **UNBLOCKED 2026-05-04** : epic HUD créé (`production/epics/hud-system/EPIC.md`). Stories HUD couvrent l'AC-CRD-46 :
> - **HUD story-002** (`story-002-pull-pattern-credits-changed-listener.md` — Type Integration, Ready) implémente le listener `_on_credits_changed(total, delta, source)` SYNC same-frame qui met à jour `Label.text` dans le même `_physics_process` tick que le kill (Pillar 1 garde-fou technique).
> - **HUD story-006** (`story-006-visual-feel-frame-perfect-playtest.md` — Type Visual/Feel ADVISORY, Blocked sur build MVP playable) produit l'evidence frame-by-frame screencap + sign-off lead-designer.
>
> **Convergence stratégie** : cette story-008 sera **close-out par evidence shared avec hud-006** OU **subsumed par hud-006** au moment du close-out Sprint Multi-Epic (post-build MVP). Décision finale au moment de close-out :
> - **Option A — Subsume** : credit-008 fermée par hud-006, credit-008 marquée "Closed — subsumed by hud-006" avec cross-link.
> - **Option B — Shared evidence** : evidence file `production/qa/evidence/hud-frame-perfect-evidence-[date].md` référencée par les deux stories ; chacune close indépendamment.
>
> En attendant, credit-008 reste **Ready** (pas Blocked) — la dépendance HUD est techniquement résolue (listener spec écrite, lints CI prévus, pulse différencié source spec écrit). Le seul prérequis restant est l'**implémentation effective** des stories HUD-002 + HUD-006 + le build MVP playable Sprint Multi-Epic.
> **Layer**: Feature
> **Type**: Visual/Feel
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/credit-economy-system.md`
**Requirement**: AC-CRD-46 (gain crédit kill — chiffre HUD monte visiblement dans le **même frame** que le kill, effet "récompense immédiate" perceptible sans latence — Pillar 1 FLOW + Pillar 2 LA PROGRESSION SE VOIT).
*(TR-crd-* IDs non encore présents dans `tr-registry.yaml` — référence directe AC GDD r3.)*

**ADR Governing Implementation**:
- Aucun ADR direct — la conformité visuelle dépend de l'implémentation HUD System (épic séparé) qui consume `credits_changed` SYNC. Cette story Credit ne fait QUE garantir l'émission SYNC (déjà couverte par AC-CRD-29 story 001) ; la perception visuelle est validée par playtest evidence.

**ADR Decision Summary**: La latence d'affichage du compteur HUD est garantie côté Credit par l'émission SYNC `credits_changed` dans le même `_physics_process` que `enemy_killed` (AC-CRD-29). Le test ADVISORY playtest confirme que cette garantie technique se traduit bien en perception "frame-perfect" côté joueur — capture screencap ou vidéo frame-by-frame + sign-off lead designer.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: aucun. Capture vidéo via OBS / Godot built-in screen recorder ou Capture FX `MoviewWriter` (Godot 4.6). Frame-by-frame analysis via VLC ou ffmpeg.

**Control Manifest Rules (Feature layer)**:
- Required: evidence file dans `production/qa/evidence/credit-hud-frame-perfect-evidence.md` ; sign-off lead-designer (creative-director ou game-designer agent dans le pipeline solo).
- Forbidden: marquer ADVISORY comme "passed" sans evidence visuelle réelle (capture screen ou vidéo) — c'est le **point** d'un gate ADVISORY.
- Guardrail: pas de gate BLOCKING en CI — cette story ne bloque jamais un merge.

---

## Acceptance Criteria

*From GDD §Acceptance Criteria, scoped à cette story (Visual/Feel ADVISORY) :*

- [ ] AC-CRD-46 [Visual/Feel] **ADVISORY** — kill grunt enregistré → chiffre HUD monte dans le **même frame** que le kill, effet "récompense immédiate" perceptible sans latence d'affichage. Mécanisme : playtest evidence (screencap ou vidéo frame-by-frame) + sign-off lead designer.

---

## Implementation Notes

*Visual/Feel — pas de code à écrire ; produire l'evidence et le sign-off.*

1. **Pré-requis** : HUD System epic implémenté avec listener `_on_credits_changed(total, delta, source)` qui met à jour le compteur. Si HUD epic n'est pas encore implémenté à ce moment, cette story 008 reste `Ready` mais ne peut pas être close — la dépendance HUD est explicite.

2. **Setup capture** :
   - Lancer le jeu en mode debug ou release.
   - Naviguer vers étage 1 avec un grunt.
   - Activer la capture (OBS ou `MovieWriter` Godot — `Project > MovieWriter > Output File` avec frame rate 60).
   - Tuer le grunt avec katana, capturer ~1 seconde de vidéo couvrant le moment d'impact.

3. **Analyse frame-by-frame** :
   - Ouvrir la vidéo dans VLC (touche `e` pour avancer image par image) ou ffmpeg :
     ```bash
     ffmpeg -i capture.mp4 -vf "fps=60" -frame_pts true frames/%04d.png
     ```
   - Identifier la frame F0 = moment où l'ennemi disparaît (mort visible).
   - Identifier la frame F1 = moment où le compteur HUD passe de N à N+1.
   - **Pass** : `F1 == F0` (même frame) ou `F1 == F0+1` (1 frame de délai max acceptable, dans le budget de tolérance perceptuelle 16.6 ms).
   - **Fail** : `F1 > F0+1` — perception "lag" possible, violation Pillar 1.

4. **Documentation evidence** : créer `production/qa/evidence/credit-hud-frame-perfect-evidence.md` :
   ```markdown
   # Evidence — AC-CRD-46 HUD frame-perfect

   **Date** : 2026-MM-DD
   **Build** : commit SHA
   **Capture** : production/qa/evidence/credit-hud-frame-perfect-capture.mp4
   **Frames extraites** : production/qa/evidence/credit-hud-frame-perfect/

   ## Setup
   - Étage 1, premier grunt MVP
   - Resolution 1920x1080, 60 fps lock vsync
   - Hardware : [machine specs]

   ## Analyse
   - F0 (mort grunt visible) = frame 0123
   - F1 (HUD passe N → N+1) = frame 0123
   - Delta : 0 frames

   ## Verdict
   ✅ PASS — gain crédit visible dans le même frame que le kill (Pillar 1 + Pillar 2 satisfaits).

   ## Sign-off
   - Reviewer : [creative-director / game-designer]
   - Date : 2026-MM-DD
   ```

5. **En mode solo auto-approve** : la story peut être close avec evidence partiellement manuelle (screencap + analyse rapide) si HUD epic est implémenté. Si HUD epic n'existe pas encore, la story reste `Ready` jusqu'à ce que le matériel d'analyse soit disponible.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- L'implémentation HUD listener `_on_credits_changed` — appartient à HUD epic (à créer post-Credit MVP).
- L'animation pulse cyan, durées tween, easing curves — appartiennent à HUD GDD §J.
- Différenciation visuelle KILL vs SECRET — Pillar 4 viscéralité, appartient à HUD r1.1 Rule 5.

---

## QA Test Cases

*Visual/Feel — manual verification steps (pas de test automatisé) :*

- **AC-CRD-46** **Manual check** :
  - **Setup** : Build release Godot 4.6, étage 1 chargé avec ≥1 grunt visible. Capture vidéo 60 fps activée.
  - **Action** : Tuer 1 grunt avec katana (single swing).
  - **Verify** : Extraire les frames de la vidéo (ffmpeg). Identifier F0 (mort visible grunt) et F1 (compteur HUD incrémenté). Calculer `delta = F1 - F0`.
  - **Pass condition** : `delta ∈ [0, 1]` (frame-perfect ou 1 frame de tolérance, soit ≤ 16.6 ms latence visuelle). Documenter dans evidence file + sign-off lead-designer.
  - **Fail condition** : `delta > 1` — relancer test après vérification de la chaîne SYNC `enemy_killed → credits_changed → HUD listener` (peut indiquer un `CONNECT_DEFERRED` quelque part dans la chaîne).

---

## Test Evidence

**Story Type**: Visual/Feel (ADVISORY)
**Required evidence**:
- `production/qa/evidence/credit-hud-frame-perfect-evidence.md` (capture vidéo + analyse frame-by-frame + sign-off).
- Optionnellement : `production/qa/evidence/credit-hud-frame-perfect-capture.mp4` ou screencap PNGs.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: **Story 002** (handler `_on_enemy_killed` implémenté et émettant `credits_changed`), **Story 004** (Persistence — `_is_hydrated` et guards en place pour le boot du test). **HARD UPSTREAM EXTERNE** : HUD epic implémenté avec listener `_on_credits_changed` mettant à jour le compteur visuel. Sans HUD, cette story ne peut pas être validée.
- Unlocks: aucune story (gate ADVISORY de fin de cycle Credit).
