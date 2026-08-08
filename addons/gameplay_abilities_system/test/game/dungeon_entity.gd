class_name DungeonEntity
extends Node

signal died(entity: DungeonEntity)

var asc: GASAbilitySystemComponent
var attr_set: DungeonAttributeSet
var display_name: String = ""
var board_index: int = -1

func setup(p_name: String, p_attrs: Dictionary) -> void:
	display_name = p_name
	asc = GASAbilitySystemComponent.new()
	asc.name = "ASC_" + p_name
	add_child(asc)
	asc.init_ability_actor_info(self, self)
	attr_set = DungeonAttributeSet.new()
	var typed_attrs: Dictionary[StringName, float] = {}
	for key in p_attrs:
		typed_attrs[key] = float(p_attrs[key])
	attr_set.initial_attributes = typed_attrs
	attr_set.initialize_attributes(asc)
	asc.add_attribute_set(attr_set)
	attr_set.attribute_changed.connect(_on_attr_changed)

func get_attr(attr_name: StringName) -> float:
	return attr_set.get_attribute_value(attr_name)

func is_alive() -> bool:
	return get_attr(&"Body") > 0.0

func is_stunned() -> bool:
	return asc.has_tag(GameplayTags.request_gameplay_tag(&"State.Debuff.Stun"))

func _on_attr_changed(attr_name: StringName, new_value: float, old_value: float) -> void:
	if attr_name == &"Body" and new_value <= 0.0 and old_value > 0.0:
		died.emit(self)
