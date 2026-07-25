class_name GASExecutionCalculation
extends Resource

func _execute(spec: GASEffectSpec) -> Array[GASModifierEvaluatedData]:
	GameLogger.error("ExecutionCalculation", "Must Override!")
	return []
