class_name GASModifierMagnitudeSetByCallerTimesAttribute
extends GASModifierMagnitude

@export var attr_name: StringName # 属性名
@export var data_key: StringName # 调用方设置的名称
@export var default_value: float = 0.0 # 默认值
@export var coefficient: float = 1.0 # 属性乘以的系数

func is_snapshot() -> bool:
	return false # 返回false，防止出现先get_setbycaller后set_setbycaller的事情

# 公式： data_value x (attr_value x coefficient)
func _calculate(spec: GASEffectSpec) -> float:
	var data_value = spec.get_setbycaller_magnitude(data_key, default_value)
	if not spec.source_asc:
		GameLogger.error("ModifierMagnitudeSetByCallerTimesAttribute", "source_asc is not exist in spec !")
		return 0.0
	if attr_name.is_empty():
		GameLogger.error("ModifierMagnitudeSetByCallerTimesAttribute", "attr_name is empty!")
		return 0.0
	var attr_set = spec.source_asc.find_attribute_set(attr_name)
	if not attr_set:
		GameLogger.error("ModifierMagnitudeSetByCallerTimesAttribute", "there is no attr_set called %s" % attr_name)
		return 0.0
	var attr_value = attr_set.get_attribute_value(attr_name)
	return data_value * (attr_value * coefficient)
