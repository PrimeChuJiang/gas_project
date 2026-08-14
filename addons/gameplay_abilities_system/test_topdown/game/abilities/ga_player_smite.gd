class_name GAPlayerSmite
extends GASGameplayAbility

## 落雷：右键进入瞄准（AOE 圈预览由表现层驱动 TargetActor），左键确认落雷
var game: TopdownGame = null
var target_actor: GASAbilityTargetActor2D = null
var wait_task: GASAbilityTaskWaitTargetData = null

func activate() -> void:
	super.activate()
	if not game or not target_actor or not game.player.is_alive():
		end_ability(true)
		return
	if not commit_ability():
		end_ability(true)
		return
	wait_task = GASAbilityTaskWaitTargetData.create(self, target_actor)
	wait_task.task_finished.connect(_on_wait_finished)
	wait_task.task_canceled.connect(_on_wait_canceled)

func _on_wait_finished() -> void:
	var data := wait_task.get_target_data()
	var targets: Array[TopdownEntity] = []
	if data != null:
		for actor in data.get_actors():
			var entity := actor as TopdownEntity
			if entity != null:
				targets.append(entity)
	var center := Vector2.ZERO
	for target in targets:
		center += target.pos
	if not targets.is_empty():
		center /= float(targets.size())
	game.do_smite(targets, center)
	end_ability(false)

func _on_wait_canceled() -> void:
	end_ability(true)
