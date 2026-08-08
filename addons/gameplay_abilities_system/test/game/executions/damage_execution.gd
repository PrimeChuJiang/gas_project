class_name DungeonDamageExecution
extends GASExecutionCalculation

func _execute(spec: GASEffectSpec) -> Array[GASModifierEvaluatedData]:
	var source_asc: GASAbilitySystemComponent = spec.source_asc
	var target_asc: GASAbilitySystemComponent = spec.target_asc
	if not source_asc or not target_asc:
		return []
	var source_set: GASAttributeSet = source_asc.find_attribute_set(&"Attack")
	var target_set: GASAttributeSet = target_asc.find_attribute_set(&"Defense")
	if not source_set or not target_set:
		return []
	var damage := maxf(1.0, source_set.get_attribute_value(&"Attack") - target_set.get_attribute_value(&"Defense"))
	var data := GASModifierEvaluatedData.new()
	data.attr_name = &"Body"
	data.op = GASEnums.ModifierOp.ADD
	data.value = -damage
	return [data]
