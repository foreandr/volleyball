extends RefCounted

# Team-local defaults on a 9 m half court (net Z=4, baseline Z=-5).
const BACK_ROW_DEPTH := -2.8
const BACK_ROW_SPACING := 2.6
const BACK_RIGHT := Vector3(-BACK_ROW_SPACING,.04,BACK_ROW_DEPTH)
const BACK_MIDDLE := Vector3(0.,.04,BACK_ROW_DEPTH)
const BACK_LEFT := Vector3(BACK_ROW_SPACING,.04,BACK_ROW_DEPTH)

const Xbox = preload("res://scripts/xbox_controls.gd")

# Both courts use team-local +Z toward the net.
static func attack_staging(pin: Vector3) -> Vector3:
	var line := preload("res://scripts/net_collision.gd").NET_Z-3.
	return Vector3(pin.x,pin.y,minf(line,pin.z-1.55))

static func forward_sight(ball_offset: Vector3) -> Vector3:
	var yaw := clampf(atan2(ball_offset.x,maxf(.35,ball_offset.z)),-.55,.55)
	return Vector3(sin(yaw),0.,cos(yaw))

static func focus(axis: Callable) -> bool:
	return axis.call(Xbox.trigger(true))>.25 or Input.is_physical_key_pressed(KEY_CTRL)

static func sprint(axis: Callable) -> bool:
	return axis.call(Xbox.trigger(false))>.25 or Input.is_physical_key_pressed(KEY_SHIFT)

static func block_shuffle_scale(actor:Node3D) -> float:
	return 1.+.5*clampf(actor.effective_rating("Blocking")/100.,0.,1.)

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
