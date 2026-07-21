class_name GAFireBoltAbility
extends GASGameplayAbility

@export var damage_ge: GASGameplayEffect = GASGameplayEffect.new()

var _snapshot_spec: GASEffectSpec = null

func activate() -> void:
	super.activate()
	
	_snapshot_spec = _make_damage_spec(damage_ge)
	if not _snapshot_spec :
		end_ability(true)
		return
	
	var task: GASAbilityTaskDelay = GASAbilityTaskDelay.create(self, 1.5)
	task.task_finished.connect(_on_charge_down)

func _on_charge_down():
	if not commit_ability():
		end_ability(true)
		return
	asc.apply_gameplay_effect_spec_to_self(_snapshot_spec)
	end_ability(false)

func _make_cooldown_spec(ge: GASGameplayEffect) -> GASEffectSpec:
	var attr_set: GASAttributeSet = asc.find_attribute_set(&"CooldownReduction")
	var spec = asc.make_effect_spec(ge)
	if attr_set:
		spec.duration = spec.duration*clamp((1 - attr_set.get_attribute_value(&"CooldownReduction")), 0.5, 2.0)
	return spec

func _make_damage_spec(ge: GASGameplayEffect) -> GASEffectSpec:
	if not ge :
		GameLogger.error("GAFireBolt", "ge is null")
		return null
	var attr_set: GASAttributeSet = asc.find_attribute_set(&"Attack")
	if not attr_set:
		GameLogger.error("GAFireBolt", "can't get attribute Attack!")
		return null
	var spec = asc.make_effect_spec(ge)
	var damage_plus: float = -(attr_set.get_attribute_value(&"Attack") * 0.3)
	var damage_basic: float = 0
	for ge_mod in spec.modifiers:
		if ge_mod.attr_name == &"Health":
			damage_basic = ge_mod.magnitude
			ge_mod.magnitude = damage_basic + damage_plus
	return spec
