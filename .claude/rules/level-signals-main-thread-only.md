# Level Signals — Main Thread Only

Tous les `emit_signal(...)` et appels `.emit(...)` dans `src/gameplay/level/**/*.gd`
doivent s'exécuter depuis le main thread. Émettre un signal depuis un thread non-main
peut produire :

- Data races sur les handlers connectés qui mutent l'état de scène
- Deadlocks sur les locks internes de Godot (signal table, connection list)
- Comportement indéfini lors de `queue_free()` ou `add_child()` depuis un handler

## Contexte

ADR-0005 D-4 impose que tous les signaux du Level System soient émis depuis
`_physics_process` (main thread garanti par Godot). Le pattern `_assert_main_thread()`
(implémenté dans `LevelSystemScript._assert_main_thread()`) vérifie
`OS.get_thread_caller_id() == OS.get_main_thread_id()` avant chaque emit.

## Scope

**Fichiers** : tout `src/gameplay/level/**/*.gd`.

**Interdit** : appel à `.emit(...)` ou `emit_signal(...)` depuis :

- Corps d'un `Thread.start(func(): ...)` ou équivalent
- Callback `WorkerThreadPool.add_task(Callable(...))`
- Callback `ResourceLoader.load_threaded_request` (async OK, emit pas depuis le callback)
- `call_deferred` dont l'appelant est un thread non-main

**Autorisé** : `.emit(...)` depuis :

- `_ready`, `_process`, `_physics_process` (main thread garanti Godot)
- `_input`, `_unhandled_input`, `_notification`
- Handlers de signaux (body_entered, body_exited, area_entered, etc.) — context physics step
- Autoload `_init` (avant SceneTree — main thread)
- `call_deferred` appelé depuis le main thread (deferred exec sur main thread)

## Forbidden Patterns

Lint cover-all : si un fichier `src/gameplay/level/` contient à la fois une référence
à `.emit(` ou `emit_signal(` et une référence à un contexte thread, inspecter manuellement.

| Contexte | Regex | Action |
|----------|-------|--------|
| Mention Thread | `\bThread\s*(\(|\.new\b|\.start\b)` | Flag si combiné avec `.emit(` |
| WorkerThreadPool | `\bWorkerThreadPool\s*\.` | Flag si combiné avec `.emit(` |
| Cross-thread deferred | `call_deferred.*\.emit\s*\(` | Flag immédiat (vérifier thread origin) |

## Enforcement

### Local

```bash
# 1. Lister tous les fichiers level qui émettent des signaux
mapfile -t files < <(grep -rlE '\.(emit|emit_signal)\s*\(' src/gameplay/level/ || true)

# 2. Pour chacun, vérifier l'absence de contextes thread
for f in "${files[@]}"; do
  if grep -qE '\bThread\s*(\(|\.new|\.start)|\bWorkerThreadPool\s*\.' "$f"; then
    echo "REVIEW: $f touches .emit() AND mentions Thread/WorkerThreadPool"
  fi
done
```

Zéro `REVIEW` = lint pass (cover-all au MVP).

### CI (GitHub Actions)

Intégré dans `.github/workflows/tests.yml` — job `lint-level-signals-main-thread`.
Le job inspecte les fichiers `src/gameplay/level/**/*.gd` et échoue si un fichier
mentionne à la fois `.emit(` et un contexte thread, sauf marquage explicite.

Exception acceptée : commentaire `# lint-emit-thread-ok: <raison>` sur la ligne
concernée (justification obligatoire pour audit trail).

## Pattern recommandé : deferred emit depuis _physics_process

```gdscript
# CORRECT — pattern LevelSystemScript
# Flag positionné depuis _process (peut être appelé hors main thread pour status check)
var _pending_my_event: bool = false

func _physics_process(_delta: float) -> void:
    if _pending_my_event:
        _pending_my_event = false
        _assert_main_thread()   # guard ADR-0005 D-4
        my_signal.emit(payload)

# INCORRECT — emit direct depuis callback ResourceLoader async
func _on_resource_loaded(resource: Resource) -> void:
    # NE PAS FAIRE — ce callback peut arriver depuis un thread non-main
    my_signal.emit(resource)  # VIOLATION
```

## Exceptions Futures

Tout futur système (Audio System, CheckpointSystem) qui devra émettre des signaux
depuis un contexte asynchrone devra :

1. Capturer l'état dans une variable atomique depuis le thread
2. Émettre le signal uniquement depuis `_physics_process` (main thread)
3. Documenter le pattern via un amendement ADR-0005 ou un nouvel ADR
4. Marquer le fichier avec `# lint-emit-thread-ok: <raison>` si l'exception est prouvée sûre

## Source

- ADR-0005 D-4 (emit depuis physics process uniquement)
- ADR-0005 D-8 (mutation d'état AVANT emit)
- story-022 TR-lvl-044
- `LevelSystemScript._assert_main_thread()` — implémentation de référence
