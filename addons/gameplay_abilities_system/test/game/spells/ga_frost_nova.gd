class_name GAFrostNova
extends GASGameplayAbility

var target: DungeonEntity = null
var nova_ge: GASGameplayEffect

func activate() -> void:
	super.activate()
	if not target or not target.is_alive() or not nova_ge:
		end_ability(true)
		return
	if not commit_ability():
		end_ability(true)
		return
	target.asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(nova_ge))
	end_ability(false)
