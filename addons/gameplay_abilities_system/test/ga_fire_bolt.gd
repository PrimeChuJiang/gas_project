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
