class_name GASCustomApplicationRequirement
extends Resource

## 子类重写，默认放行(fail-open)
func can_apply(spec: GASEffectSpec) -> bool:
	return true
