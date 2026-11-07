extends Camera3D
## Behind-team camera. Court coordinates: net at Z=0, home half at positive Z.
@export var ball_target: Node3D
@export var player_target: Node3D
@export var smoothing := 4.0
var home_position := Vector3(0,5.0,11.5)
var home_focus := Vector3(0,0.9,-0.5)
var focus := Vector3(0,0.9,-0.5)
var zoom := 1.0

func _ready() -> void:
	current = true
	fov = 50.0
	near = 0.1
	far = 240.0
	reset_view()

func reset_view() -> void:
	zoom = 1.0
	focus = home_focus
	position = home_position
	look_at(focus)

func _process(delta: float) -> void:
	var wanted_focus := home_focus
	var wanted_position := home_position
	if is_instance_valid(ball_target):
		wanted_focus.x += clampf(ball_target.position.x*0.2,-0.9,0.9)
		wanted_focus.y += clampf((ball_target.position.y-1.0)*0.24,0,1.6)
		wanted_focus.z += clampf(ball_target.position.z*0.12,-0.8,0.8)
	if is_instance_valid(player_target):
		wanted_position.x += clampf(player_target.position.x*0.3,-1.0,1.0)
	wanted_position.y *= zoom
	wanted_position.z = 8.0+(home_position.z-8.0)*zoom
	var weight := 1.0-exp(-smoothing*delta)
	position = position.lerp(wanted_position,weight)
	focus = focus.lerp(wanted_focus,weight)
	look_at(focus)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R: reset_view()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: zoom = maxf(0.8,zoom-0.05)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom = minf(1.4,zoom+0.05)
