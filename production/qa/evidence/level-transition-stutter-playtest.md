# Playtest Evidence — Level Transition Stutter (AC-LVL-35b)

**Story**: story-017 — Load time F4 + frame-time gate
**AC**: AC-LVL-35b — No perceptible stutter at room_entered (PLAYTEST)
**Status**: [ ] Pending playtest — to be executed Sprint 1 post-meshes Chrome Zen
**Date**: TBD
**Signed off**: [ ] QA Lead, [ ] Producer

---

## Context

AC-LVL-35b complements the automated gate AC-LVL-35a (which validates
Performance.TIME_PROCESS p99 ≤ 14.0 ms in a 24-frame window around
room_entered). This playtest validates the perceptual aspect: a human
observer running 10 consecutive room transitions must perceive no
micro-pause or visible stutter.

This evidence doc becomes BLOCKING before story-017 can be closed as Done.

---

## Setup Procedure

1. Build: export Godot 4.6 project (debug build acceptable for Sprint 1)
2. Scene: load `tests/fixtures/level/etage_full_mvp.tscn` directly via
   ResourceLoader or via the LevelSystem (once production scenes are wired)
3. Player config: standard movement setup, no combat active
4. Camera: CameraArm standard (ADR-0002), FPS perspective
5. HUD: minimal or none (avoid HUD render cost polluting frame time perception)
6. Target hardware: Tier 1 entry-level gaming laptop (see `docs/architecture/hardware-spec-testbeds.md`)
7. Display: vsync ON at 60 Hz (ADR-0003 baseline mode)

---

## Test Procedure

Perform 10 consecutive room transitions: Room_00 → Room_01 → ... → Room_09.

For each transition:
1. Walk the player through the RoomTrigger Area3D boundary
2. Observe the moment the room_entered signal fires (may be visible via debug
   overlay or frametimer HUD if available)
3. Record any perceptible pause, freeze frame, or micro-stutter

---

## Pass Criteria

- No micro-pause visible during any of the 10 transitions
- Stutter threshold: < 1 frame perceived (< ~16.6 ms at 60 fps)
- No audio click or desync correlated with room transition
- No visual pop (geometry swap, culling artefact) coinciding with transition

---

## Evidence to Capture

- [ ] Video recording of the 10 transitions (screen capture at 60 fps minimum)
- [ ] Frame time overlay screenshot at the moment of each transition (optional but recommended)
- [ ] Notes on any observed stutter, even if below threshold

---

## Sign-off

| Role | Name | Date | Status |
|------|------|------|--------|
| QA Lead | | | [ ] Pending |
| Producer | | | [ ] Pending |

---

## Notes

This playtest is deferred to Sprint 1 because:

1. Chrome Zen meshes are not yet authored (story-022) — geometry stubs
   produce artificially low draw call counts and may not represent real
   transition costs.
2. PlayerController is not yet wired to the Level fixture — the playtest
   requires real movement input, not stub teleportation.
3. AC-LVL-35a (automated) provides a proxy until this sign-off is obtained.

Once Sprint 1 meshes and PlayerController are in place, re-run this playtest
and complete the sign-off table above.

**Source**: story-017 AC-LVL-35b, TR-lvl-036, ADR-0003 (Rendering Latency).
