class_name GASLevelRequirement
extends GASCustomApplicationRequirement

## 施加条件：目标等级 >= min_level（读属性——tag 检查做不到的典型）
@export var min_level: int = 1

func can_apply(spec: GASEffectSpec) -> bool:
	var target_asc := spec.target_asc
	if target_asc == null:
		return false
	var attr_set := target_asc.find_attribute_set(&"Level")
	if attr_set == null:
		return false
	return attr_set.get_attribute_value(&"Level") >= float(min_level)
