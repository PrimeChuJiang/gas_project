class_name GAWaitTargetTest
extends GASGameplayAbility

var target_actor: GASAbilityTargetActor
var wait_task: GASAbilityTaskWaitTargetData = null
var last_target_data: GASAbilityTargetData = null
var task_finished_flag := false
var task_canceled_flag := false

func activate() -> void:
	super.activate()
	wait_task = GASAbilityTaskWaitTargetData.create(self, target_actor)
	wait_task.task_finished.connect(_on_wait_finished)
	wait_task.task_canceled.connect(_on_wait_canceled)

func _on_wait_finished() -> void:
	task_finished_flag = true
	last_target_data = wait_task.get_target_data()
	end_ability(false)

func _on_wait_canceled() -> void:
	task_canceled_flag = true
	end_ability(true)
