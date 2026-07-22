class_name GASModifierMagnitudeAttributeBased
extends GASModifierMagnitude

@export var attr_name: StringName # 读哪个属性
@export var coefficient: float # 系数
@export var pre_add: float # 公式：(coefficient * (属性值 + pre_add)) + post_add
@export var post_add: float
@export var snapshot: bool = true # 是否是快照
@export var from_target: bool  # false=读source, true=读target(护甲折算用)

func _calculate(spec: GASEffectSpec) -> float:
	if attr_name.is_empty():
		GameLogger.error("ModifierMagnitudeAttributeBased", "no attr_name")
		return 0.0
	var asc: GASAbilitySystemComponent = null
	var attr_set: GASAttributeSet = null
	if from_target:
		asc = spec.target_asc
	else:
		asc = spec.source_asc
	if not asc:
		if from_target:
			GameLogger.error("ModifierMagnitudeAttributeBased", "target_asc is null")
			return 0.0
		else:
			GameLogger.error("ModifierMagnitudeAttributeBased", "source_asc is null")
			return 0.0
	attr_set = asc.find_attribute_set(attr_name)
	if not attr_set:
		GameLogger.error("ModifierMagnitudeAttributeBased", "attr_set %s is null" % attr_name)
		return 0.0
	var base_value = attr_set.get_attribute_value(attr_name)
	return (coefficient * (base_value + pre_add)) + post_add

func is_snapshot() -> bool:
	return snapshot and not from_target
