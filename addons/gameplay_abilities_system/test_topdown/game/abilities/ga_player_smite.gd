class_name GAPlayerSmite
extends GASGameplayAbility

## 落雷：右键进入瞄准（AOE 圈预览由表现层驱动 TargetActor），左键确认后进入
## 前摇（法阵 0.4s，表现层动画命中帧发通知），WaitAnimNotify 等到通知才结算。
## 前摇中被打断 = 无伤害（施法可被取消）。
var game: TopdownGame = null
var target_actor: GASAbilityTargetActor2D = null
var wait_task: GASAbilityTaskWaitTargetData = null
var notify_task: GASAbilityTaskWaitAnimNotify = null

var _strike_targets: Array[TopdownEntity] = []
var _strike_center: Vector2 = Vector2.ZERO

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
	_strike_targets.clear()
	if data != null:
		for actor in data.get_actors():
			var entity := actor as TopdownEntity
			if entity != null:
				_strike_targets.append(entity)
	var center := Vector2.ZERO
	for target in _strike_targets:
		center += target.pos
	if not _strike_targets.is_empty():
		center /= float(_strike_targets.size())
	_strike_center = center
	if _strike_targets.is_empty():
		end_ability(true)
		return
	game.start_smite_casting()
	notify_task = GASAbilityTaskWaitAnimNotify.create(self, game, &"anim_notify", &"smite_strike")
	notify_task.task_finished.connect(_on_strike)
	notify_task.task_canceled.connect(_on_strike_canceled)

func _on_strike() -> void:
	game.do_smite(_strike_targets, _strike_center)
	end_ability(false)

func _on_strike_canceled() -> void:
	end_ability(true)

func _on_wait_canceled() -> void:
	end_ability(true)
