# Story 008: Perf gate ConfigFile.save() budget < 1 ms SSD reference (ADVISORY)

> **Epic**: Save/Load System
> **Status**: Ready
> **Layer**: Foundation / Persistence
> **Type**: Logic
> **Manifest Version**: 2026-04-23
> **Estimate**: ~1h — t-shirt XS
> **Risk**: LOW
> **Priority**: ADVISORY (cosmetic CI guard — non-bloquant `/story-done`)

## Context

**GDD**: `design/gdd/save-load-system.md` r1
**Requirement**: F-SAV-1 (perf budget `ConfigFile.save() ≈ 0.3 ms` SSD M1, marge ×55 sur frame 16.6 ms @ 60fps)

**ADR Governing Implementation**: ADR-0010 — Accepted 2026-04-27
**ADR Decision Summary**: D-1 ConfigFile budget < 1 ms SSD reference. ADR-0010 ne fixe pas un perf gate strict CI — story-008 livre la mesure périodique pour détecter régression.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**:
- `Time.get_ticks_usec()` retourne wall-clock microseconde resolution.
- ConfigFile.save() perf domine par I/O OS (write syscall) + sérialization texte. Sur SSD M1 ~0.3 ms, sur HDD spinning peut atteindre 5-10 ms.
- Variance run-to-run : 5-10% sur SSD, jusqu'à 3× sur HDD. Mesure P95 + outliers exclus = signal stable.
- CI hardware variance significative — gate ADVISORY au CI (runner heterogène).

**Control Manifest Rules (Foundation Persistence)**:
- **Required**: `ConfigFile.save() < 1 ms` SSD reference (F-SAV-1 / AC-SAV-2 ADVISORY).
- **Forbidden**: bloquer le merge sur perf gate CI ADVISORY (false positive sur HDD CI runners).
- **Guardrail**: si HDD détecté, graceful degradation accepté (skip ou seuil relâché ×10).

---

## Acceptance Criteria

*From GDD `design/gdd/save-load-system.md`, scoped to this story:*

- [ ] **AC-SAV-26** [Performance] [BLOCKING] : GIVEN file MVP ~100 bytes, WHEN `save_int` 60 fois consécutifs (simulation 1 sec @ 60 fps avec save chaque frame), THEN durée totale < 60 ms (i.e. < 1 ms / call avg). Mécanisme : perf test GUT — Time.get_ticks_usec() deltas. F-SAV-1 budget verification.
- [ ] **AC-SAV-27** [Performance] [ADVISORY] : GIVEN file Tier 2+ schema simulé (10 keys, ~2 KB), WHEN save burst 10 saves consécutifs, THEN total < 50 ms. Mécanisme : perf scaling test. Advisory MVP, BLOCKING Tier 2+.

---

## Implementation Notes

*Derived from F-SAV-1 + ADR-0010 D-1:*

1. **Créer `tests/performance/save_load_budget_test.gd`** :
   ```gdscript
   extends GutTest

   const SAMPLES_AC_SAV_26: int = 60
   const BUDGET_MS_AC_SAV_26: float = 60.0  # 60 saves × 1 ms target = 60 ms total

   func test_ac_sav_26_save_int_burst_60_under_60ms() -> void:
       var save_load: Node = get_node("/root/SaveLoadSystem")
       assert_true(save_load._is_ready(), "AC-SAV-26 prerequisite : SaveLoadSystem ready")

       var start_usec: int = Time.get_ticks_usec()
       for i in range(SAMPLES_AC_SAV_26):
           save_load.save_int("perf_k_" + str(i), i)
       var elapsed_ms: float = (Time.get_ticks_usec() - start_usec) / 1000.0

       if _is_likely_hdd():
           print("AC-SAV-26 SKIP : HDD detected, %.1f ms (graceful degradation)" % elapsed_ms)
           pending("HDD detected — perf gate skipped per ADR-0010 D-1 graceful degradation")
           return

       assert_lt(elapsed_ms, BUDGET_MS_AC_SAV_26,
           "AC-SAV-26 : 60 save_int prennent %.2f ms ≥ %.0f ms budget — perf régression" % [elapsed_ms, BUDGET_MS_AC_SAV_26])

   func _is_likely_hdd() -> bool:
       # Heuristique simple : si la première save prend > 5 ms, on assume HDD ou CI low-perf
       var save_load: Node = get_node("/root/SaveLoadSystem")
       var start: int = Time.get_ticks_usec()
       save_load.save_int("hdd_probe", 0)
       var first_save_ms: float = (Time.get_ticks_usec() - start) / 1000.0
       return first_save_ms > 5.0
   ```

2. **AC-SAV-27 Tier 2+ scaling** (ADVISORY) — implémenter optionnellement :
   ```gdscript
   func test_ac_sav_27_burst_10_saves_2kb_file_under_50ms() -> void:
       # Simuler file 2 KB : pre-saver 10 keys avec valeurs string longues
       var save_load: Node = get_node("/root/SaveLoadSystem")
       for i in range(10):
           save_load.save_string_array("padding_" + str(i),
               [&"id_a", &"id_b", &"id_c", &"id_d", &"id_e"])  # ~50 bytes par key

       var start: int = Time.get_ticks_usec()
       for i in range(10):
           save_load.save_int("burst_" + str(i), i)
       var elapsed_ms: float = (Time.get_ticks_usec() - start) / 1000.0

       if _is_likely_hdd():
           pending("HDD detected")
           return
       assert_lt(elapsed_ms, 50.0, "AC-SAV-27 : burst 10 saves @ ~2KB = %.1f ms ≥ 50 ms" % elapsed_ms)
   ```

3. **CI integration** : ajouter job `perf-save-load-budget` à `.github/workflows/tests.yml` avec flag ADVISORY (continue-on-error: true). Permet tracking perf historique sans bloquer le merge sur runner HDD.

4. **NE PAS** ajouter de logging / telemetry persistant (R-SAV-10 zero outbound + scope MVP).

---

## Out of Scope

- **Async batch perf** (OQ-SAV-3) : Tier 2+ — pas testé MVP.
- **Atomic write perf** (OQ-SAV-4) : Tier 2+ — pas testé MVP.
- **Profiling fine-grained** (which line cost most) : optionnel post-MVP si playtest révèle drop frame perçu.

---

## QA Test Cases

**AC-SAV-26** — burst 60 save_int < 60 ms :
- Given : SaveLoadSystem ready, file MVP ~100 bytes (3 keys MVP)
- When : `for i in range(60): save_int("perf_k_" + str(i), i)` enclosed entre `Time.get_ticks_usec()`
- Then : delta total < 60 ms (< 1 ms / call moyenne SSD)
- Edge cases :
  - HDD detected (probe > 5 ms) → test passes via `pending()` skip (graceful degradation ADR-0010 D-1)
  - Variance high run-to-run → exécuter 3 runs, prendre médiane (Tier 2+ amélioration)

**AC-SAV-27** — burst 10 save_int @ ~2 KB file < 50 ms (ADVISORY) :
- Given : SaveLoadSystem ready avec 10 keys padding (~2 KB total file size)
- When : `for i in range(10): save_int("burst_" + str(i), i)`
- Then : total < 50 ms
- Edge cases : ADVISORY — failure n'empêche pas `/story-done`, juste alerte.

---

## Test Evidence

**Story Type**: Logic (perf — sub-type)
**Required evidence**:
- `tests/performance/save_load_budget_test.gd` — must exist (1 test BLOCKING AC-SAV-26 + 1 test ADVISORY AC-SAV-27)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: **story-001 + 002** (skeleton + scalar verbs minimum pour le burst test)
- Unlocks: Pillar 1 régression CI tracking — visibilité perf historique
- **ADVISORY** : story-008 peut être différée Sprint 1+ sans bloquer Sprint A consumers (Credit/Shop/Menu).
