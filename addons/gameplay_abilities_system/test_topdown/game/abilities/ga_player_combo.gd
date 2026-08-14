class_name GAPlayerCombo
extends GASGameplayAbility

## 连击：普通攻击后开窗（WaitInput 等攻击键 0.6s），按到 → 强化斩击
var game: TopdownGame = null
var wait_task: GASAbilityTaskWaitInput = null

func activate() -> void:
	super.activate()
	if not game or not game.player.is_alive():
		end_ability(true)
		return
	if not commit_ability():
		end_ability(true)
		return
	wait_task = GASAbilityTaskWaitInput.create(self, &"attack", TopdownGame.COMBO_WINDOW)
	wait_task.task_finished.connect(_on_input_received)
	wait_task.task_canceled.connect(_on_window_closed)

func _on_input_received() -> void:
	game.do_combo_strike()
	end_ability(false)

func _on_window_closed() -> void:
	end_ability(true)
