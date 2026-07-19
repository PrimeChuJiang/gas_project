class_name GAFireBoltAbility
extends GASGameplayAbility

@export var damage_ge: GASGameplayEffect = GASGameplayEffect.new()

func activate() -> void:
	super.activate()
	var task: GASAbilityTaskDelay = GASAbilityTaskDelay.create(self, 1.5)
	task.task_finished.connect(_on_charge_down)

func _on_charge_down():
	if not commit_ability():
		end_ability(true)
		return
	if damage_ge:
		asc.apply_gameplay_effect_spec_to_self(GASEffectSpec.new(damage_ge))
	end_ability(false)

func _make_cooldown_spec(ge: GASGameplayEffect) -> GASEffectSpec:
	var attr_set: GASAttributeSet = asc.find_attribute_set(&"CooldownReduction")
	var spec = GASEffectSpec.new(ge)
	if attr_set:
		spec.duration = spec.duration*clamp((1 - attr_set.get_attribute_value(&"CooldownReduction")), 0.5, 2.0)
	return spec
