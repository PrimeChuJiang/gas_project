class_name GAPlayerCounter
extends GASGameplayAbility

## 反击：T 键激活 → 3s 反击姿态（WaitGameplayEvent 等 GameplayEvent.Hurt）→
## 受击 → 对攻击者造成 1.5× 反击伤害；超时落空。
var game: TopdownGame = null
var wait_task: GASAbilityTaskWaitGameplayEvent = null

func activate() -> void:
	super.activate()
	if not game or not game.player.is_alive():
		end_ability(true)
		return
	if not commit_ability():
		end_ability(true)
		return
	var hurt_tag := GameplayTags.request_gameplay_tag(&"GameplayEvent.Hurt")
	wait_task = GASAbilityTaskWaitGameplayEvent.create(self, hurt_tag, 3.0)
	wait_task.task_finished.connect(_on_event_received)
	wait_task.task_canceled.connect(_on_timeout)

func _on_event_received() -> void:
	var event_data := wait_task.get_event_data()
	if event_data != null and event_data.instigator is TopdownEntity:
		game.do_counter_attack(event_data.instigator)
	end_ability(false)

func _on_timeout() -> void:
	end_ability(true)
