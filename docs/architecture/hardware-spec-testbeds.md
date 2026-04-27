# Hardware Spec — CI Testbeds

> **Status** : Draft v1 (créé 2026-04-23 suite r2 Player Combat review BLOCKING performance-analyst 01)
> **Owner** : technical-director
> **Consumed by** : ACs performance (AC-CMB-35a, AC-CMB-35b, AC-CMB-42, futurs ACs perf Movement/Camera/Rendering), CI benchmark pipelines
> **Reference budget** : `.claude/docs/technical-preferences.md` Performance Budgets (60 fps min, 16.6 ms frame budget, <500 draw calls, 2 GB RAM / 1 GB VRAM target)

---

## Purpose

Tout AC classifié `[Integration — BLOCKING]` avec une métrique performance (frame time, memory, draw calls, latency) DOIT référencer une machine testbed reproductible. Sans spec hardware figée, un benchmark passant sur une machine puissante peut masquer une régression fatale sur le minimum supporté du projet.

Ce document définit deux tiers testbed : **Minimum supporté** (gate obligatoire) et **Cible confort** (target 60 fps stable marge 40%).

---

## Tier 1 — Minimum Supporté (CI gate obligatoire)

Représente le **hardware le plus bas** sur lequel le jeu doit tourner à 60 fps locked (vsync) sans régression critique. Aligné sur `technical-preferences.md` Performance Budgets (2 GB RAM / 1 GB VRAM target : entry-level gaming laptop).

| Composant | Spec minimum |
|---|---|
| CPU | Intel Core i3-10100F @ 3.6 GHz (4 cores / 8 threads) ou équivalent AMD Ryzen 3 3100 |
| GPU | NVIDIA GTX 1050 3 GB ou équivalent (AMD RX 560 4 GB, Intel Arc A380) |
| RAM | 8 GB DDR4 @ 2400 MHz |
| Stockage | SATA SSD 256 GB (pas HDD — loading budget incompatible) |
| OS | Windows 10 21H2 (64-bit) |
| Godot | 4.6 stable (pinned `docs/engine-reference/godot/VERSION.md`) |
| Renderer | Forward+ (cible projet) |
| Résolution benchmark | 1920×1080 @ 60 Hz vsync on |

**Exit criteria Minimum** (valides pour AC-CMB-35a, AC-CMB-35b, AC-CMB-42) :
- `frame_time p99 <= 16.6 ms` (60 fps locked)
- `frame_time p50 <= 12.0 ms` (marge ≥28% sur moyenne)
- `draw_calls <= 500` (budget Chrome Zen)
- `memory_static` delta post-soak 1000 cycles <= +500 KB (AC-CMB-37)

**Un AC perf qui fail sur Minimum = BLOCKING — pas de ship.**

---

## Tier 2 — Cible Confort (target 60 fps headroom)

Représente le hardware visé pour confort joueur typique — 60 fps stable avec 40% de marge frame time.

| Composant | Spec cible |
|---|---|
| CPU | Intel Core i5-12400F @ 4.4 GHz (6 cores / 12 threads) ou équivalent Ryzen 5 5600X |
| GPU | NVIDIA GTX 1650 Ti 4 GB ou équivalent (AMD RX 6500 XT) |
| RAM | 16 GB DDR4 @ 3200 MHz |
| Stockage | NVMe SSD 512 GB |
| OS | Windows 10 22H2 ou Windows 11 |
| Godot | 4.6 stable |
| Renderer | Forward+ |
| Résolution benchmark | 1920×1080 @ 60 Hz (vsync on), headroom validé à 120 Hz sans vsync |

**Exit criteria Confort** :
- `frame_time p99 <= 10.0 ms` (headroom 40% sur budget 16.6 ms)
- `frame_time p50 <= 6.0 ms`
- `draw_calls <= 400`
- Pas de GC spikes visible p99

**Un AC perf qui fail sur Confort mais pass sur Minimum = WARNING — investiguer mais pas BLOCKING.**

---

## Tier 3 — Haut de gamme (informatif, pas CI gate)

Référence "modern gaming desktop 2025" pour valider que le jeu scale correctement en fréquence (120+ fps) et résolution (1440p/2160p). Pas de gate CI — uniquement pour informer les perf envelopes post-launch.

| Composant | Spec haut de gamme |
|---|---|
| CPU | Intel Core i7-13700K ou Ryzen 7 7700X |
| GPU | NVIDIA RTX 4070 12 GB ou équivalent |
| RAM | 32 GB DDR5 |
| Résolution | 2560×1440 @ 120 Hz |

---

## Microbenchmark Protocol (AC-CMB-35a, futurs `tests/perf/`)

Pour les microbenchmarks isolés (scene minimale, bloc de code mesuré) :

- **Instrumentation** : `Time.get_ticks_usec()` avant/après le bloc, log dans `Array[int]` en GDScript, calcul p50/p99 en fin de run.
- **Sample count** : **1000 samples minimum** (16.7 sec à 60 Hz) — 240 samples (r1 spec) jugés insuffisants pour p99 robuste par performance-analyst. Position p99 sur 1000 = rang 990, granularité ~0.1%.
- **Warmup** : premiers 60 samples (1 sec) ignorés — compile JIT + cache warmup.
- **Evidence path** : `tests/perf/<system>-<bench>-bench-log.md` avec p50/p99/hardware/Godot version/date.

## Integrated Benchmark Protocol (AC-CMB-35b, futurs ACs perf intégrés)

Pour les benchmarks scène complète (frame time global, draw calls, memory) :

- **Instrumentation préférée** : `Time.get_ticks_usec()` dans `_process` + `_physics_process` (cohérent microbench), **pas** le Godot Profiler intégré (résolution ~10 ms insuffisante + overhead 1-3 ms). Logger dans Array puis p50/p99.
- **Sample count** : **500 frames minimum** (8.3 sec), **1000 frames recommandé** (16.7 sec — capte cycles GC périodiques).
- **Scène** : aussi proche que possible de la scène gameplay réelle (pas de "scene minimale" pour ce tier).
- **Evidence path** : identique microbench + screenshot Profiler Godot en annexe si utile.

---

## Update protocol

- Ce document est la **source of truth** pour toute spec hardware CI.
- Modifications : PR review obligatoire par technical-director + performance-analyst.
- Version bump : incrémenter `Status: Draft vN` à chaque modification substantielle (changement tier minimum, nouveau composant, exit criteria retune).
- Régression : si un minimum supporté change (ex: 1 GB VRAM → 2 GB VRAM), re-valider tous les ACs perf passés et informer les GDDs concernés via `/propagate-design-change`.

---

## Cross-references

- `.claude/docs/technical-preferences.md` — Performance Budgets projet (source du minimum 2 GB RAM / 1 GB VRAM)
- `docs/engine-reference/godot/VERSION.md` — Godot version pinned (doit matcher le Godot testbed)
- `docs/architecture/adr-0001-physics-rate-60hz.md` — 60 fps locked contract
- ACs consommateurs :
  - `design/gdd/player-combat-system.md` AC-CMB-35a, AC-CMB-35b, AC-CMB-37, AC-CMB-42
  - Futurs ACs perf Movement, Camera, Rendering, Audio
