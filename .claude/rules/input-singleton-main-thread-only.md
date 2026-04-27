---
name: input-singleton-main-thread-only
scope_files:
  - src/**/*.gd
registry_forbidden_pattern: input_singleton_access_from_non_main_thread
source:
  - ADR-0004 D-7
  - ADR-0004 VC-7
---

# Input Singleton — Main Thread Only

Le singleton Godot `Input` (y compris `Input.mouse_mode`, `is_action_pressed`,
`get_vector`, `parse_input_event`, etc.) n'est pas documenté thread-safe. Tout
accès depuis un `Thread` non-main, un `WorkerThreadPool.add_task` callback, ou
un `Callable.call_deferred` résultant d'un thread non-main peut produire :

- Data races silencieuses sur l'état `mouse_mode`
- Deadlocks sur le lock interne (pas documenté explicitement par Godot)
- État incohérent vu depuis le main thread post-switch

## Scope

**Fichiers** : tout `src/**/*.gd`.

**Interdit** : accès à `Input.*` depuis :

- Corps d'un `Thread.start(func(): ...)` ou équivalent
- Callback `WorkerThreadPool.add_task(Callable(...))`
- `Callable.call_deferred` dont l'appelant est un thread non-main

**Autorisé** : `Input.*` depuis `_ready`, `_process`, `_physics_process`,
`_input`, `_unhandled_input`, `_notification`, handlers de signaux, API
publique appelée depuis le main thread.

## Forbidden Patterns

Lint cover-all : si un fichier `src/` contient à la fois une référence à `Input.`
et une référence à un contexte thread (`Thread`, `WorkerThreadPool`,
`call_deferred`), inspecter manuellement. Au MVP, la base de code ne contient
aucun `Thread`, donc le scan retourne zéro match → pass automatique.

| Contexte | Regex | Action |
|----------|-------|--------|
| Mention Thread | `\bThread\s*(\(|\.new\b|\.start\b)` | Flag si combiné avec `Input.` |
| WorkerThreadPool | `\bWorkerThreadPool\s*\.` | Flag si combiné avec `Input.` |
| Cross-thread deferred | `call_deferred.*Input\.` | Flag immédiat |

## Enforcement

### Local

```bash
# 1. Lister tous les fichiers qui touchent Input.
mapfile -t files < <(grep -rlE '\bInput\s*\.' src/ || true)

# 2. Pour chacun, vérifier l'absence de contextes thread
for f in "${files[@]}"; do
  if grep -qE '\bThread\s*(\(|\.new|\.start)|\bWorkerThreadPool\s*\.' "$f"; then
    echo "REVIEW: $f touches Input.* AND mentions Thread/WorkerThreadPool"
  fi
done
```

Zéro `REVIEW` = lint pass (cover-all au MVP).

### CI (GitHub Actions)

Intégré dans `.github/workflows/tests.yml` — job `lint-input-main-thread`.
Le job inspecte les fichiers `src/**/*.gd` et échoue si un fichier mentionne
à la fois `Input.*` et un contexte thread, sauf marquage explicite (commentaire
`# lint-input-thread-ok: <raison>` accepté pour exception documentée).

## Exceptions Futures

Le futur Accessibility System (Tier 3) pourra avoir besoin de capture
d'état depuis un thread dédié (features hold-to-repeat, sticky keys).
Le pattern recommandé sera :

- Capturer `Input.*` au dernier tick main dans une variable atomique / `Semaphore`
- Lire cette variable depuis le thread
- Jamais accès direct à `Input.*` depuis le thread

Ce pattern requiert un ADR dédié avant implémentation (amendement ADR-0004
ou nouvel ADR Accessibility).

## Source

- ADR-0004 D-7 (main-thread only)
- ADR-0004 VC-7 (lint statique cover-all)
- Control manifest Foundation layer forbidden pattern
  `input_singleton_access_from_non_main_thread`
