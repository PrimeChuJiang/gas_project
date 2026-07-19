class_name TestAttributeSet
extends GASAttributeSet

func pre_attribute_change(attr_name: StringName, new_value: float) -> float:
	match attr_name:
		&"Health":
			return clamp(new_value, 0.0, _attributes[&"MaxHealth"].base_value)
		&"Attack":
			return max(new_value, 0.0)
		&"Mana":
			return clamp(new_value, 0.0, _attributes[&"MaxMana"].base_value)
	return new_value
