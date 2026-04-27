# UX Spec — Main Menu

> **Status** : Draft (baseline for gate)
> **Owner** : ux-designer
> **Last Updated** : 2026-04-21
> **Related** : `design/ux/interaction-patterns.md`, `design/accessibility-requirements.md`, `design/art/art-bible.md` (Chrome Zen visual identity), `design/gdd/game-concept.md`
> **Accessibility Tier** : Standard

---

## 1. Purpose & Player Experience

Le main menu est le **premier moment de contact** avec CHROME://ASCENT. En cohérence avec Pillar 1 FLOW AVANT TOUT, il doit :
- Permettre de lancer une run en **≤ 2 clics / 2 keys** depuis l'écran d'accueil (Press Any Key → New Run).
- Communiquer l'identité visuelle Chrome Zen (primitives, flat shaders, palette minimale) dès la première frame.
- Ne jamais bloquer l'input ni introduire de latence perceptible.

Fantasy visée : « tu arrives, le jeu ne te ralentit pas, tu es DÉJÀ en train de jouer ».

---

## 2. Information Architecture

```
[Press Any Key / Splash] ──→ Main Menu
                              │
                              ├─ [New Run]        → scene transition → Sprint 1 gameplay
                              ├─ [Continue]       → (disabled si aucun save slot — post-MVP)
                              ├─ [Settings]       → Settings screen (separate UX spec, planned)
                              ├─ [Credits]        → Credits screen (post-MVP)
                              └─ [Quit]           → confirm modal → OS exit
```

---

## 3. Screen Flow

### 3.1 Entry

1. App launch → Godot splash (incompressible) → black frame 100 ms.
2. Game logo "CHROME://ASCENT" fade-in 300 ms.
3. "Press Any Key" prompt fade-in 200 ms.
4. Any key/button/click → Main Menu fade-in 200 ms.

**Accessibility** : `reduce_motion` → durée fade-in / fade-out → 50 ms (cut-like).

### 3.2 Main Menu

- 4 menu items en colonne verticale, centrés. Spacing 40 px.
- Focus initial : `[New Run]`.
- Navigation : `ui_up`/`ui_down` (P-INP-003). Wraparound top↔bottom.
- Select : `ui_accept` OR mouse click.
- Cancel : `ui_cancel` → `[Quit]` confirm modal direct.

### 3.3 Exit confirmation

- Modal dialog (P-ERR-001), focus default `[Cancel]`.
- Text : « Quitter CHROME://ASCENT ? La run en cours ne sera pas sauvegardée. »
- `[Confirm]` → `OS.quit()` via GameStateManager.

---

## 4. Visual Layout

```
┌─────────────────────────────────────────┐
│                                         │
│                                         │
│         CHROME://ASCENT                 │  ← logo, 120 px height
│                                         │
│                                         │
│            [New Run]       ← focused    │  ← 40 px text
│            [Continue]      (disabled)   │
│            [Settings]                   │
│            [Credits]       (post-MVP)   │
│            [Quit]                       │
│                                         │
│                                         │
│                          v0.1.0  GPL-3  │  ← footer, 12 px bottom-right
└─────────────────────────────────────────┘
```

**Grid** : 1920×1080 reference. Centered vertically. Logo Y=15 %, menu Y=55 %.

**Typography** :
- Logo : sans-serif geometric, 120 px, letter-spacing 8 px, color `#E6E6E6` (Chrome Zen neutral).
- Menu items : monospace, 40 px, color `#CCCCCC` normal / `#FFFFFF` focused / `#666666` disabled. Contrast ratio focused-on-bg ≥ 7:1 (accessibility WCAG AAA for critical navigation).

**Background** : solid `#0A0A0A` near-black. No busy background art at MVP (Chrome Zen minimalism, Pillar 4 performance).

**Focus indicator** : `>` prefix (5 px from text) + subtle underline `#FFFFFF` full width of text.

**UI scaling** : applies via P-MENU-001 pattern — range 75-150 % (accessibility). Default 100 %. Text-only scaling (logo stays fixed).

---

## 5. Interaction Patterns Referenced

| Pattern | Usage |
|---------|-------|
| P-INP-003 (menu navigation focus) | Focus handling, arrow keys, gamepad |
| P-INP-004 (accessibility gating) | N/A main menu (no gating needed) |
| P-TRANS-001 (scene transition) | `[New Run]` → gameplay transition |
| P-ERR-001 (confirm modal) | Exit confirmation |

---

## 6. Input Bindings

| Action | Default Binding | Notes |
|--------|-----------------|-------|
| `ui_up` / `ui_down` | W/S, Arrow Up/Down | Menu navigation |
| `ui_accept` | Enter, Space | Select item |
| `ui_cancel` | Escape | Back / quit prompt |
| Mouse click | Left button | Direct select |

**Remap** : inaccessible from main menu (only from Settings → Controls). MVP : Settings menu provides rebinding (post-MVP ADR-0014 for persistence).

---

## 7. Accessibility Annotations

| Concern | Addressed | Implementation |
|---------|-----------|----------------|
| Text contrast | ✅ | All text ≥ 7:1 ratio on `#0A0A0A` bg |
| Text size | ✅ | Menu items 40 px at 1080p (exceeds 24 px minimum) |
| Color-as-only-indicator | ✅ | Focus uses `>` prefix + underline, not just color |
| Full keyboard navigation | ✅ | No mouse required — arrow keys + Enter + Escape |
| `reduce_motion` | ✅ | Fade durations collapse to 50 ms |
| `reduce_flash` | N/A | No flash effects in main menu |
| Screen reader | ❌ | Out of scope (Comprehensive tier) — documented Known Limitation |
| UI scaling 75-150 % | ✅ | Menu items rescale, logo fixed, layout tested both ends |

---

## 8. Performance Budget

- Render cost : ≤ 1 ms/frame (solid bg + 5 text labels + optional shader border). Within Pillar 4 allocation.
- Load time from splash to playable main menu : ≤ 2 s on entry-level laptop.
- Transition to gameplay `[New Run]` : fade-out 200 ms + async scene load + fade-in 200 ms. Total ≤ 1.5 s including load.

---

## 9. Edge Cases

| Case | Behavior |
|------|----------|
| App minimized during splash | Godot handles. Resume from splash on focus return. |
| Focus lost during main menu | `InputManager.application_focus_lost` fires but no gameplay to pause. Menu remains interactive on focus return. |
| Display mode change while in menu | Re-layout triggered via `get_viewport().size_changed`. No state loss. |
| Controller unplug during menu | Input method switches to keyboard. Focus preserved. (P-INP-003 pattern — dynamic prompts Tier 2+.) |
| `[Continue]` clicked while disabled | No-op. Sound feedback = none (silent disabled state). Visual feedback : disabled color already distinct. |

---

## 10. Acceptance Criteria

- [ ] AC-MM-1 : fresh launch → splash → main menu reachable within 3 s on target hardware.
- [ ] AC-MM-2 : `[New Run]` from focus → gameplay start ≤ 2 s total.
- [ ] AC-MM-3 : keyboard-only navigation complete (no mouse needed) for all menu paths.
- [ ] AC-MM-4 : all text ≥ 7:1 contrast ratio verified via Coblis.
- [ ] AC-MM-5 : `reduce_motion=true` collapses all fades to 50 ms.
- [ ] AC-MM-6 : UI scaling 75 % / 150 % does not break layout (no overlap, no clipping).
- [ ] AC-MM-7 : Exit confirmation modal focus defaults to `[Cancel]`, `ui_cancel` cancels modal.
- [ ] AC-MM-8 : transitions do not exceed frame budget (16.6 ms at 60 fps) during fade animations.

---

## 11. Open Questions

| Question | Owner | Deadline |
|----------|-------|----------|
| Logo animated intro (subtle glitch / scanline effect) or static? | art-director + ux-designer | Sprint Menu |
| Audio on main menu — silence, ambient loop, or menu theme track? | audio-director | Sprint Audio |
| Display remap prompt on first launch (tutorial overlay) or assume keyboard defaults? | ux-designer | Sprint Menu playtest |

---

## 12. References

- `design/art/art-bible.md` §1-4 Visual Identity Foundation
- `design/accessibility-requirements.md` §2 Visual + §4 Cognitive
- `design/ux/interaction-patterns.md` P-INP-003, P-TRANS-001, P-ERR-001, P-MENU-001/002/003
- `docs/architecture/architecture.md` §3 Layer Map (Menu System in Presentation Layer)
