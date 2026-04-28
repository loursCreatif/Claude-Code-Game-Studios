# Story 013: Bidirectional Integration Playtest + UX Specs Alignment

> **Epic**: Menu System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Visual/Feel
> **Manifest Version**: 2026-04-23
> **Estimate**: S (2-3 h, manual playtest + UX walkthrough + 3 sign-offs)
> **Performance**: validation manuelle ressenti — Pillar 1 FLOW snap < 100 ms ressenti + Pillar 3 anti-pause RESPAWNING. Pas de mesure automatique (couverte story 011).

## Context

**GDD**: `design/gdd/menu-system.md`
**Requirement**: Bidirectional check (4/4) — alignement UX specs (`design/ux/main-menu.md` r1 11 AC-UX-MM + `design/ux/pause-menu.md` r1 18 AC-UX-PM)

**UX Specs Sources**:
- `design/ux/main-menu.md` r1 (294 lignes, livré 2026-04-27 commit `d6279a7`) — 11 AC-UX-MM
- `design/ux/pause-menu.md` r1 (357 lignes, livré 2026-04-27 commit `d6279a7`) — 18 AC-UX-PM
- `design/ux/quit-flow.md` r1 — Tier 3 Steam-only NOT-blocking MVP (cf. EPIC §UX flag K.10)

**ADR Governing Implementation**: aucun — playtest manuel + sign-off cross-discipline (gameplay-programmer + ux-designer + game-designer + creative-director).

**Engine**: Godot 4.6 | **Risk**: LOW (validation finale — code livré stories précédentes)
**Engine Notes**: Build distribuable (export Linux/Windows/macOS) requis pour playtest cross-OS optionnel.

**Control Manifest Rules**:
- Required : Cohérence Pillar 1 FLOW snap < 100 ms ressenti.
- Manual gate : ux-designer + creative-director sign-off avant `/story-done`.

---

## Acceptance Criteria

- [ ] **AC-MNU-53** [Manual — ADVISORY] : inspecteur Godot + résolution 1920×1080, lecture des tailles font Theme — TitleLabel=28, Button=15, SubtitleLabel=13, VersionLabel=11. Evidence : screenshot inspecteur + sign-off ux-designer.
- [ ] **AC-MNU-54** [Manual — ADVISORY] : ratios contraste WCAG mesurés à l'écran rendu — `MENU_TEXT_BASE` sur `MENU_BG_BLACK` ≥ 15.2:1 + `MENU_ACCENT_CYAN` ≥ 8.9:1. Evidence : valeurs documentées + screenshot.
- [ ] **Boucle complète manuelle** : Main Menu → Start Run → étage_01 → ESC → Pause → Resume → ESC → Quitter Menu Principal → Main Menu → Quitter le jeu. Aucun crash, aucun freeze > 100 ms ressenti, focus initial chaque étape correct.
- [ ] **UX specs alignment** : implémentation matche les 11 AC-UX-MM (`design/ux/main-menu.md`) + 18 AC-UX-PM (`design/ux/pause-menu.md`). Walk-through point-par-point documenté.
- [ ] **Sign-off creative-director** : Pillar 1 FLOW respecté (snap pause/resume < 100 ms ressenti, zéro friction confirm/SFX/animation). Pillar 3 SECONDE CHANCE respecté (Pause inerte pendant RESPAWNING vérifié manuellement via die intentionnel).
- [ ] **Bidirectional reciprocity confirmed** : 4/4 PASS (GSM r1 / InputManager r6 / HUD r1 / Shop r2.1) déjà documenté EPIC ; cette story confirme post-impl + flag amendement éditorial GSM r1 §Dependencies Downstream "MenuSystem inferred Not Started → APPROVED r2 / Implemented Sprint A" (cosmetic non-blocker).

---

## Implementation Notes

*Validation finale — pas de code menu écrit, uniquement playtest + evidence collection :*

1. **Playtest scenario complet** : sur build dev ou export, dérouler la boucle :
   - Boot → vérifier Main Menu visible immédiat (zéro splash MVP cf. OQ-MNU-4 désactivé), `StartButton` focused, mouse libre.
   - Click "Start Run" → transition LOADING → PLAYING ; gameplay 60 fps.
   - Press ESC → snap Pause Overlay visible < 100 ms ressenti, `ResumeButton` focused, mouse libre, gameplay frozen.
   - Press ESC → snap Resume < 100 ms, mouse capturée, gameplay resume.
   - Press ESC → Pause à nouveau ; click "Quitter vers Menu Principal" → transition snap → Main Menu visible ; vérifier mouse libre et focus initial.
   - Click "Quitter le jeu" → window close clean, save-on-quit délégué SaveLoad invisible côté Menu.
2. **UX specs walkthrough** :
   - Lire `design/ux/main-menu.md` r1 → cocher chacun des 11 AC-UX-MM contre l'implémentation.
   - Lire `design/ux/pause-menu.md` r1 → cocher chacun des 18 AC-UX-PM.
   - Documenter écarts (s'il y en a) dans `production/qa/evidence/menu-ux-walkthrough-[date].md`.
3. **Pillar 3 RESPAWNING test** : die intentionnel (tomber dans WorldBounds — Level System) → state RESPAWNING → press ESC pendant respawn animation. Vérifier : Pause Overlay ne s'ouvre PAS (matrice ADR-0007 D-2 + AC-MNU-14). Critique pour Pillar 3.
4. **Cross-OS optional** : si builds export Linux/Windows/macOS disponibles, dérouler boucle sur chaque plateforme (EC-MNU-37/38/42 — minimize, sleep/wake, dual-monitor focus loss).
5. **Bidirectional amendement éditorial GSM r1** :
   - Ouvrir `design/gdd/game-state-manager.md` §Dependencies Downstream.
   - Si l'entrée mentionne "MenuSystem inferred Not Started", la promote en "MenuSystem APPROVED r2 / Implemented Sprint A".
   - Commit cosmetic (non-blocker) dans la même PR ou suivante.
6. **Evidence file structure** : `production/qa/evidence/menu-bidirectional-playtest-[date].md` :
   - Section 1 : boucle complète (texte + screenshots à chaque étape critique)
   - Section 2 : UX walkthrough (11 + 18 ACs cochés)
   - Section 3 : Pillar 1 + Pillar 3 sign-off
   - Section 4 : bidirectional 4/4 confirmé
   - Sign-off : ux-designer + game-designer + creative-director (initiales + date)

---

## Out of Scope

- Stories 001-012 : implémentation menu (cette story consomme).
- Story 011 : perf bench headless (cette story est playtest manuel ressenti — complémentaire).
- Settings Menu Tier 2+ (OQ-MNU-3 latent).
- Localization Tier 2+ (OQ-MNU-8 FR-only MVP).

---

## QA Test Cases

*Mode Visual/Feel — manual checks + evidence sign-off.*

**Manual check : boucle Main Menu → étage → Pause → MainMenu → Quit**
- Setup : build dev export OU `godot --path . scenes/menus/main_menu.tscn`.
- Verify : (1) Main Menu visible immédiat, StartButton focused, mouse libre.
- Pass condition : déroulement complet sans crash, sans freeze ressenti > 100 ms, focus correct chaque étape.

**Manual check : Pillar 3 anti-pause RESPAWNING**
- Setup : étage chargé, mourir intentionnellement (tomber dans WorldBoundsVolume).
- Verify : pendant RESPAWNING animation, presser ESC.
- Pass condition : Pause Overlay ne s'ouvre PAS (AC-MNU-14 ressenti).

**Manual check : UX specs Main Menu (11 AC-UX-MM)**
- Setup : `design/ux/main-menu.md` r1 ouvert + Main Menu rendu 1920×1080.
- Verify : chaque AC-UX-MM coché point-par-point.
- Pass condition : 11/11 cochés OU écarts documentés + accepté ux-designer.

**Manual check : UX specs Pause Menu (18 AC-UX-PM)**
- Setup : `design/ux/pause-menu.md` r1 ouvert + Pause Overlay visible.
- Verify : chaque AC-UX-PM coché.
- Pass condition : 18/18 cochés OU écarts documentés + accepté ux-designer.

**Manual check : Pillar 1 FLOW snap ressenti**
- Setup : presser ESC en gameplay, observer transition.
- Verify : aucune sensation de friction ; pause apparaît "instantanément".
- Pass condition : creative-director sign-off "Pillar 1 satisfait".

**Manual check : bidirectional reciprocity**
- Setup : ouvrir GSM r1 + InputManager r6 + HUD r1 + Shop r2.1 GDDs.
- Verify : chacune cite Menu sibling (4/4 PASS post-impl).
- Pass condition : amendement éditorial GSM r1 promote "Implemented Sprint A" si applicable (cosmetic).

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**:
- `production/qa/evidence/menu-bidirectional-playtest-[date].md` (boucle + UX walkthrough + sign-offs)
- Screenshots Main Menu + Pause Overlay rendus (1920×1080 + 1280×720 + ultrawide si disponible)
- Sign-offs : ux-designer + game-designer + creative-director (initiales + date dans evidence file)
- Optional : amendement éditorial commit `design/gdd/game-state-manager.md` §Dependencies Downstream

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on : Stories 001-012 (totalité du Menu System livré) ; UX specs `design/ux/main-menu.md` r1 + `design/ux/pause-menu.md` r1 livrées (déjà commit `d6279a7`).
- Unlocks : `/story-done` epic Menu System ; promotion EPIC.md status Ready → Implemented Sprint A ; flag follow-up cosmetic GSM r1 §Dependencies Downstream amendement éditorial.
