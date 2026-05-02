---
name: no-alloc-hot-paths
scope_files:
  - src/core/input_manager.gd
scope_functions:
  - _unhandled_input
  - _physics_process
  - _record_latency_sample
registry_forbidden_pattern: allocating_input_hot_path
source:
  - ADR-0004 D-8
  - ADR-0004 VC-3
  - design/gdd/input-system.md AC-PF-2
---

# No Alloc Hot Paths — InputManager

Les hot paths de `InputManager` ne doivent jamais allouer de mémoire heap à
l'exécution. Toute allocation dans `_unhandled_input`, `_physics_process` ou
`_record_latency_sample` casse le Pillar 1 (FLOW AVANT TOUT — input latency
< 1 frame) et fait grandir `MEMORY_STATIC` linéairement pendant le gameplay.

AC-PF-4 (story-008) gate le delta 60 s à < 64 KB. Ce lint statique capture
les violations avant qu'elles ne se propagent, et sert de garde-fou pour les
reviews de code quand le stress test lui-même n'est pas relancé.

## Scope

**Fichier** : `src/core/input_manager.gd` uniquement.

**Fonctions gardées** (substring match) :
- `_unhandled_input` — ~1000 Hz sur flick souris, saturation hot path
- `_physics_process` — 60 Hz, chemin principal polling/swap
- `_record_latency_sample` — appelé depuis `_physics_process`, inclus par association

Les autres fonctions (`_ready`, `get_latency_p99_ms`, helpers `simulate_*`,
API publique) sont autorisées à allouer — elles ne tournent pas en hot path
(boot one-shot, lecture rare HUD, fixtures test debug-only).

## Forbidden Patterns

| Pattern | Regex | Raison |
|---------|-------|--------|
| `push_back(` sur Array/PackedArray | `\bpush_back\s*\(` | Realloc potentielle si capacité dépassée |
| Dictionary literal `{a = ...}` | `\{[^}]*=[^}]*\}` | Alloc heap à chaque évaluation |
| Array literal assigné `= [a, b]` | `=[[:space:]]*\[[^]]*,[^]]*\]` | Alloc heap à chaque évaluation |
| `Dict.new()` / `Array.new()` | `\.new\s*\(\s*\)` | Alloc explicite |
| `String(` cast | `\bString\s*\(` | Boxing → alloc heap |
| `"literal" +` concat | `"[^"]*"[[:space:]]*\+` | Nouvelle String allouée |

Les commentaires (lignes commençant par `#` après indentation) sont exclus — un
commentaire de type `# pas de push_back ici` ne viole pas la règle.

**Extraction function-scoped** : le lint n'analyse que les bodies des fonctions
listées dans `scope_functions` (entre `func <name>(...)` et le prochain
top-level `func`). Cela exclut :
- `_ready()` et boot-time code (allocation one-shot autorisée)
- Helpers `simulate_*` (debug-only, `InputEvent*.new()` autorisé par D-9)
- API publique non-hot-path (`get_latency_p99_ms`, `request_disable`, …)
- Déclarations de type module-level (`var _pressed: Dictionary[StringName, bool] = {}`)

Le pattern Array literal est restreint à `= [...]` pour éviter les faux
positifs sur les annotations de type `Dictionary[K, V]` / `Array[T]`.

## Enforcement

### Local

```bash
# Répéter pour chaque forbidden pattern
grep -nE 'PATTERN' src/core/input_manager.gd | grep -v '^[^:]*:\s*#' || true
```

Un match non-commenté dans une fonction hot path = violation.

### CI (GitHub Actions)

Intégré dans `.github/workflows/tests.yml` — job `lint-input-hot-paths`.
Le job échoue si un pattern forbidden apparaît dans une fonction scope.

### Fallback si AC-PF-4 échoue

Si le stress runner révèle un delta ≥ 64 KB malgré lint clean, investiguer
les sources cachées (COW Dictionary swap, realloc PackedArray via
assignation `arr[oob] = x`). Plan de repli documenté : replier le swap
`_pressed ↔ _consumed` sur 2× `PackedByteArray` parallèles indexés par
`ACTIONS_MVP.find(action)` (ADR-0004 Risk 2).

## Exceptions

Aucune au MVP. Tout ajout d'exception doit être justifié dans un ADR
(amendement ADR-0004) et documenté ici avec régression test GUT associé.

## Source

- ADR-0004 D-8 (ring buffer zero-alloc)
- ADR-0004 VC-3 (gate 64 KB / 60 s)
- design/gdd/input-system.md AC-PF-2 / AC-PF-4
- TR-inp-007 (tr-registry.yaml)
