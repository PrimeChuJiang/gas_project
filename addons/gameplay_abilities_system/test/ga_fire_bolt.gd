class_name GAFireBoltAbility
extends GASGameplayAbility

@export var damage_ge: GASGameplayEffect = GASGameplayEffect.new()

var _damage_spec: GASEffectSpec = null

func activate() -> void:
	super.activate()
	
	_damage_spec = asc.make_effect_spec(damage_ge)
	
	if not _damage_spec :
		end_ability(true)
		return
	
	_damage_spec.set_setbycaller_magnitude(&"charge_time", 1.7)
	var task: GASAbilityTaskDelay = GASAbilityTaskDelay.create(self, 1.5)
	task.task_finished.connect(_on_charge_down)

func _on_charge_down():
	if not commit_ability():
		end_ability(true)
		return
	asc.apply_gameplay_effect_spec_to_self(_damage_spec)
	end_ability(false)

func _make_cooldown_spec(ge: GASGameplayEffect) -> GASEffectSpec:
	var attr_set: GASAttributeSet = asc.find_attribute_set(&"CooldownReduction")
	var spec = asc.make_effect_spec(ge)
	if attr_set:
		spec.duration = spec.duration*clamp((1 - attr_set.get_attribute_value(&"CooldownReduction")), 0.5, 2.0)
	return spec
