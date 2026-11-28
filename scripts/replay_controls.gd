extends RefCounted

const Xbox = preload("res://scripts/xbox_controls.gd")

static func scrub(pad_id:int) -> float:
	if pad_id<0: return 0.
	var axis:=Input.get_joy_axis(pad_id,Xbox.trigger(false))-Input.get_joy_axis(pad_id,Xbox.trigger(true))
	return axis*4. if absf(axis)>=.10 else 0.

static func move_camera(camera:Camera3D,pad_id:int,delta:float) -> void:
	var direction := Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),0,float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	if pad_id>=0:
		var move := replay_stick(pad_id,JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y)
		var look := replay_stick(pad_id,JOY_AXIS_RIGHT_X,JOY_AXIS_RIGHT_Y)
		direction+=Vector3(move.x,0.,move.y)
		camera.rotation.y-=look.x*delta*2.
		camera.rotation.x=clampf(camera.rotation.x-look.y*delta*2.,-1.54,1.54)
		var zoom := float(Input.is_joy_button_pressed(pad_id,JOY_BUTTON_B))-float(Input.is_joy_button_pressed(pad_id,JOY_BUTTON_X))
		camera.fov=clampf(camera.fov+zoom*delta*45.,12.,100.)
	var rise := float(Input.is_physical_key_pressed(KEY_E))-float(Input.is_physical_key_pressed(KEY_Q))
	if pad_id>=0: rise+=float(Input.is_joy_button_pressed(pad_id,JOY_BUTTON_RIGHT_SHOULDER))-float(Input.is_joy_button_pressed(pad_id,JOY_BUTTON_LEFT_SHOULDER))
	camera.global_position += (camera.global_basis*direction+Vector3.UP*rise).limit_length(1)*delta*5.0

static func replay_stick(id: int,x: JoyAxis,y: JoyAxis) -> Vector2:
	var stick := Vector2(Input.get_joy_axis(id,x),Input.get_joy_axis(id,y)).limit_length(1.)
	return stick.normalized()*maxf(0.,(stick.length()-.16)/.84)

static func mouse_camera(camera:Camera3D,event:InputEvent) -> bool:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		camera.rotation.y -= event.relative.x*0.004
		camera.rotation.x = clampf(camera.rotation.x-event.relative.y*0.004,-1.54,1.54)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		camera.fov = clampf(camera.fov+(-3 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 3),12,100)
	else: return false
	return true
