class_name GAPoisonCloud
extends GASGameplayAbility

var target: DungeonEntity = null
var dot_ge: GASGameplayEffect

func activate() -> void:
	super.activate()
	if not target or not target.is_alive() or not dot_ge:
		end_ability(true)
		return
	if not commit_ability():
		end_ability(true)
		return
	target.asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(dot_ge))
	end_ability(false)
