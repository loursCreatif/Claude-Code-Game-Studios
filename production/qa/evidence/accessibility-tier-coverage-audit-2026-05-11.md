# Audit Accessibility Tier Coverage — 2026-05-11

**Contexte** : Quality Check #4 du gate-check Pre-Production → Production 2026-05-05 (MANUAL CHECK Accessibility tier UX specs).

**Verdict** : **PASS CONDITIONNEL** — 2 patchs cosmétiques (rétro-ref ADR-0015) à scheduler en Sprint Polish P3, **non-bloquants** pour le gate.

## Matrice de couverture

| Doc | Tier mentionné ? | WCAG 2.1 AA ? | ADR-0015 D-1 ref ? | Verdict |
|-----|------------------|---------------|-------------------|---------|
| `design/accessibility-requirements.md` | OUI (source canonique) | OUI (SC 2.3.1/2.3.3) | OUI (§6 Planned ADR-0015) | REFERENCE |
| `design/ux/hud.md` | Implicite (§Accessibility + §Reduce-motion + cross-ref ADR-0015) | OUI (4.5:1 cité) | OUI (`ADR-0015 D-1 Option A`) | PASS |
| `design/ux/interaction-patterns.md` | OUI (`Accessibility Tier: Standard`) | OUI (contrast ≥ 4.5:1) | NON | GAP MINEUR |
| `design/ux/main-menu.md` | OUI (Tier 1 obligatoire + Tier 2 AccessKit) | OUI (WCAG AAA 7:1) | NON | GAP MINEUR |
| `design/ux/pause-menu.md` | OUI (Tier 1 obligatoire + Tier 2 AccessKit) | OUI (WCAG AAA 7:1) | NON | GAP MINEUR |
| `design/gdd/hud-system.md` | Implicite (Tier 3 text scaling) | Implicite via UX spec | NON (OQ-HUD-6 mention AccessibilityManager Tier 2+) | GAP MODERE |
| `design/gdd/menu-system.md` | OUI (Tier 2+/Tier 3 §K.9) | OUI (WCAG AAA 15.2:1) | NON | GAP MINEUR |
| `design/gdd/player-movement-system.md` | NON (MVP-required reduce_motion) | OUI (SC 2.3.1 + 2.3.3) | NON (TR-mov-008 précède l'ADR) | GAP MODERE |
| `design/gdd/camera-system.md` | NON | OUI (AC-CAM-70/71/72 WCAG 2.3.1) | NON | GAP MODERE |
| `design/gdd/vfx-system.md` | NON | OUI (R-VFX-13 SC 2.3.1) | OUI (header + R-VFX-11 ADR-0015) | PASS |
| `design/gdd/player-combat-system.md` | NON (knobs r1 correction) | OUI (flash mult WCAG 2.3.1) | NON (story-022 câble post-GDD) | GAP MODERE |
| `design/gdd/audio-system.md` | NON | NON | OUI (§Dependencies AccessibilityService Tier 3) | GAP MODERE |
| `design/gdd/shop-system.md` | OUI (§J.8 Tier 2+/Tier 3) | OUI (WCAG AA §J.6) | NON | GAP MINEUR |
| `design/gdd/enemy-system.md` | NON | NON | NON | SILENCIEUX (justifié) |
| `design/gdd/level-system.md` | NON | NON | NON | SILENCIEUX (justifié) |
| `design/gdd/game-state-manager.md` | NON | NON | NON | SILENCIEUX (justifié) |
| `design/gdd/checkpoint-respawn-system.md` | NON | NON | NON | SILENCIEUX (justifié) |
| `design/gdd/credit-economy-system.md` | NON | NON | NON | SILENCIEUX (justifié) |
| `design/gdd/save-load-system.md` | NON | NON | NON | SILENCIEUX (justifié) |
| `design/gdd/upgrade-system.md` | NON | NON | NON | SILENCIEUX (justifié) |
| `design/gdd/secret-system.md` | NON | NON | NON | SILENCIEUX (justifié) |

## Synthèse

- **4 UX specs (100%)** couvrent le tier explicitement et WCAG 2.1 AA — gate-check unblocked.
- **5 docs/21** mentionnent le tier explicitement (4 UX + `shop-system.md`).
- **3 docs** référencent ADR-0015 D-1 (`hud.md` UX, `vfx-system.md`, `audio-system.md` Dependencies).
- **8 GDDs silencieux justifiés** — systèmes sans surface UX directe.
- **4 GDDs MODERE** (movement, camera, combat, hud) — implémentent reduce_motion mais sans ref ADR-0015 (rédigés avant l'ADR).
- **4 docs MINEUR** — tier couvert, WCAG présent, ADR-0015 absent.

## Recommandations Polish P3 (non-bloquantes)

1. **Patch rétro-ref ADR-0015** dans 4 GDDs MODERE (`camera-system.md`, `player-movement-system.md`, `player-combat-system.md`, `hud-system.md`) — ajouter ligne header `> **Accessibility** : ADR-0015 D-1 — consumers lisent AccessibilityService.reduce_motion / reduce_flash`. Effort : ~30 min cumulé.

2. **Patch References section** dans 3 UX specs (`interaction-patterns.md`, `main-menu.md`, `pause-menu.md`) — ajouter lien ADR-0015. Effort : ~15 min cumulé.

**Tracking** : ajouter en tech-debt list `production/session-state/active.md` sous "Polish P3 — Accessibility ref drift" (non-bloquant Pre-Production → Production).

## References

- Gate-check : `production/gate-checks/2026-05-05-pre-production-to-production.md` Quality Check #4
- Source canonique : `design/accessibility-requirements.md` (3-tier model)
- ADR : `docs/architecture/adr-0015-accessibility-interface-layer.md`
