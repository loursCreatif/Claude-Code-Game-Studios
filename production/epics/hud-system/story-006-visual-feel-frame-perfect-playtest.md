# Story 006: Visual/Feel HUD Frame-Perfect Playtest (ADVISORY) — Cross-Reference Credit-008 Close-Out

> **Epic**: HUD System
> **Status**: **Blocked** — recrutement panel Martin OU evidence frame-by-frame screencap autonome. Cette story ne peut PAS être close avant que les stories 001-005 soient livrées (HUD listener + visibility + pulse différencié + lints) ET qu'un build MVP playable soit disponible. Cross-reference convergence avec `credit-economy-system/story-008-visual-feel-hud-frame-perfect.md` AC-CRD-46 — cette story-006 **subsume** credit-008 OU credit-008 close-out par evidence shared (clarification au moment de close-out).
> **Layer**: Presentation
> **Type**: Visual/Feel
> **Manifest Version**: 2026-05-04
> **Estimate**: M (3-5 h preparation + 1 session playtest 30-60 min + 2 h analyse frame-by-frame + writeup evidence + sign-off)

## Context

**GDD**: `design/gdd/hud-system.md` (In Design r1.1)
**Requirement**: AC-HUD-23 ADVISORY PLAYTEST (source-dependent feedback distinguable visuellement KILL vs SECRET — observateur humain), AC-HUD-30 ADVISORY MANUAL (toggle plein écran ↔ fenêtré — counter reste positionné selon anchor), Pillar 1 FLOW frame-perfect garde-fou + Pillar 2 LA PROGRESSION SE VOIT primaire.

**Cross-reference unblock** : Cette story **débloque** `production/epics/credit-economy-system/story-008-visual-feel-hud-frame-perfect.md` (Blocked sur absence epic HUD). AC-CRD-46 demande `delta = F1 - F0 ∈ [0, 1]` frames entre kill visible et HUD update. La garantie technique SYNC est portée par story-002 (`_on_credits_changed` SYNC same-frame) ; cette story-006 valide la **perception humaine** par evidence playtest + sign-off lead-designer.

**ADR Governing Implementation**:
- Aucun ADR direct — la conformité visuelle dépend de l'implémentation HUD (stories 001-004) qui consume `credits_changed` SYNC. Cette story confirme que la garantie technique se traduit en perception "frame-perfect" + différenciation KILL/SECRET côté joueur.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Capture vidéo via OBS / Godot built-in `MovieWriter` (Godot 4.6 stable) ou screen recorder OS. Frame-by-frame analysis via VLC (touche `e`) ou ffmpeg.

**Control Manifest Rules (Presentation layer)**:
- Required : evidence file `production/qa/evidence/hud-frame-perfect-evidence-[date].md` ; capture vidéo 60 fps minimum ; sign-off lead-designer (creative-director ou game-designer agent dans pipeline solo).
- Forbidden : marquer ADVISORY comme "passed" sans evidence visuelle réelle (capture screen ou vidéo) — c'est le **point** d'un gate ADVISORY.
- Guardrail : pas de gate BLOCKING en CI — cette story ne bloque jamais un merge, mais elle doit être close avant `/gate-check production` (epic HUD complet).

---

## Acceptance Criteria

*From GDD §Acceptance Criteria r1.1, scoped à cette story (Visual/Feel ADVISORY) :*

- [ ] **AC-HUD-23** [ADVISORY][PLAYTEST] **GIVEN** `credits_changed(total, delta, SourceKind.SECRET)` reçu avec delta ≥ `BASE_SECRET_CREDIT_T1` (≥ 5), **WHEN** le tween démarre, **THEN** un observateur humain distingue visuellement ce feedback de SourceKind.KILL — la décision de design (flash cyan vs neutre OU durée différenciée) doit être documentée Visual section avant impl. ADVISORY jusqu'à OQ-HUD-1 résolue. **MVP r1.1** : différenciation par durée (KILL=100ms vs SECRET=150ms) suffit ; flash cyan F-HUD-3 latent Tier 2+.
- [ ] **AC-HUD-30** [ADVISORY][MANUAL] **GIVEN** jeu en plein écran, **WHEN** toggle vers fenêtré, **THEN** counter reste positionné selon anchor — observateur humain confirme lisibilité sans dérive de position. *Note* : text scaling Tier 3 hors scope MVP.
- [ ] **AC-CRD-46 cross-reference** [Visual/Feel — ADVISORY] (credit-008 convergence) — kill grunt enregistré → chiffre HUD monte dans le **même frame** que le kill, effet "récompense immédiate" perceptible sans latence d'affichage. Mécanisme : playtest evidence (screencap ou vidéo frame-by-frame) + sign-off lead designer. **Pass** : `delta = F1 - F0 ∈ [0, 1]` (frame-perfect ou 1 frame de tolérance ≤ 16.6 ms).

---

## Implementation Notes

*Visual/Feel — pas de code à écrire ; produire l'evidence et le sign-off.*

### Setup capture (préparation 30-60 min)

1. **Pré-requis** : stories 001-005 Complete (HUD autoload + listener SYNC + visibility state + pulse différencié + lints CI green). Build MVP playable disponible (Sprint Multi-Epic Sprint A livré : Movement + Camera + Level + Combat + Credit + HUD).
2. **Setup capture** :
   - Lancer le jeu en mode debug ou release.
   - Naviguer vers étage 1 avec ≥1 grunt + ≥1 secret tier-1 collectable.
   - Activer la capture vidéo 60 fps :
     - **Option A** : OBS (recording 60 fps locked).
     - **Option B** : Godot `MovieWriter` (`Project > MovieWriter > Output File` + `--write-movie capture.mp4 --fixed-fps 60` flag CLI).
     - **Option C** : screen recorder OS (macOS QuickTime 60 fps).
3. **Scénarios à capturer** (1-2 sec chacun) :
   - **Scénario A — KILL** : tuer 1 grunt avec katana (single swing).
   - **Scénario B — SECRET** : collecter 1 secret tier-1 (delta=+5).
   - **Scénario C — Multi-kill** : tuer 3 grunts dans même swing (`MAX_KILLS_PER_SWING = 3`).
   - **Scénario D — KILL + SECRET combo** : kill 1 grunt puis collecter 1 secret 500ms+ après (différenciation tween durée 100 vs 150ms perceptible).
   - **Scénario E — Resize toggle** (AC-HUD-30 MANUAL) : pendant gameplay, toggle plein écran ↔ fenêtré 2-3 fois.

### Analyse frame-by-frame (1-2 h)

4. **Extraction frames** :
   ```bash
   ffmpeg -i capture.mp4 -vf "fps=60" -frame_pts true frames/%04d.png
   ```
5. **Identification frames clés** par scénario :
   - **Scénario A KILL** : F0 = frame mort grunt visible (corps disparaît) ; F1 = frame `Label.text` passe N → N+1.
     - **Pass** : `F1 == F0` ou `F1 == F0+1` (1 frame tolérance ≤ 16.6 ms).
     - **Fail** : `F1 > F0+1` — perception "lag" possible, violation Pillar 1.
   - **Scénario B SECRET** : F0 = frame collect visible (icône secret consumed) ; F1 = frame `Label.text` passe N → N+5.
     - **Pass** : `F1 == F0` ou `F1 == F0+1`.
   - **Scénario C Multi-kill** : F0 = swing impact frame ; F1/F2/F3 = 3 frames consécutifs `Label.text` saute N→N+1→N+2→N+3.
     - **Pass** : tous dans même frame (SYNC) ou maximum 1 frame étalé.
   - **Scénario D KILL+SECRET** : observer durée pulse KILL (~100ms = ~6 frames) vs SECRET (~150ms = ~9 frames) — différenciation ≥ 3 frames perceptible.
     - **Pass** : observateur humain distingue les deux pulses comme "différents" (sign-off subjectif lead-designer).
   - **Scénario E Resize toggle** : counter reste in-bounds top-right, pas de dérive position out-of-screen.
     - **Pass** : observateur humain confirme lisibilité.

### Documentation evidence

6. **Créer evidence file** `production/qa/evidence/hud-frame-perfect-evidence-[date].md` :
   ```markdown
   # Evidence — HUD frame-perfect (AC-HUD-23 + AC-HUD-30 + AC-CRD-46)

   **Date** : 2026-MM-DD
   **Build** : commit SHA
   **Capture** : production/qa/evidence/hud-frame-perfect-capture.mp4
   **Frames extraites** : production/qa/evidence/hud-frame-perfect/

   ## Setup
   - Étage 1, premier grunt + secret tier-1 MVP
   - Resolution 1920x1080, 60 fps lock vsync
   - Hardware : [machine specs]

   ## Scénario A — KILL frame-perfect
   - F0 (mort grunt visible) = frame 0123
   - F1 (HUD passe N → N+1) = frame 0123
   - Delta : 0 frames ✅ PASS

   ## Scénario B — SECRET frame-perfect
   - F0 (collect secret visible) = frame 0456
   - F1 (HUD passe N → N+5) = frame 0457
   - Delta : 1 frame ✅ PASS (tolérance ≤ 16.6 ms)

   ## Scénario C — Multi-kill 3 emits same tick
   - F0 (swing impact) = frame 0789
   - F1 (HUD N → N+3) = frame 0789
   - Delta : 0 frames ✅ PASS — Label saute N → N+3 sans frame intermédiaire visible

   ## Scénario D — KILL+SECRET differentiation (AC-HUD-23)
   - Pulse KILL : pic frame 0900-0906 (~6 frames = 100ms ✅)
   - Pulse SECRET : pic frame 0930-0939 (~9 frames = 150ms ✅)
   - Différenciation perçue : ✅ observable distinctement (lead-designer sign-off)

   ## Scénario E — Resize toggle (AC-HUD-30 MANUAL)
   - Plein écran 1920x1080 → fenêtré 1280x720 → plein écran
   - Counter reste anchored top-right, in-bounds, lisible ✅ PASS

   ## Verdict global
   ✅ PASS — gain crédit visible dans le même frame que kill/secret (Pillar 1 + Pillar 2 satisfaits) ; différenciation source perceptible (Pillar 4 viscéralité MVP minimum) ; resize toggle stable (AC-HUD-30 MANUAL).

   ## Sign-off
   - Reviewer : [creative-director / game-designer]
   - Date : 2026-MM-DD
   - Signature : [name]

   ## Cross-reference close-out
   - AC-CRD-46 BLOCKING dépendance externe HUD listener `_on_credits_changed` ✅ RESOLVED — story-002 implémente le listener SYNC ; evidence cumulée par cette story-006 ferme credit-008 (subsumed OR shared evidence).
   - credit-008 status updated → Closed/Subsumed avec référence cross-link.
   ```

### Mode solo auto-approve

7. **Si build MVP playable disponible et sign-off solo Martin** : la story peut être close avec evidence partiellement manuelle (screencap + analyse rapide) si lead-designer agent dans pipeline solo accepte. Si build MVP n'existe pas encore (Sprint Multi-Epic non livré), la story reste **Blocked** jusqu'à ce que le matériel d'analyse soit disponible.

8. **Cascade Audio Rule 17 cross-reference** : pendant playtest Scénario D, observer également la cohérence audio — clac aigu pitch +5 semitones au moment SECRET (Audio Rule 17) cohérent avec pulse HUD durée +50%. Sign-off cross-system (creative-director).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- L'implémentation HUD listener `_on_credits_changed` — story-002.
- Pulse durée différenciée KILL/SECRET — story-004.
- Lints statiques anti-patterns — story-005.
- Différenciation magnitude SECRET (Tier 2+ knob `PULSE_SCALE_MAGNITUDE_SECRET`) — déféré.
- Flash cyan F-HUD-3 (Tier 2+ knob `HUD_SECRET_FLASH_ENABLED`) — déféré OQ-HUD-1.
- Animation pulse durées, easing curves, color transitions — owned story-004.

---

## QA Test Cases

*Visual/Feel — manual verification steps (pas de test automatisé) :*

**AC-HUD-23 + AC-HUD-30 + AC-CRD-46** **Manual checks** :
- **Setup** : Build release Godot 4.6, étage 1 chargé avec ≥1 grunt + 1 secret tier-1. Capture vidéo 60 fps activée.
- **Action** : Exécuter Scénarios A-E ci-dessus (kill / secret / multi-kill / kill+secret combo / resize toggle).
- **Verify** : Extraire les frames de la vidéo (ffmpeg) ; identifier F0/F1 par scénario ; calculer `delta = F1 - F0` ; documenter dans evidence file ; sign-off lead-designer.
- **Pass condition global** : tous scénarios `delta ∈ [0, 1]` frames + différenciation KILL/SECRET perceptible + resize toggle stable. Documenter dans evidence file + sign-off lead-designer.
- **Fail condition** : `delta > 1` frame OU différenciation KILL/SECRET imperceptible OU resize toggle dérive position — relancer après vérification chaîne SYNC `enemy_killed → credits_changed → HUD listener` (peut indiquer un `CONNECT_DEFERRED` quelque part dans la chaîne) OU recalibration durée tween (story-004 amendement Tuning Knobs).

---

## Test Evidence

**Story Type**: Visual/Feel (ADVISORY)
**Required evidence**:
- `production/qa/evidence/hud-frame-perfect-evidence-[date].md` (capture vidéo + analyse frame-by-frame + sign-off lead-designer).
- `production/qa/evidence/hud-frame-perfect-capture.mp4` ou screencap PNGs.
- Optionnellement : extraction frames PNG pour réplicabilité.

**Cross-reference** :
- Cette story **subsume** OR **partage evidence** avec `production/epics/credit-economy-system/story-008-visual-feel-hud-frame-perfect.md` AC-CRD-46. Au moment de close-out (Sprint Multi-Epic post-build MVP), clarifier si :
  - **Option A — Subsume** : story-006 close credit-008 directement, credit-008 marquée "Closed — subsumed by hud-006".
  - **Option B — Shared evidence** : evidence file partagée référencée par les deux stories ; chacune close indépendamment avec mention cross-link.

**Status**: [ ] Not yet created — Blocked sur build MVP playable + recrutement panel Martin OU evidence solo auto.

---

## Dependencies

- **Hard upstream** :
  - Stories 001-005 Complete (HUD autoload + listener SYNC + visibility state + pulse différencié source + lints CI green).
  - Build MVP playable Sprint Multi-Epic Sprint A — Movement / Camera / Level / Combat / Credit Economy / HUD tous livrés et intégrés.
  - GameStateManager autoload boot Sprint A (sans GSM, HUD ne reçoit pas `state_changed` → visibility table inerte).
- **Soft upstream** : Audio System Rule 17 r2.2 r1.1 cascade NB-CRD-6 Option A (clac aigu SECRET +5 semitones bus SFX) — cohérence cross-system observable au playtest.
- **Cross-reference unblock** : `production/epics/credit-economy-system/story-008-visual-feel-hud-frame-perfect.md` AC-CRD-46 — cette story-006 ferme credit-008 par subsume OU shared evidence.
- **Unlocks** : aucune story HUD (gate ADVISORY de fin de cycle epic — close-out HUD epic).
