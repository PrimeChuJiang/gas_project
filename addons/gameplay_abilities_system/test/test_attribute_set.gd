class_name TestAttributeSet
extends GASAttributeSet

var _initialized: bool = false

var attribute_map: Dictionary[StringName, StringName] = {
	&"MaxHealth" : &"Health",
	&"MaxMana" : &"Mana"
}

func pre_attribute_change(attr_name: StringName, new_value: float) -> float:
	match attr_name:
		&"Health":
			return clamp(new_value, 0.0, _attributes[&"MaxHealth"].current_value)
		&"Attack":
			return max(new_value, 0.0)
		&"Mana":
			return clamp(new_value, 0.0, _attributes[&"MaxMana"].current_value)
	return new_value

func initialize_attributes(owner_asc: GASAbilitySystemComponent):
	if not _initialized:
		super.initialize_attributes(owner_asc)
		# 连接signal放在initialize_attribute之后，防止我们在初始化的时候触发signal
		_connect_signal()
		_initialized = true
	else:
		GameLogger.error("TestAttributeSet", "Attribute already initialized")

func _connect_signal():
	attribute_changed.connect(_on_attribute_changed)

func _on_attribute_changed(attr_name: StringName, new_value: float, old_value: float) -> void:
	match attr_name:
		&"MaxHealth", &"MaxMana":
			_shrink_to_max(attr_name, new_value)

func _shrink_to_max(attr_name: StringName, new_value: float):
	if attribute_map.has(attr_name):
		var mapped_attr_name = attribute_map[attr_name]
		if new_value < _attributes[mapped_attr_name].current_value:
			apply_base_value_change(mapped_attr_name, new_value - get_attribute_value(mapped_attr_name))
	else:
		GameLogger.error("TestAttributeSet", "AttributeMap don't have the attr_name!")
