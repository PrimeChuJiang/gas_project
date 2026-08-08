class_name GAShieldSpell
extends GASGameplayAbility

var shield_ge: GASGameplayEffect

func activate() -> void:
	super.activate()
	if not shield_ge:
		end_ability(true)
		return
	if not commit_ability():
		end_ability(true)
		return
	asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(shield_ge))
	end_ability(false)
