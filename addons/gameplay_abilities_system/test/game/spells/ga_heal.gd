class_name GAHealSpell
extends GASGameplayAbility

var heal_ge: GASGameplayEffect

func activate() -> void:
	super.activate()
	if not heal_ge:
		end_ability(true)
		return
	if not commit_ability():
		end_ability(true)
		return
	asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(heal_ge))
	end_ability(false)
