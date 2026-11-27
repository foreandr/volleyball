extends RefCounted

static func fatigue(actor: Node3D) -> float:
	return lerpf(.85,1.,actor.stamina.fraction())

static func arm(actor: Node3D) -> float:
	return float(actor.attributes.get("Arm swing",65))*fatigue(actor)/100.

static func kmh(actor: Node3D) -> float:
	var strength := float(actor.attributes.get("Strength",65))*fatigue(actor)/100.
	return 20.+75.*arm(actor)+25.*strength
