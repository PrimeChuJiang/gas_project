class_name TopdownEntity
extends Node

signal died(entity: TopdownEntity)
signal health_changed(current: float, max_value: float)

var asc: GASAbilitySystemComponent
var attr_set: TopdownAttributeSet
var display_name: String = ""

## 世界坐标（像素），逻辑层唯一权威；表现层每帧同步
var pos: Vector2 = Vector2.ZERO

## 实体半径（像素），用于碰撞与近战判定
const RADIUS: float = 18.0

func setup_entity(p_name: String, p_attrs: Dictionary[StringName, float]) -> void:
	display_name = p_name
	asc = GASAbilitySystemComponent.new()
	asc.name = "ASC_" + p_name
	add_child(asc)
	asc.init_ability_actor_info(self, self)
	attr_set = TopdownAttributeSet.new()
	attr_set.initial_attributes = p_attrs
	attr_set.initialize_attributes(asc)
	asc.add_attribute_set(attr_set)
	attr_set.attribute_changed.connect(_on_attr_changed)

func get_attr(attr_name: StringName) -> float:
	return attr_set.get_attribute_value(attr_name)

func is_alive() -> bool:
	return get_attr(TopdownAttributeSet.ATTR_HEALTH) > 0.0

func distance_to_entity(other: TopdownEntity) -> float:
	return pos.distance_to(other.pos)

func _on_attr_changed(attr_name: StringName, new_value: float, old_value: float) -> void:
	if attr_name == TopdownAttributeSet.ATTR_HEALTH:
		health_changed.emit(new_value, get_attr(TopdownAttributeSet.ATTR_MAX_HEALTH))
		if new_value <= 0.0 and old_value > 0.0:
			died.emit(self)
