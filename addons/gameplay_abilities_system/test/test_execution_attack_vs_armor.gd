class_name TestExecutionAttackVsArmor
extends GASExecutionCalculation

func _execute(spec: GASEffectSpec) -> Array[GASModifierEvaluatedData]:
	var source_asc = spec.source_asc
	var target_asc = spec.target_asc
	if not source_asc:
		GameLogger.error("TestExecutionAttackVsArmor", "source_asc is null!")
		return []
	if not target_asc:
		GameLogger.error("TestExecutionAttackVsArmor", "target_asc is null!")
		return []
	
	var attack_attr_set = source_asc.find_attribute_set(&"Attack")
	var armor_attr_set = target_asc.find_attribute_set(&"Armor")
	if not attack_attr_set:
		GameLogger.error("TestExecutionAttackVsArmor", "source_asc Attack is null!")
		return []
	if not armor_attr_set:
		GameLogger.error("TestExecutionAttackVsArmor", "target_asc Armor is null!")
		return []
	
	var attack = attack_attr_set.get_attribute_value(&"Attack")
	var armor = armor_attr_set.get_attribute_value(&"Armor")
	
	var evaluate_data: GASModifierEvaluatedData = GASModifierEvaluatedData.new()
	evaluate_data.attr_name = &"Health"
	evaluate_data.value = armor - attack
	if evaluate_data.value >= 0:
		return []
	
	return [evaluate_data]
