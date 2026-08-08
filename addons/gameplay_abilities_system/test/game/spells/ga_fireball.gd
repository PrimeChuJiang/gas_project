class_name GAFireballSpell
extends GASGameplayAbility

var target: DungeonEntity = null
var damage_ge: GASGameplayEffect

func activate() -> void:
	super.activate()
	if not target or not target.is_alive() or not damage_ge:
		end_ability(true)
		return
	var task: GASAbilityTaskDelay = GASAbilityTaskDelay.create(self, 0.6)
	task.task_finished.connect(_on_charged)

func _on_charged() -> void:
	if not commit_ability():
		end_ability(true)
		return
	var attr_set: GASAttributeSet = asc.find_attribute_set(&"Level")
	var level := attr_set.get_attribute_value(&"Level") if attr_set else 0.0
	var damage := 30.0 + level * 10.0
	var spec: GASEffectSpec = asc.make_effect_spec(damage_ge)
	spec.set_setbycaller_magnitude(&"damage", -damage)
	target.asc.apply_gameplay_effect_spec_to_self(spec)
	end_ability(false)
