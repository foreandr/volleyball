extends RefCounted

static func fatigue(actor: Node3D) -> float:
	return lerpf(.85,1.,actor.stamina.fraction())

static func arm(actor: Node3D) -> float:
	return float(actor.attributes.get("Arm swing",65))*fatigue(actor)/100.

static func kmh(actor: Node3D) -> float:
	var strength := float(actor.attributes.get("Strength",65))*fatigue(actor)/100.
	return 20.+75.*arm(actor)+25.*strength

static func rating_terms(actor:Node3D) -> String:
	return "20 + (arm %d × 0.75 + strength %d × 0.25) × %.1f%% stamina"%[
		actor.attributes.get("Arm swing",65),actor.attributes.get("Strength",65),fatigue(actor)*100.]

static func ratings(actor:Node3D) -> String:
	return rating_terms(actor)+" = %.1f km/h"%kmh(actor)
