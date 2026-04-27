# Accessibility Requirements — CHROME://ASCENT

> **Status** : Committed
> **Author** : ux-designer + producer (auto — solo mode)
> **Last Updated** : 2026-04-21
> **Accessibility Tier Target** : **Standard**
> **Platform(s)** : PC (Steam, itch.io)
> **External Standards Targeted** :
> - WCAG 2.1 Level AA (contrast, text sizing, photosensitivity SC 2.3.1)
> - AbleGamers CVAA Guidelines (partial — input remap, subtitles, motion reduction)
> - Xbox Accessibility Guidelines (XAG) — N/A (pas de release Xbox envisagée pour v1.0)
> - PlayStation Guidelines — N/A
> - Apple/Google Guidelines — N/A (pas de release mobile)
> **Accessibility Consultant** : None engaged (studio indé, post-launch audit envisagé si succès commercial)
> **Linked Documents** : `design/gdd/systems-index.md`, `docs/architecture/architecture.md`, `design/gdd/player-movement-system.md` (TR-mov-008), `design/gdd/input-system.md`, `design/gdd/camera-system.md`

---

## 1. Tier Commitment — Standard

**Pourquoi Standard (et pas Basic ou Comprehensive)** :

CHROME://ASCENT est un FPS action-platformer fast-twitch solo avec katana one-shot, parkour (dash + wall-run + air-jump) et Pillar 1 « FLOW AVANT TOUT » (latence ≤ 1 frame perçue). La structure cible crée deux catégories de barrières majeures :

1. **Motrices** — inputs rapides simultanés (dash + saut + attaque en moins de 200 ms), hold inputs (sprint — on verra si retenu MVP), précision souris pour katana court. Les joueurs avec tremor / RSI / hémiplégie sont les plus exposés. **Motif #1 de tier Standard** : remapping complet + toggle-hold + input timing windows adjust sont l'investissement minimal non-négociable pour ce genre.
2. **Visuelles / photosensibilité** — VFX dash flash, respawn overlay rouge/blanc 150 ms, wall-run tilt 20°. Risque de déclenchement crises photosensibles et motion sickness. **Motif #2 de tier Standard** : reduce_flash + reduce_motion toggles (TR-mov-008) exigés WCAG 2.3.1.

Comprehensive / Exemplary exige screen reader menus (Godot 4.6 AccessKit support mais non-trivial), mono audio, cognitive assist modes, HUD reposition, audit externe. Hors-scope v1.0 studio indé sans accessibility specialist dédié.

Basic exclurait 8-12 % de l'audience cible (AbleGamers data) — les joueurs colorblind + ceux qui remap clavier. Inacceptable pour un projet qui vise le public parkour / FPS skill-based.

**Features elevées au-dessus du tier Standard (dans scope)** :
- **Aim assist OFF par défaut + pas d'option au MVP** — contrainte design (Pillar 1, skill ceiling parkour). Tension explicite : sacrifie l'accessibilité motrice au bénéfice de l'identité. Review en Vertical Slice si playtest révèle barrière rédhibitoire.
- **Timer extension QTE / timed inputs : N/A** — le jeu n'a pas de QTE, pas de timed prompts dialogue. Pas de fenêtre applicable.
- **`reduce_motion` bypass tilt wall-run** — spécifique à ce game (TR-mov-008). Élevé de Comprehensive à Standard car wall-run est un système MVP utilisé en permanence.

**Features explicitement out-of-scope** :
- Screen reader menus (AccessKit Godot 4.6 integration) — post-launch patch si commercialement viable.
- Full subtitle customization (font / bg / position) — subtitles minimales seulement (SFX critiques + narration, s'il y en a).
- HUD repositioning.
- Mono audio option.
- Tactile / haptic alternatives — PC only, pas de contrôleur prioritaire (gamepad est stretch Tier 2).

---

## 2. Visual Accessibility

| Feature | In-scope | Status | Notes |
|---------|----------|--------|-------|
| Minimum text size — menu UI | ✅ | Not Started | 24 px min à 1080p. Scaling proportionnel 4K. |
| Minimum text size — HUD | ✅ | Not Started | 20 px min pour credits counter / dash cooldown / death overlay. |
| Text contrast — UI on backgrounds | ✅ | Not Started | ≥ 4.5:1 body, ≥ 3:1 large. Testé Coblis. |
| Colorblind mode — Protanopia / Deuteranopia / Tritanopia | ✅ | Not Started | 3 modes. Audit : health bar (N/A — one-shot), credit counter (blue/yellow), secret found (gold glow), enemy indicator. |
| Color-as-only-indicator audit | ✅ | Not Started | Voir §2.1. |
| UI scaling 75-150 % | ✅ | Not Started | Menu + HUD indépendants. |
| Brightness / gamma controls | ✅ | Not Started | Range -50 % / +50 %. Calibration reference image. |
| **Screen flash / strobe warning (photosensitive)** | ✅ | Not Started | Pre-launch warning screen + Harding FPA audit sur respawn flash + dash trails. Voir TR-mov-008 `reduce_flash`. |
| **`reduce_flash` toggle** (TR-mov-008) | ✅ | Not Started | **MVP-required**. Réduit amplitude flash respawn 150 ms + dash trail brightness 50 %. |
| **`reduce_motion` toggle** (TR-mov-008) | ✅ | Not Started | **MVP-required**. Bypass wall-run tilt (camera_effects.rotation.z = 0), réduit camera shake × 0.3, désactive FOV dash kick. Propagation cross-system documentée §6. |
| High contrast mode | ❌ | Out of scope | Comprehensive tier. Post-launch. |
| Subtitles style customization | ❌ | Out of scope | 2 presets seulement (voir §5). |

### 2.1 Color-as-Only-Indicator Audit

| Location | Color Signal | Communicates | Non-Color Backup | Status |
|----------|--------------|--------------|------------------|--------|
| Credit counter | Blue | Credits balance | Numeric value always displayed | ✅ Already OK |
| Dash cooldown UI | Cyan full / gray empty | Dash ready / on cooldown | Cooldown duration ms affichée + icon fill (circular progress) | Not Started |
| Secret found | Gold glow | Secret unlock | Chime SFX + text "SECRET +1" overlay | Not Started |
| Respawn overlay | Red flash | Player died | Big text "DIED" + shake | ✅ Already OK (Camera GDD) |
| Enemy health state (boss only) | Red bar | Boss HP | Numeric HP + phase indicator text | Not Started (post-MVP boss) |
| Hazard (spikes, fall-kill) | Red tint on hazard surface | Dangerous | Distinct mesh shape + spike silhouette + warning SFX | Not Started |

---

## 3. Motor Accessibility

| Feature | In-scope | Status | Notes |
|---------|----------|--------|-------|
| **Full input remapping** — keyboard/mouse | ✅ **MVP** | Not Started | Tous les inputs rebindable. Conflict warning. Persist to `input_settings.tres` (post-MVP save/load ADR-0014). |
| Input remapping — gamepad | ⚠️ Partial | Not Started | Gamepad = Tier 2 support. Infra ready, remap UI en Tier 2+. |
| Input method switching (KB/M ↔ gamepad) | ⚠️ Partial | Not Started | Tier 2. Dynamic prompts icons si gamepad support activé. |
| One-hand mode | ❌ | Out of scope | Incompatible avec design : dash + saut + attaque + mouse aim simultanés. Documenté comme Known Limitation §9. |
| Hold-to-press alternatives — toggle sprint | ⚠️ Conditional | Not Started | Applicable seulement si sprint-hold retenu Movement MVP (décision non tranchée). Sinon N/A. |
| Rapid input alternatives | ❌ N/A | — | Le katana est one-shot, pas de button mashing. |
| **Input timing adjustments** (coyote time scaling) | ✅ | Not Started | Coyote time (MVP-required) 100 ms default, scalable 100-300 ms dans accessibility settings. |
| Aim assist | ❌ | Out of scope | **Tension design** : Pillar 1 skill ceiling. Review Vertical Slice si playtest révèle blocker. |
| Auto-sprint / auto-run | ❌ | Out of scope | Incompatible identité parkour. |
| Platforming assists — generous ledge detection | ✅ | Not Started | Coyote time (above) + wall-run raycast range légèrement élargi. Tuning knob dans movement_tuning.tres. |
| HUD repositioning | ❌ | Out of scope | Comprehensive tier. |

---

## 4. Cognitive Accessibility

| Feature | In-scope | Status | Notes |
|---------|----------|--------|-------|
| **Pause anywhere** | ✅ **MVP** | Not Started | Pause gameplay, pas pendant cinématiques (N/A — pas de cinématiques au MVP). GameStateManager.request_pause() via `ui_cancel_pressed` traversant même pendant respawn (ADR-0004 D-4 refcount releases pause). |
| Difficulty options | ❌ N/A | — | Pas de difficulty slider MVP. One-shot = fixe. Post-MVP : "assist mode" fenêtre attaque + i-frames étendues post-respawn envisageable. |
| Tutorial persistence | ⚠️ VS tier | Not Started | Tutorial est Vertical Slice system (VS tier systems-index). Help section menu en scope VS. |
| Quest / objective clarity | ❌ N/A | — | Pas de quests. Objectif = compléter étage → boss. |
| **Visual indicators for audio-only information** | ✅ | Not Started | Audio cues critiques : enemy attack windup (SFX + visual telegraph déjà requis), hazard trigger (SFX + animation), low health (N/A one-shot). Audit complet §5.1. |
| Reading time UI / auto-dismiss | ✅ | Not Started | Credit popup "+N credits" : 2 s default, extensible à 5 s in settings. Secret found text : 3 s default. |
| Cognitive load documentation | ⚠️ Advisory | Not Started | Movement tracks : state (1) + dash cooldown (1) + wall-run timer (1) + air_jumps_used (1) + capability flags (lus pas tracked) = **4 simultaneous**. Combat tier review. |
| Navigation assists — checkpoint map | ⚠️ Partial | Not Started | Checkpoint system MVP inclut visualisation dernier checkpoint atteint. Fast travel = post-MVP. |

---

## 5. Auditory Accessibility

| Feature | In-scope | Status | Notes |
|---------|----------|--------|-------|
| Subtitles for spoken dialogue | ❌ N/A | — | **Pas de dialogue** MVP (anti-pillar narration). Si narration audio ajoutée VS : subtitles obligatoires. |
| **Closed captions gameplay-critical SFX** | ✅ | Not Started | Audit §5.1. Target : enemy attack windup + hazard trigger + secret found + respawn flash. Format `[SOUND DESCRIPTION]` distinct typographie. |
| Mono audio option | ❌ | Out of scope | Comprehensive tier. Post-launch. |
| **Independent volume controls** | ✅ **MVP** | Not Started | 4 sliders : Master / SFX / Music / UI. Persist `audio_settings.tres` (post-MVP ADR-0014). Range 0-100 %, default Master 80 % / SFX 90 % / Music 70 % / UI 80 %. |
| Visual representations for directional audio | ⚠️ Partial | Not Started | Enemy off-screen : screen-edge arrow indicator (Standard tier pushed into scope pour FPS one-shot). Deferrable Sprint Combat. |
| Hearing aid compatibility — low-frequency alternatives | ✅ | Not Started | Audit SFX : tous les gameplay-critical cues ont composante < 4 kHz OU visual backup. |

### 5.1 Gameplay-Critical SFX Audit

| Sound Effect | Communicates | Visual Backup | Caption Required | Status |
|--------------|--------------|---------------|------------------|--------|
| Enemy attack windup | Incoming damage imminent | Enemy animation telegraph (design rule — must be visible 3-camera-angles) | No — visual suffisant | Not Started |
| Hazard trigger (spikes out) | Hazard armed | Spike extrude animation | Yes if off-screen : `[SPIKES TRIGGER]` directional indicator | Not Started |
| Dash activate | Dash started (self-feedback) | FOV kick + trail VFX + screen blur 50 ms | No — visual suffisant | Not Started |
| Wall-run engage | Wall-run started | Camera tilt + HUD indicator (briefly) | No — visual suffisant | Not Started |
| Respawn flash | Player died + respawned | Red overlay 100 ms + flash 50 ms (Camera GDD) | No — visual suffisant | Not Started |
| Secret found chime | Secret unlocked | Gold glow + "SECRET +1" overlay | No — visual suffisant | Not Started |
| Boss phase transition | Boss HP threshold | Boss animation + screen shake | Yes : `[BOSS ENRAGES]` | Not Started (post-MVP boss) |

---

## 6. `reduce_motion` Cross-System Propagation (TR-mov-008)

Interface unique figée dans **ADR-0015 Accessibility Interface Layer** (à créer post-MVP). Spec inline MVP :

```gdscript
# AccessibilityManager autoload (à créer — couverture gap G-4)
extends Node

var reduce_motion: bool = false
var reduce_flash: bool = false

signal accessibility_changed()

# Consumers lisent via getter OR écoutent signal accessibility_changed
# Write-access uniquement depuis MenuSystem (settings toggle)
```

**Propagation** :

| System | Consumes | Behavior if `reduce_motion=true` |
|--------|----------|----------------------------------|
| CameraSystem | `AccessibilityManager.reduce_motion` | Bypass tilt wall-run (camera_effects.rotation.z=0), shake × 0.3 max amplitude, FOV dash kick désactivé |
| MovementController | `AccessibilityManager.reduce_motion` | Aucun impact mouvement (bypass serait trompeur) |
| VFXFeedback | `AccessibilityManager.reduce_motion` | Dash trail brightness × 0.5, particle count × 0.5 |
| HUD | `AccessibilityManager.reduce_motion` | Transitions menus cross-fade only (pas de slide/scale) |

| System | Consumes | Behavior if `reduce_flash=true` |
|--------|----------|----------------------------------|
| CameraSystem | `AccessibilityManager.reduce_flash` | Respawn flash amplitude × 0.2 (50 % → 10 %), durée inchangée |
| VFXFeedback | `AccessibilityManager.reduce_flash` | Strobe effects supprimés (aucun effet > 3 flashes/sec Harding FPA) |

**Default values** : `reduce_motion = false`, `reduce_flash = false`. Exposé dans settings menu Accessibility section.

---

## 7. Platform Accessibility API Integration

| Platform | API | In-scope MVP | Notes |
|----------|-----|--------------|-------|
| Steam (PC) | Steam Input + SDL | ⚠️ Partial | Steam Input pour gamepad remap (Tier 2+). Keyboard/mouse remap in-game. |
| PC Screen Reader (JAWS/NVDA/Narrator) | Godot 4.6 AccessKit | ❌ | Out of scope v1.0. Evaluation post-launch. |
| itch.io | N/A | ❌ | Pas d'API accessibility spécifique. |

---

## 8. Test Plan

| Feature | Test Method | Pass Criteria | Responsible | Sprint |
|---------|-------------|---------------|-------------|--------|
| Text contrast ratios | Automated Coblis sur tous UI screens | ≥ 4.5:1 body, ≥ 3:1 large | ux-designer | Sprint HUD/Menu |
| Colorblind modes (3) | Manual Coblis simulator | No essential info lost | ux-designer | Sprint HUD/Menu |
| Input remapping | Manual — rebind tous inputs, complete Sprint 1 level | Tous actions accessibles + pas de conflict | qa-tester | Sprint Menu |
| `reduce_motion` | Manual — toggle ON, 10 min gameplay | Pas de tilt, shake reduced, pas de motion sickness | ux-designer + playtester motion-sensitive | Sprint Camera polish |
| `reduce_flash` | Manual — toggle ON + Harding FPA tool on respawn sequence | Aucun flash > 3/sec threshold | ux-designer | Sprint VFX |
| Photosensitive pre-launch warning | Manual — fresh install | Warning screen affiché first launch | qa-tester | Polish |
| Volume independent sliders | Manual — chaque slider 0-100 % | Aucune interaction entre buses | sound-designer | Sprint Audio |

---

## 9. Known Intentional Limitations

| Feature | Tier Required | Why Not Included | Risk | Mitigation |
|---------|---------------|------------------|------|------------|
| Aim assist | Standard | Pillar 1 FLOW + skill ceiling parkour. Design constraint. | Exclut joueurs motor impairment visant à la souris | Review Vertical Slice. Si 2+ playtesters testent l'absence comme blocker, réouverture. |
| Screen reader menus | Comprehensive | Godot 4.6 AccessKit menu-only mais integration non-triviale + studio sans ax-specialist | Exclut joueurs blind/low-vision totalement | Post-launch patch si succès commercial. |
| One-hand mode | Standard | Mécaniques requièrent souris + 3-4 touches simultanées. Redesign partiel requis. | Exclut joueurs hémiplégie | Documenté. Alternative : `Use keyboard-only mode via remapping` partial workaround (pas testé). |
| Mono audio | Comprehensive | Pas de budget SFX re-mix | Exclut joueurs single-sided deafness | Post-launch patch. |
| HUD repositioning | Comprehensive | Architecture HUD figée simple (coins) | Impact mineur — HUD minimal | Accept. |
| Full subtitle customization | Comprehensive | Narration absente MVP | N/A tant que pas de dialogue | Si narration ajoutée VS : re-scope. |

---

## 10. Audit History

| Date | Auditor | Type | Scope | Findings | Status |
|------|---------|------|-------|----------|--------|
| 2026-04-21 | ux-designer (solo mode self-audit) | Internal commitment | Tier selection + scope definition | Standard tier committed. 2 MVP toggles confirmed : reduce_flash + reduce_motion (TR-mov-008). 5 known limitations documented. | Baseline established |

---

## 11. Open Questions

| Question | Owner | Deadline |
|----------|-------|----------|
| Sprint-hold retenu MVP Movement ? (impacte scope toggle sprint) | game-designer | Sprint 1 Movement |
| Coyote time range 100-300 ms acceptable game-feel au bound sup ? | game-designer + playtest | VS playtest |
| Godot 4.6 AccessKit menus — effort réel ? (si < 2 jours, push into MVP) | godot-specialist + ux-designer | Avant Sprint Menu |
| Aim assist review threshold Vertical Slice : combien de playtesters / quel feedback ? | producer | Before VS playtest |

---

## 12. Cross-References

- `design/gdd/player-movement-system.md` — TR-mov-008 (reduce_flash/reduce_motion GDD spec source)
- `design/gdd/camera-system.md` — shake + tilt + FOV consumers de reduce_motion
- `design/gdd/input-system.md` — remap + input_settings.tres persistence (post-MVP ADR-0014)
- `docs/architecture/architecture.md` §2 Engine Knowledge Gap — AccessKit 4.5 noted post-MVP
- `docs/architecture/tr-registry.yaml` — TR-mov-008 Gap G-4
- Planned ADR-0015 Accessibility Interface Layer (post-MVP polish ou inline Sprint Accessibility)
