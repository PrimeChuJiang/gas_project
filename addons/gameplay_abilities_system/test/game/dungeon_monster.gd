class_name DungeonMonster
extends DungeonEntity

enum MonsterKind { CHARGER, VENOM, STUNNER }

var kind: MonsterKind = MonsterKind.CHARGER
var attack_ge: GASGameplayEffect
var secondary_ge: GASGameplayEffect = null

func setup_monster(p_name: String, p_attrs: Dictionary, p_kind: MonsterKind, p_attack_ge: GASGameplayEffect, p_secondary_ge: GASGameplayEffect = null) -> void:
	kind = p_kind
	attack_ge = p_attack_ge
	secondary_ge = p_secondary_ge
	super.setup(p_name, p_attrs)

func get_move_attr() -> int:
	return int(get_attr(&"Move"))
