# Hardware Spec Testbeds — Matrice Tier 1/2/3

**Statut** : Document baseline · 2026-05-11 · Pre-Production
**Sign-off** : 4 gates en attente (voir §Gap Analysis TD-013)
**Sprint ref** : `production/sprints/sprint-pre-production-2026-05-05.md` — TD-013 (W-1+W-2)

---

## Modèle à 3 tiers

| Tier | Rôle | Gate obligatoire |
|------|------|-----------------|
| **Tier 1 — Minimum spec MVP** | Spec cible entrée de gamme — toute session de jeu doit passer ici | OUI — bloque gate Pre-Production → Production |
| **Tier 2 — Recommended** | Expérience confortable attendue — objectif marketing "runs great" | NON — informatif |
| **Tier 3 — Optimal** | Plein potentiel rendu — futurs DLCs / post-launch contenu enrichi | NON — informatif |

Le Tier 1 est la seule spec qui **gate** les milestones. Tier 2 et Tier 3 servent
au profiling et à la communication marketing.

---

## Tier 1 — Minimum spec MVP

Spec cible : entry-level gaming laptop ou desktop de génération 2020.

| Composant | Spec |
|-----------|------|
| **CPU** | Intel Core i3-10100F (4C/8T, 3.6 GHz boost 4.3 GHz, Comet Lake) |
| **GPU** | NVIDIA GeForce GTX 1050 2 GB VRAM |
| **RAM** | 8 GB DDR4 |
| **OS** | Windows 10 64-bit (22H2) |
| **Résolution** | 1920×1080 (1080p) |
| **Refresh rate** | 60 Hz, V-sync activé |
| **Stockage** | HDD 7200 RPM (SSD non requis pour gates) |
| **Driver GPU** | NVIDIA 537.x ou supérieur |

Rationale : i3-10100F + GTX 1050 couvre ~30 % du parc Steam 2024–2025
(Steam Hardware Survey Q4 2024). GTX 1050 2 GB est le bas de gamme compatible
Vulkan + Forward+ Godot 4.6 sans fallback Compatibility renderer.

---

## Tier 2 — Recommended spec

| Composant | Spec |
|-----------|------|
| **CPU** | Intel Core i5-10400F (6C/12T, 2.9 GHz boost 4.3 GHz) |
| **GPU** | NVIDIA GeForce GTX 1660 6 GB VRAM |
| **RAM** | 16 GB DDR4 |
| **OS** | Windows 10/11 64-bit |
| **Résolution** | 1920×1080 (1080p) ou 2560×1440 (1440p) |
| **Refresh rate** | 144 Hz, V-sync ou G-Sync |
| **Stockage** | SSD NVMe |

---

## Tier 3 — Optimal spec

| Composant | Spec |
|-----------|------|
| **CPU** | Intel Core i7-12700K (8P+4E, 3.6 GHz boost 5.0 GHz, Alder Lake) |
| **GPU** | NVIDIA GeForce RTX 3070 8 GB VRAM |
| **RAM** | 32 GB DDR5 |
| **OS** | Windows 11 64-bit |
| **Résolution** | 2560×1440 (1440p) |
| **Refresh rate** | 144 Hz, G-Sync / FreeSync |
| **Stockage** | SSD NVMe PCIe 4.0 |

---

## Dev Baseline — Apple M4 (NOT certified Tier 1)

> **AVERTISSEMENT** : les mesures ci-dessous sont des baselines informatives
> de développement. Elles ne valent pas comme sign-off Tier 1 et ne débloquent
> aucun gate milestone.

| Composant | Spec |
|-----------|------|
| **Machine** | Apple Mac mini (M4, 2024) |
| **CPU** | Apple M4 (10 cores — 4P + 6E) |
| **GPU** | Apple M4 GPU 10 cores (UMA) |
| **RAM** | 16 GB unified memory |
| **OS** | macOS 15 (Sequoia) |
| **Résolution** | Variable (dev monitor) |

Données disponibles dans `tests/perf/combat-integration-frametime-log.md` :
- CombatSystem `_physics_process` soak : p99 ≤ 0.119 ms (pire run) — très en
  dessous du threshold 16.6 ms, mais c'est uniquement la logique physics
  (RenderingServer headless → `draw_calls_max = 0`, non représentatif).
- Ces chiffres sont utiles pour détecter les régressions de complexité algorithmique
  (O(n²) dans ShapeCast par exemple), pas pour valider le budget rendering réel.

Pourquoi M4 ne certifie pas Tier 1 :
- Architecture ARM vs x86 — pas de comparaison directe avec i3-10100F
- GPU UMA shared memory vs dGPU GDDR5 dédié — profil VRAM radicalement différent
- macOS Forward+ Godot via MoltenVK — pas le chemin Vulkan natif Windows
- `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` retourne 0 en headless (pas de RenderingServer)

---

## Gates de performance par Tier

### Tier 1 (gates bloquants pour Production)

| Gate | Seuil | Méthode de mesure | Status |
|------|-------|-------------------|--------|
| **Frame time p99** | ≤ 16.6 ms (60 fps) | Godot `Performance.TIME_PROCESS` sur scène de jeu complète | ❌ non mesuré sur Tier 1 |
| **RAM usage** | ≤ 2 048 MB | Task Manager / `Performance.MEMORY_STATIC` runtime | ❌ non mesuré sur Tier 1 |
| **VRAM usage** | ≤ 1 024 MB | GPU-Z ou équivalent en session de jeu | ❌ non mesuré sur Tier 1 |
| **Draw calls par frame** | ≤ 500 | `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` (non headless) | ❌ non mesuré sur Tier 1 |
| **Load time etage** | ≤ 5 s (HDD Tier 1) | Chronométrage boot → etage 1 playable | ❌ non mesuré sur Tier 1 |

Source seuils : `.claude/docs/technical-preferences.md` (Memory Ceiling) +
game-concept.md Pillar 1 (60 fps locked vsync).

### Tier 2 / Tier 3 (informatifs)

Tier 2 cible : 60+ fps constant à 1440p, RAM ≤ 1 500 MB, draw calls ≤ 350.
Tier 3 cible : 120+ fps à 1440p, VRAM ≤ 600 MB.

---

## CI vs hardware réel

Le CI GitHub Actions (`ubuntu-latest`) est **headless** — il ne mesure **pas**
le vrai coût rendering :

- `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` retourne `0` systématiquement (pas de GPU)
- Pas de VRAM physique mesurable
- Les frame time CI mesurent uniquement la logique GDScript + Jolt physics
  (valeur utile pour régressions algorithmiques, pas pour gates rendering)

Règle : **aucun gate rendering ne peut être validé par CI seul**. Les gates
draw_calls et frame time rendering nécessitent un run sur testbed physique ou
cloud GPU.

---

## Gap Analysis — TD-013 (W-1+W-2)

Référence sprint : `production/sprints/sprint-pre-production-2026-05-05.md` §Tech-debt #7.

| Gap | Description | Impact | Status |
|-----|-------------|--------|--------|
| **W-1** | Aucun testbed Tier 1 physique disponible | draw_calls gate non mesurable | ❌ OPEN |
| **W-2** | Aucun CI GPU pour bench rendering full-stack | frame time rendering gate non mesurable | ❌ OPEN |
| **W-3** | Baseline draw_calls M4 non disponible (headless retourne 0) | Impossible d'extrapoler vers Tier 1 | ❌ OPEN |
| **W-4** | Aucune session playtest humaine sur Tier 1 | feel + input latency non validés sur spec min | ❌ OPEN |

**Conclusion** : gate Pre-Production → Production bloqué sur 4 items hardware
tant qu'aucun testbed Tier 1 (physique ou cloud) n'est disponible.
Vertical Slice playtest (gate #1) peut être réalisé sur M4 pour la logique de jeu,
mais le sign-off performance Tier 1 requiert du matériel cible.

---

## Plan — Recrutement testbed Tier 1

### Option A — Testbed physique

1. Localiser un PC avec i3-10100F + GTX 1050 (occasion ~150–200 EUR en 2026)
2. Windows 10 22H2 propre, drivers NVIDIA 537.x
3. Installer Godot 4.6 + project (pas d'éditeur requis — templates export suffisent)
4. Exécuter le runbook ci-dessous

### Option B — Cloud GPU (Paperspace / Shadow)

- Paperspace : instance P4000 (~0.51 $/h) — GTX 1080 équivalent, Windows disponible
  (surspécifié vs Tier 1 — valable pour draw_calls et RAM, pas pour frame time worst-case)
- Shadow PC : GTX 1080 Ti — même remarque
- Limitation : pas d'équivalent GTX 1050 en cloud → les gates frame time Tier 1
  strict ne peuvent pas être validés en cloud GPU (overhead VM + réseau ≠ bare metal)
- Recommandation : Option A préférée pour sign-off officiel, Option B acceptable
  pour draw_calls + RAM si Option A impossible avant gate Production

### Runbook testbed Tier 1

```bash
# 1. Lancer le build export depuis le testbed (Windows, Godot 4.6 export template)
# Ou : copier le répertoire projet + ouvrir avec Godot 4.6 editor une fois pour cache

# 2. Mesurer frame time en session de jeu (etage 1, combat actif)
# Via Godot debugger profiler OU overlay MSI Afterburner → exporter CSV

# 3. Mesurer RAM au pic (Task Manager > Détails > SetterProcess)
# Cible : ≤ 2 048 MB

# 4. Mesurer VRAM au pic (GPU-Z > Sensors > GPU Memory Used)
# Cible : ≤ 1 024 MB

# 5. Mesurer draw calls (Godot Remote Debugger > Monitors > draw_calls)
# Cible : ≤ 500 par frame

# 6. Enregistrer les résultats dans production/qa/evidence/
# Format JSON :
# {
#   "date": "2026-MM-DD",
#   "hardware": "i3-10100F + GTX 1050 2GB",
#   "os": "Windows 10 22H2",
#   "godot_version": "4.6",
#   "scene": "etage_01.tscn",
#   "frame_time_p99_ms": <valeur>,
#   "ram_peak_mb": <valeur>,
#   "vram_peak_mb": <valeur>,
#   "draw_calls_max": <valeur>,
#   "verdict": "PASS|FAIL"
# }
```

Evidence attendue : `production/qa/evidence/tier1-sign-off-YYYY-MM-DD.json`

---

## Références

- `.claude/docs/technical-preferences.md` — Memory Ceiling 2 GB RAM / 1 GB VRAM
- `production/sprints/sprint-pre-production-2026-05-05.md` — TD-013 (W-1+W-2), perf gates
- `tests/perf/combat-integration-frametime-log.md` — baselines M4 (informational)
- `production/qa/smoke-2026-05-04.md` — smoke check W-1+W-2 warnings origin
- `production/qa/smoke-2026-05-05.md` — confirmation DEFERRED perf gates hardware
- `docs/architecture/adr-0001-*.md` — Pillar 1 FLOW 60 fps authority
