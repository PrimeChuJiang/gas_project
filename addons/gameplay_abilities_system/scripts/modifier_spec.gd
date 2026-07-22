class_name GASModifierSpec
extends RefCounted

var attr_name: StringName
var op: GASEnums.ModifierOp
var magnitude_def: GASModifierMagnitude
var resolved: bool = false
var value: float = 0.0

func _init(mod: GEModifier, spec: GASEffectSpec):
	attr_name = mod.attr_name
	op = mod.op
	magnitude_def = mod.magnitude
	if mod.magnitude.is_snapshot():
		resolve(spec)

func resolve(spec: GASEffectSpec):
	value = magnitude_def._calculate(spec)
	resolved = true

func get_magnitude() -> float:
	if resolved: 
		return value
	else:
		GameLogger.error("ModifierSpec", "try to get value before resolve()")
		return 0.0
