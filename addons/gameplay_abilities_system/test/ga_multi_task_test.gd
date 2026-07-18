class_name GAMultiTaskTest
extends GASGameplayAbility

func activate() -> void:
	super.activate()
	commit_ability()
	var task_1: GASAbilityTaskDelay = GASAbilityTaskDelay.create(self, 0.5)
	task_1.task_finished.connect(_on_task_1_finished)
	task_1.task_canceled.connect(_on_task_1_cancled)

func _on_task_1_finished():
	GameLogger.info("GA_MultiTask", "task 1 finished, task 2 started")
	var task_2: GASAbilityTaskDelay = GASAbilityTaskDelay.create(self, 10)
	task_2.task_finished.connect(_on_task_2_finished)
	task_2.task_canceled.connect(_on_task_2_cancled)

func _on_task_1_cancled():
	GameLogger.info("GA_MultiTask", "task 1 cancled")

func _on_task_2_finished():
	GameLogger.info("GA_MultiTask", "task 2 finished")
	end_ability(false)

func _on_task_2_cancled():
	GameLogger.info("GA_MultiTask", "task 2 cancled")
