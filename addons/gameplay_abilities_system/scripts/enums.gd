class_name GASEnums
extends RefCounted

# 持续时间决策
enum DurationPolicy{
	INSTANT,  # 立即执行一次
	DURATION, # 持续一段时间
	INFINITE  # 永久
}

# 修改器选项
enum ModifierOp{
	ADD,
	MULTIPLY,
	DIVIDE,
	OVERRIDE
}

# 计算结果收件人
enum Receiver{
	SOURCE,
	TARGET
}

# GE堆叠策略
enum StackingPolicy{
	NONE,
	LIMITED,
	REFRESH_DURATION
}

# GE到期消除策略
enum StackingExpirationPolicy{
	REMOVE_SINGLE, # 一层一层的消除
	CLEAR_ENTIRE # 整个GE一起消除
}
