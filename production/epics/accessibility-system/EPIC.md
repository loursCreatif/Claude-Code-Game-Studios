# Epic: Accessibility System

> **Status**: Active (Polish P3)
> **Owner**: Foundation
> **Manifest Version**: 2026-04-23
> **Governing ADR**: ADR-0015 Accessibility Interface Layer (Accepted 2026-05-02)

## Overview

Single-source-of-truth pour les préférences d'accessibilité (`reduce_motion`,
`reduce_flash`, multipliers per-system). Persistance déléguée à ADR-0014
(`accessibility_settings.tres` typé Resource via helper `SettingsResource`).
Propagation cross-system via autoload `AccessibilityService` (pub-sub signal
`settings_changed`) + bridge `OS.is_reduce_motion_enabled()` (Godot 4.5+
AccessKit) en OR-merge avec toggle utilisateur.

## Governing ADRs

| ADR | Title | Status | Coverage |
|-----|-------|--------|----------|
| ADR-0015 | Accessibility Interface Layer | Accepted 2026-05-02 | TR-mov-008 + TR-cmb-016 |
| ADR-0014 | Save/Load Settings Infrastructure | Accepted 2026-05-02 | Helper `SettingsResource` consommé |

## TR Coverage

| TR-ID | Description | Covered by | Status |
|-------|-------------|------------|--------|
| TR-mov-008 | Movement accessibility toggles propagation | ADR-0015 | ✅ |
| TR-cmb-016 | Combat reduce_motion impact (slow-mo + flash) | ADR-0015 | ✅ |

## Stories

| ID | Title | Status | Layer | Type |
|----|-------|--------|-------|------|
| 001 | Foundation autoload `AccessibilityService` + Resource schema | ✅ Complete 2026-05-02 | Foundation | Logic |

**Totaux** : 0 Ready / 0 Blocked / 1 Complete.

**Tests** : 19/19 PASSED (`reports/report_228`).

## Dependencies

- **Depends on** : ADR-0014 (helper `SettingsResource` — déjà mergé PR #2).
- **Unlocks** : Combat story-022 (câblage `AccessibilityService.get_*`),
  Camera Polish P4 (remplace flag local par `AccessibilityService.get_camera_*_mult`),
  Enemy futur (`DEATH_TWEEN_DURATION_MS` reduce_motion variant).
