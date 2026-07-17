class_name GASEffectContext
extends RefCounted

"""
Instigator    = 法师本身（谁发动的）
EffectCauser  = 火球投射物 Actor（碰撞到目标的那个东西）
Ability       = 火球能力实例
SourceObject  = 法师的法杖（可空）
TargetData    = [{TargetActor: 敌人, HitLocation: (100,200,300)}]
WorldOrigin   = (100, 200, 300) — 命中点
或是
Instigator    = 放毒雾的法师
EffectCauser  = 毒雾区域 Actor
Ability       = 毒雾能力
SourceObject  = 空
TargetData    = [{TargetActor: 踩进来的敌人}]
WorldOrigin   = 毒雾中心位置
"""
var instigator: Node # 发起者 (谁授意产生的这个效果)
var effect_causer: Node # 物理来源 (投射物/陷阱/区域本身)
var ability: Resource # 产生此效果的能力实例 (可选)
var source_object: Object # 来源对象 (武器/道具等)
var target_data: Array # 目标数据 (命中位置，命中目标列表等)
var world_0rigin: Vector3 # 效果的世界空间起始位置
var has_world_origin : bool # world_origin 是否有效

func clone() -> GASEffectContext:
	var copy = GASEffectContext.new()
	copy.instigator = instigator
	copy.effect_causer = effect_causer
	copy.ability = ability
	copy.source_object = source_object
	copy.target_data = target_data.duplicate()
	copy.world_0rigin = world_0rigin
	copy.has_world_origin = has_world_origin
	return copy
