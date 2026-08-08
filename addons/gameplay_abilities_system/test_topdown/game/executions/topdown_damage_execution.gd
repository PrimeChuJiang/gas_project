class_name TopdownDamageExecution
extends GASExecutionCalculation

## 伤害公式：max(1, source.Attack × coeff − target.Defense)
## coeff 由攻击能力按形态注入（SetByCaller），公式本体唯一住在这里
func _execute(spec: GASEffectSpec) -> Array[GASModifierEvaluatedData]:
	var source_asc: GASAbilitySystemComponent = spec.source_asc
	var target_asc: GASAbilitySystemComponent = spec.target_asc
	if not source_asc or not target_asc:
		return []
	var source_set := source_asc.find_attribute_set(&"Attack")
	var target_set := target_asc.find_attribute_set(&"Defense")
	if not source_set or not target_set:
		return []
	var coeff := spec.get_setbycaller_magnitude(&"coeff", 1.0)
	var attack := source_set.get_attribute_value(&"Attack")
	var defense := target_set.get_attribute_value(&"Defense")
	var damage := maxf(1.0, attack * coeff - defense)
	var data := GASModifierEvaluatedData.new()
	data.attr_name = &"Health"
	data.op = GASEnums.ModifierOp.ADD
	data.value = -damage
	return [data]
