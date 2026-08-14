class_name TopdownPlayer
extends TopdownEntity

signal gear_changed(slot: String, gear_name: String)

const SLOT_WEAPON := "weapon"
const SLOT_ARMOUR := "armour"
const SLOT_RING := "ring"
const SLOT_BOOTS := "boots"
const ALL_SLOTS: Array[String] = [SLOT_WEAPON, SLOT_ARMOUR, SLOT_RING, SLOT_BOOTS]

## 每帧输入方向（归一化后），由表现层写入
var move_input: Vector2 = Vector2.ZERO

## 朝向（单位向量），最后一次移动方向
var facing: Vector2 = Vector2.RIGHT

var attack_ability: GASGameplayAbility
var smite_ability: GAPlayerSmite
var combo_ability: GAPlayerCombo
var gear_slots: Dictionary = {}

func setup_player(p_attrs: Dictionary[StringName, float], p_attack_ability: GASGameplayAbility) -> void:
	super.setup_entity("勇者", p_attrs)
	attack_ability = p_attack_ability
	asc.give_ability(attack_ability)

func get_move_speed() -> float:
	return get_attr(TopdownAttributeSet.ATTR_MOVE_SPEED)

func equip_gear(ge: GASGameplayEffect, slot: String, gear_name: String) -> bool:
	unequip_gear(slot)
	var handle := asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge))
	if handle == GASAbilitySystemComponent.INVALID_HANDLE:
		return false
	gear_slots[slot] = {"name": gear_name, "handle": handle}
	gear_changed.emit(slot, gear_name)
	return true

func unequip_gear(slot: String) -> bool:
	if not gear_slots.has(slot):
		return false
	var entry: Dictionary = gear_slots[slot]
	if asc.remove_active_effect(entry.handle):
		gear_slots.erase(slot)
		gear_changed.emit(slot, "")
		return true
	return false

func get_gear_name(slot: String) -> String:
	if gear_slots.has(slot):
		return gear_slots[slot].name
	return ""

func get_gear_names() -> Dictionary:
	var result: Dictionary = {}
	for slot in ALL_SLOTS:
		result[slot] = get_gear_name(slot)
	return result

func try_attack() -> bool:
	if not is_alive():
		return false
	return asc.try_activate_ability(attack_ability)

func try_smite(target_actor: GASAbilityTargetActor2D) -> bool:
	if not is_alive():
		return false
	smite_ability.target_actor = target_actor
	return asc.try_activate_ability(smite_ability)

func open_combo_window() -> bool:
	if combo_ability == null or combo_ability.is_active:
		return false
	return asc.try_activate_ability(combo_ability)

func get_level() -> int:
	return int(get_attr(TopdownAttributeSet.ATTR_LEVEL))

func get_xp() -> float:
	return get_attr(TopdownAttributeSet.ATTR_XP)

func xp_to_next() -> float:
	return attr_set.xp_to_next(get_attr(TopdownAttributeSet.ATTR_LEVEL))
