class_name GAPlayerAttack
extends GASGameplayAbility

## 唯一攻击能力：等级决定形态（数据表驱动，不写分支海）
var game: TopdownGame = null
var attack_ge: GASGameplayEffect = null

func activate() -> void:
	super.activate()
	if not game or not attack_ge or not game.player.is_alive():
		end_ability(true)
		return
	if not commit_ability():
		end_ability(true)
		return
	var form := game.get_current_attack_form()
	match form.kind:
		TopdownAttackForm.Kind.MELEE_ARC:
			game.do_entity_melee_attack(game.player, form)
		TopdownAttackForm.Kind.PROJECTILE, TopdownAttackForm.Kind.PIERCE_BLAST:
			game.spawn_projectiles(form, 1)
		TopdownAttackForm.Kind.SPREAD:
			game.spawn_projectiles(form, form.count)
	end_ability(false)
