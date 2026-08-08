class_name GAMeleeStrike
extends GASGameplayAbility

var target: DungeonEntity = null
var attack_ge: GASGameplayEffect

func activate() -> void:
	super.activate()
	if not target or not target.is_alive() or not attack_ge:
		end_ability(true)
		return
	if not commit_ability():
		end_ability(true)
		return
	var spec: GASEffectSpec = asc.make_effect_spec(attack_ge)
	target.asc.apply_gameplay_effect_spec_to_self(spec)
	end_ability(false)
