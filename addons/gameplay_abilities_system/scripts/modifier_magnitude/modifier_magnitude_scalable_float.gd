class_name GASModifierMagnitudeScalableFloat
extends GASModifierMagnitude

@export var value: float = 0.0

func _calculate(spec: GASEffectSpec) -> float:
	return value

func is_snapshot() -> bool:
	return true
