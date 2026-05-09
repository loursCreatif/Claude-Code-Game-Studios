# MockCreditEconomy — fixture minimale pour tests HUD (story-001).
#
# Expose le même contrat que CreditEconomy autoload :
#   - enum SourceKind identique (KILL=0, SECRET=1, SPEND_SHOP=2, BOOT_HYDRATE=3)
#   - signal credits_changed(total: int, delta: int, source: int)
#   - get_total() avec compteur d'appels
#   - set_total() pour setup de test
#
# Pas de class_name — évite collision cache headless CI.

extends Node

# ---------------------------------------------------------------------------
# Enum (miroir CreditEconomy.SourceKind)
# ---------------------------------------------------------------------------

enum SourceKind {
	KILL         = 0,
	SECRET       = 1,
	SPEND_SHOP   = 2,
	BOOT_HYDRATE = 3,
}

# ---------------------------------------------------------------------------
# Signal
# ---------------------------------------------------------------------------

signal credits_changed(total: int, delta: int, source: int)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _total: int = 0

## Spy : nombre de fois que get_total() a été appelé. Réinitialisé manuellement par les tests.
var get_total_call_count: int = 0

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func get_total() -> int:
	get_total_call_count += 1
	return _total

## Configure le total courant du mock pour le setup de test.
func set_total(n: int) -> void:
	_total = n

## Émet credits_changed pour simuler un changement de crédit en test.
func emit_credits_changed(total: int, delta: int, source: int) -> void:
	_total = total
	credits_changed.emit(total, delta, source)
