class_name GASModifierSpec
extends RefCounted

var attr_name: StringName
var op: GASEnums.ModifierOp
var magnitude_def: GASModifierMagnitude
var resolved: bool = false
var value: float = 0.0

# 注意：不保存 effect_spec 回引——GASEffectSpec.modifiers → GASModifierSpec → spec
# 会形成 RefCounted 循环引用导致内存泄漏。重算需要 spec 时由依赖登记簿直接持有。

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
