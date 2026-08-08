class_name GASModifierMagnitudeScalableFloat
extends GASModifierMagnitude

@export var value: float = 0.0

@export var level_curve: Curve = null

func _calculate(spec: GASEffectSpec) -> float:
	if level_curve:
		return level_curve.sample(spec.level)
	return value

func is_snapshot() -> bool:
	return true
