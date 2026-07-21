class_name TestAttributeSet
extends GASAttributeSet

var _initialized: bool = false

const attribute_map: Dictionary[StringName, StringName] = {
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
		for key in attribute_map.keys():
			var value = attribute_map[key]
			if not _attributes.has(key):
				GameLogger.error("TestAttributeSet", "attribute key: " + key + " not in _attributes")
			if not _attributes.has(value):
				GameLogger.error("TestAttributeSet", "attribute value: " + value + " not in _attributes")
		# 连接signal放在initialize_attribute之后，防止我们在初始化的时候触发signal
		_connect_signal()
		_initialized = true
	else:
		GameLogger.error("TestAttributeSet", "Attribute already initialized")

func _connect_signal():
	attribute_changed.connect(_on_attribute_changed)

func _on_attribute_changed(attr_name: StringName, new_value: float, old_value: float) -> void:
	if attribute_map.has(attr_name):
		_shrink_to_max(attr_name, new_value)

func _shrink_to_max(attr_name: StringName, new_value: float):
	var mapped_attr_name = attribute_map[attr_name]
	if new_value < get_attribute_value(mapped_attr_name):
		apply_base_value_change(mapped_attr_name, new_value - get_attribute_value(mapped_attr_name))
	
