class_name GASAbilityTaskWaitTargetData
extends GASAbilityTask

var _target_actor: GASAbilityTargetActor
var _target_data: GASAbilityTargetData = null

static func create(ability: GASGameplayAbility, target_actor: GASAbilityTargetActor) -> GASAbilityTaskWaitTargetData:
	var task_wait_target_data := GASAbilityTaskWaitTargetData.new()
	task_wait_target_data._target_actor = target_actor
	task_wait_target_data._spawn(ability)
	return task_wait_target_data

func activate():
	super.activate()
	_target_actor.start_targeting()

func confirm_selection() -> bool:
	var target_data = _target_actor.confirm_target()
	if target_data == null:
		return false
	_target_data = target_data
	end_task(false)
	return true

func cancel_selection() -> void:
	_target_actor.cancel_target()
	end_task(true)

func get_target_data() -> GASAbilityTargetData:
	return _target_data

func end_task(canceled: bool):
	if canceled:
		_target_actor.cancel_target()
	super.end_task(canceled)
