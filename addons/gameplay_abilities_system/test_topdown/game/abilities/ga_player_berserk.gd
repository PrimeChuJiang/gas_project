class_name GAPlayerBerserk
extends GASGameplayAbility

## 狂暴：3 秒内攻击力 ×2。整个持续期间能力保持激活（block 窗口），
## 挂 Ability.Berserk tag 的 GE 到期/被移除 → tag 消失 → 能力结束。
## 互斥矩阵（第三梯队）：激活时打断前摇中的落雷（cancel_abilities_with_tags），
## 激活期间阻塞落雷激活（block_abilities_with_tags）。
var game: TopdownGame = null
var _connected: bool = false

func activate() -> void:
	super.activate()
	if not game or not game.player.is_alive():
		end_ability(true)
		return
	if not commit_ability():
		end_ability(true)
		return
	if game.berserk_ge == null:
		end_ability(true)
		return
	game.player.asc.gameplay_tag_changed.connect(_on_tag_changed)
	_connected = true
	game.player.asc.apply_gameplay_effect_spec_to_self(game.player.asc.make_effect_spec(game.berserk_ge))

func _on_tag_changed(tag: FGameplayTag, added: bool) -> void:
	if added:
		return
	if tag.get_tag_name() == &"Ability.Berserk":
		end_ability(false)

func end_ability(was_cancelled: bool) -> void:
	if _connected:
		game.player.asc.gameplay_tag_changed.disconnect(_on_tag_changed)
		_connected = false
	super.end_ability(was_cancelled)
