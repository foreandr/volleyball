extends RefCounted

const Xbox = preload("res://scripts/xbox_controls.gd")

static func focus(axis: Callable) -> bool:
	return axis.call(Xbox.trigger(true))>.25 or Input.is_physical_key_pressed(KEY_CTRL)

static func sprint(axis: Callable) -> bool:
	return axis.call(Xbox.trigger(false))>.25 or Input.is_physical_key_pressed(KEY_SHIFT)

static func speed(focused: bool, sprinting: bool) -> float:
	if focused: return 4.1 if sprinting else 2.35
	return 6.2 if sprinting else 4.3

static func face(actor: Node3D, direction: Vector3, delta: float, rate := 3.33) -> void:
	if direction.slide(Vector3.UP).length_squared()>.0025:
		actor.rotation.y=rotate_toward(actor.rotation.y,atan2(direction.x,direction.z),rate*delta)

static func shuffle(actor: Node3D, steps: RefCounted, velocity: Vector3, active: bool, delta: float) -> void:
	var local := actor.basis.orthonormalized().inverse()*velocity if active else Vector3.ZERO
	steps.step((local/2.35).limit_length(1.),delta,clampf(velocity.length()/2.35,.55,1.35),true,true)
	actor.set_meta("moving_shuffle",steps.weight>.04 and velocity.length()>.12)
