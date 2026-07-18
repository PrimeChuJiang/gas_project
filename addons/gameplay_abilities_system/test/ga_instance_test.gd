class_name GAInstanceTest
extends GASGameplayAbility

func activate() -> void:
	super.activate()
	commit_ability()
	end_ability(false)
