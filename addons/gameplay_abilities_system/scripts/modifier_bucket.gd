class_name GASModifierBucket
extends RefCounted

class ModifierPileArray:
	var list: Array[GASModifierPile] = []

var items: Dictionary[StringName, ModifierPileArray] = {}  

func append(attr_name: StringName, op: GASEnums.ModifierOp, magnitude: float) -> void:
	var pile := GASModifierPile.new(op, magnitude)
	if not items.has(attr_name):
		items[attr_name] = ModifierPileArray.new()
	items[attr_name].list.append(pile)

func get_pile(attr_name: StringName) -> Array[GASModifierPile]:
	return items[attr_name].list
