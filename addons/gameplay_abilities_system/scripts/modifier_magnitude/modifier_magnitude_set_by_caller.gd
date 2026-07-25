class_name GASModifierMagnitudeSetByCaller
extends GASModifierMagnitude

@export var data_key: StringName
@export var default_value: float

func is_snapshot() -> bool:
	return false

func _calculate(spec: GASEffectSpec) -> float:
	return spec.get_setbycaller_magnitude(data_key, default_value)
