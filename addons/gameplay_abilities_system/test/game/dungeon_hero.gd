class_name DungeonHero
extends DungeonEntity

signal gear_changed(slot: String, gear_name: String)
signal ability_result(ability_name: String, success: bool)

const GEAR_SLOT_WEAPON := "weapon"
const GEAR_SLOT_SHIELD := "shield"
const GEAR_SLOT_BOOTS := "boots"
const GEAR_SLOT_RING := "ring"
const GEAR_SLOT_BELT := "belt"
const GEAR_SLOT_CRYSTAL := "crystal"

var gear_slots: Dictionary = {}
var abilities: Array[GASGameplayAbility] = []

var melee_strike: GASGameplayAbility
var spells: Dictionary = {}

func setup_hero(p_name: String, p_attrs: Dictionary, p_abilities: Array[GASGameplayAbility]) -> void:
	super.setup(p_name, p_attrs)
	abilities = p_abilities
	var melee_tag := GameplayTags.request_gameplay_tag(&"Ability.Melee")
	for ability in abilities:
		asc.give_ability(ability)
		if ability.ability_tags.has_matching_tag(melee_tag):
			melee_strike = ability
		elif ability.ability_tags.has_matching_tag(GameplayTags.request_gameplay_tag(&"Ability.Spell")):
			spells[ability.ability_tags._tags.keys()[0].get_tag_name()] = ability

func try_melee_attack(target: DungeonEntity) -> bool:
	if not target or not target.is_alive():
		return false
	melee_strike.target = target
	return _try_activate(melee_strike, "近战攻击")

func try_cast_spell(spell: GASGameplayAbility, target: DungeonEntity = null) -> bool:
	if not spell:
		return false
	if "target" in spell:
		spell.target = target
	return _try_activate(spell, spell.ability_tags._tags.keys()[0].get_tag_name())

func _try_activate(ability: GASGameplayAbility, label: String) -> bool:
	var success := asc.try_activate_ability(ability)
	ability_result.emit(label, success)
	if not success:
		GameLogger.warn("DungeonHero", "%s 激活失败（冷却/消耗/眩晕门禁）" % label)
	return success

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

func use_potion(ge: GASGameplayEffect, potion_name: String) -> bool:
	if not ge:
		return false
	var handle := asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge))
	if ge.duration_policy == GASEnums.DurationPolicy.INSTANT:
		ability_result.emit(potion_name, true)
		return true
	if handle == GASAbilitySystemComponent.INVALID_HANDLE:
		return false
	ability_result.emit(potion_name, true)
	return true

func get_move_attr() -> int:
	return int(get_attr(&"Move"))
