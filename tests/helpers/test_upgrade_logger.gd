# Test fixture — UpgradeLogger qui capture les messages au lieu de push_warning.
# Story-002 AC-UPG-10/11 : permet d'asserter contenu warning depuis GdUnit4
# sans hook engine-level sur push_warning.
class_name TestUpgradeLogger
extends UpgradeLogger

var captured_warnings: Array[String] = []


func warn(msg: String) -> void:
	captured_warnings.append(msg)
