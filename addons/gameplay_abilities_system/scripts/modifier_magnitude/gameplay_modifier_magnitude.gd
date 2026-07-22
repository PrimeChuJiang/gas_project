class_name GASModifierMagnitude
extends Resource

func _calculate(spec: GASEffectSpec) -> float:
	GameLogger.error("ModifierMagnitude", "Must Override!")
	return 0.0

func is_snapshot() -> bool:
	GameLogger.error("ModifierMagnitude", "Must Override!")
	return true
