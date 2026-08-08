class_name DungeonAttributeSet
extends GASAttributeSet

var _initialized: bool = false

func pre_attribute_change(attr_name: StringName, new_value: float) -> float:
	match attr_name:
		&"Body":
			return clampf(new_value, 0.0, get_attribute_value(&"MaxBody"))
		&"Mind":
			return clampf(new_value, 0.0, get_attribute_value(&"MaxMind"))
		&"Attack", &"Defense", &"Move":
			return maxf(new_value, 0.0)
	return new_value

func initialize_attributes(owner_asc: GASAbilitySystemComponent):
	if _initialized:
		GameLogger.error("DungeonAttributeSet", "already initialized")
		return
	super.initialize_attributes(owner_asc)
	attribute_changed.connect(_on_attribute_changed)
	_initialized = true

func _on_attribute_changed(attr_name: StringName, new_value: float, old_value: float) -> void:
	match attr_name:
		&"MaxBody":
			_shrink_to_max(&"Body")
		&"MaxMind":
			_shrink_to_max(&"Mind")

func _shrink_to_max(cur_attr: StringName) -> void:
	var cur := get_attribute_value(cur_attr)
	var mx := get_attribute_value(&"MaxBody" if cur_attr == &"Body" else &"MaxMind")
	if cur > mx:
		apply_base_value_change(cur_attr, mx - cur)
