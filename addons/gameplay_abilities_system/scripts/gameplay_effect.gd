class_name GASGameplayEffect
extends Resource

# 持续策略
@export var duration_policy : GASEnums.DurationPolicy = GASEnums.DurationPolicy.INSTANT

# 持续时长 (INSTANT 忽略)
@export var duration: float = 0.0

# 周期性间隔 (0.0 = 不周期)
@export var period: float = 0.0

# 修改器列表，元素为Dictionary:{attr_name: StringName, op: ModifierOp, magnitude: float}
@export var modifiers: Array[GEModifier] = []

# 效果自身标签
@export var asset_tags: FGameplayTagContainer = FGameplayTagContainer.new()

# 授予目标的标签 (效果存在时持续，效果移除时自动撤销)
@export var granted_tag: FGameplayTagContainer = FGameplayTagContainer.new()

# 触发的表现效果标签
@export var gameplay_cue_tags: FGameplayTagContainer = FGameplayTagContainer.new()

# GE描述
@export_multiline var comment: String = "注释，用于描述GE内容"
