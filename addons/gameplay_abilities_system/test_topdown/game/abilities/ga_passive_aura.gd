class_name GAPassiveAura
extends GASGameplayAbility

## 圣光被动：激活期间 Defense +5（自己挂 INFINITE GE），
## 结束/被打断时自行摘除（狂暴模式：能力生命周期 = buff 生命周期）。
## 由 ge_amulet_aura 授予并自动激活（GE 移除 → 能力回收 → 自动结束）。
var _aura_handle: int = GASAbilitySystemComponent.INVALID_HANDLE

func activate() -> void:
	super.activate()
	if asc == null:
		end_ability(true)
		return
	var aura_ge := GASGameplayEffect.new()
	aura_ge.duration_policy = GASEnums.DurationPolicy.INFINITE
	var mod := GEModifier.new()
	mod.attr_name = &"Defense"
	mod.op = GASEnums.ModifierOp.ADD
	var mag := GASModifierMagnitudeScalableFloat.new()
	mag.value = 5.0
	mod.magnitude = mag
	aura_ge.modifiers.append(mod)
	_aura_handle = asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(aura_ge))

func end_ability(was_cancelled: bool) -> void:
	if _aura_handle != GASAbilitySystemComponent.INVALID_HANDLE:
		asc.remove_active_effect(_aura_handle)
		_aura_handle = GASAbilitySystemComponent.INVALID_HANDLE
	super.end_ability(was_cancelled)
