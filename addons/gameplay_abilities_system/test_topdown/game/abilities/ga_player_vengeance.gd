class_name GAPlayerVengeance
extends GASGameplayAbility

## 复仇：被 GameplayEvent.Hurt 事件自动激活（activation_event_tags 声明响应），
## 激活时读 last_event_data（伤害小票，快照离手即定），挂 3s 攻击 ×1.2 buff 后结束。
## 5s 冷却（cooldown_ge）防事件连触发。
var game: TopdownGame = null

func activate() -> void:
	super.activate()
	if not game or not game.player.is_alive():
		end_ability(true)
		return
	if not commit_ability():
		end_ability(true)
		return
	if game.vengeance_ge != null:
		game.player.asc.apply_gameplay_effect_spec_to_self(game.player.asc.make_effect_spec(game.vengeance_ge))
	end_ability(false)
