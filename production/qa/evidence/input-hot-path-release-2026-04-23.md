# Input Hot-Path Release Profiling — AC-PF-5

> **Status : Pending — à remplir quand le testbed hardware d'entrée de gamme est disponible.**
> Voir `docs/architecture/hardware-spec-testbeds.md` pour les spécifications testbed.

## References

| Champ | Valeur |
|-------|--------|
| Story | `story-007` (Epic `input-system`) |
| Critère d'acceptation | **AC-PF-5** : release build hot-path ≤ 0.1 ms/frame p99 |
| ADR source | [ADR-0004](../../../docs/architecture/adr-0004-input-api-focus-handling.md) D-8 / Performance Implications |
| Fichier de benchmark | `tests/performance/input_benchmark.tscn` |
| Runner | `tests/performance/input_benchmark_runner.gd` |

## Procédure

### 1. Produire le build release headless

#### Linux / Windows (via Godot export)

```bash
# Export release Linux/X11 headless
godot --export-release "Linux/X11" builds/release/benchmark_linux

# Export release Windows
godot --export-release "Windows Desktop" builds/release/benchmark_windows.exe
```

> Note : les export templates release doivent être installés dans l'éditeur
> (Éditeur → Gérer les modèles d'export → Télécharger et installer).
> Le template headless Linux est le binaire `godot.linuxbsd.template_release.x86_64`.

#### Alternative : lancer depuis l'éditeur en mode release

```bash
# Depuis le répertoire projet, en passant le feature "release" explicitement
godot --headless --no-window res://tests/performance/input_benchmark.tscn
```

> Attention : cette commande tourne en mode **debug** (binaire éditeur).
> Pour AC-PF-5 (release), utiliser un export release ou le binaire
> `godot.linuxbsd.template_release.x86_64`.

### 2. Exécuter le benchmark headless

```bash
# Linux (après export)
./builds/release/benchmark_linux --headless -- res://tests/performance/input_benchmark.tscn

# Windows (après export)
builds\release\benchmark_windows.exe --headless -- res://tests/performance/input_benchmark.tscn
```

### 3. Localiser le log de résultats

Le log est écrit automatiquement dans :

```
production/qa/evidence/input-benchmark-YYYY-MM-DD.log
```

Format du log :

```
# Input benchmark — 2026-04-23T14:30:00
# Build: release, OS: Linux, CPU: Intel Core i5-1135G7
frames=1000 p50=X.XXX p95=X.XXX p99=X.XXX max=X.XXX
hot_path frames=300 p50=X.XXX p95=X.XXX p99=X.XXX max=X.XXX  (in ms)
# Gate AC-L-3  (lat p99 <= 16.0 ms): PASS|FAIL
# Gate AC-PF   (hp  p99 <= 0.100 ms): PASS|FAIL
```

> Note sur le hot-path en release build : l'accumulateur `_hot_path_frame_usec`
> est protégé par un guard `OS.has_feature("debug")` dans `input_manager.gd`.
> En release, il vaut toujours 0. Le benchmark détecte ce cas (tous zéros) et
> marque AC-PF comme SKIP (non mesuré par l'accumulateur interne).
>
> Pour mesurer AC-PF-5 en release, utiliser le **Godot Profiler** sur un build
> release avec le flag `--profile` ou analyser `Performance.TIME_PHYSICS_PROCESS`
> via un script de monitoring externe. La mesure cible reste ≤ 0.1 ms/frame p99
> sur le testbed d'entrée de gamme spécifié ci-dessous.

## Testbed cible

Voir `docs/architecture/hardware-spec-testbeds.md` pour la spécification complète.
Le testbed d'entrée de gamme (entrée de gamme laptop gaming) est la référence
pour la validation de ce critère.

## Résultats (à remplir)

### Testbed : Entrée de gamme (à définir)

| Métrique | p50 | p95 | p99 | max | Seuil | Résultat |
|----------|-----|-----|-----|-----|-------|----------|
| Latence input→publish (ms) | — | — | — | — | 16.0 ms | Pending |
| Hot-path CPU (ms/frame) | — | — | — | — | 0.1 ms | Pending |

### Testbed : Mid-range (optionnel)

| Métrique | p50 | p95 | p99 | max | Seuil | Résultat |
|----------|-----|-----|-----|-----|-------|----------|
| Latence input→publish (ms) | — | — | — | — | 16.0 ms | Pending |
| Hot-path CPU (ms/frame) | — | — | — | — | 0.1 ms | Pending |

## Condition de passage (AC-PF-5)

> **AC-PF-5** : Le coût CPU du hot-path InputManager (`_unhandled_input` +
> `_physics_process`) mesuré en build **release** sur le testbed d'entrée de gamme
> doit être **≤ 0.1 ms/frame p99** sur une fenêtre de 300 frames physiques
> consécutives avec injection d'un `InputEventAction` + un `InputEventMouseMotion`
> par frame.

Cette condition est **distincte** de AC-L-3 (latence totale input→publish ≤ 16 ms)
pour détecter toute régression d'un ordre de grandeur sur le seul coût CPU du
manager — indépendamment du budget de latence end-to-end.

## Sign-off

| Champ | Valeur |
|-------|--------|
| Testeur | — |
| Date | — |
| Plateforme | — |
| Build hash (git) | — |
| Verdict | Pending |
| Commentaires | — |
