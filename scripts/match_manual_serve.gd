extends Node3D

const Camp=preload("res://scripts/serving_camp.gd")
const Contact=preload("res://scripts/gym_physics.gd")
const Net=preload("res://scripts/net_collision.gd")
const Ground=preload("res://scripts/player_ground_controls.gd")
const Xbox=preload("res://scripts/xbox_controls.gd")
var curves:Array=[]
var spin:=0
var pending:=-1
var hold_time:=0.
var release_at:=INF
var clock:=0.
var contact_time:=INF
var target:=Vector3(0,.065,10.)
var station:=Vector3.ZERO
var clearance:=.20
var arc:=0.
var grip:=0.
var turning:=0
var turn_age:=0.
var launched:=false
var toss_origin:=Vector3.ZERO
var endpoint:=Vector3.ZERO
var toss_time:=0.
var airborne:=false
var plant:=preload("res://scripts/setter_jump.gd").new()
var swing:=preload("res://scripts/camp_spike_pose.gd").new()
var swing_age:=-1.
var struck_phase:=0.
var struck_point:=Vector3.ZERO
var shoulder_offset:=Vector3.ZERO

func _ready() -> void:
	for style in [0,1]:
		var driver=Camp.TECHNIQUES[style].new()
		add_child(driver)
		curves.append(driver)
	plant.attack_arm_lift=true
	plant.back_limit=-15.2
	plant.load_lead_arm_clip()
	grip=StorySession.game_options.get_value("serving","grip_angle",0.)

func reset(g) -> void:
	pending=-1
	turning=0
	release_at=INF
	clock=0.
	contact_time=INF
	launched=false
	airborne=false
	plant.active=false
	swing_age=-1.
	swing.last_shoulder_time=-1.
	swing.reach_assist=Vector3.ZERO
	station=g.human.position

func curve():
	return curves[int(spin==3)]

func button(g,style:int,down:bool) -> void:
	if g.serve_pending:
		if not down and style==g.serve_style and not is_finite(release_at): release_at=clock
		return
	if down:
		if style!=g.serve_style:
			g.serve_style=style
			g.prepare_serve(style,station)
		pending=style
		hold_time=0.
	elif pending==style: pending=-1

func turn(direction:int,down:bool) -> void:
	if down:
		turning=direction
		grip=wrapf(grip+direction*deg_to_rad(5.),-PI,PI)
		turn_age=0.
	elif turning==direction:
		turning=0
		save_grip()

func save_grip() -> void:
	StorySession.game_options.set_value("serving","grip_angle",grip)
	StorySession.save_options()

func error() -> float:
	return (release_at if is_finite(release_at) else clock)-(contact_time-Camp.SERVE_LATE)

func prepare_curve(g,origin:Vector3):
	var shot=curve()
	Camp.configure_serve_curve(shot,origin,Camp.AUTO_SERVE_MAX_KMH,3-g.serve_style,spin,clearance,arc)
	shot.target=target
	return shot

func aim(g,dt:float) -> void:
	var device:=Input.get_connected_joypads()
	if not device.is_empty():
		var id:=device[0]
		var stick:=Vector2(Input.get_joy_axis(id,JOY_AXIS_LEFT_X if g.serve_pending else JOY_AXIS_RIGHT_X),Input.get_joy_axis(id,JOY_AXIS_LEFT_Y if g.serve_pending else JOY_AXIS_RIGHT_Y))
		if Input.is_joy_button_pressed(id,Xbox.physical(JOY_BUTTON_LEFT_STICK if g.serve_pending else JOY_BUTTON_RIGHT_STICK)):
			if absf(stick.y)>.16:
				clearance=clampf(clearance-stick.y*dt*1.25,.03,2.2)
				arc=clampf(arc-stick.y*dt*1.25,-1.7,2.)
			stick.y=0.
		if stick.length()>.16:
			target.x=clampf(target.x-stick.x*5.*dt,-6.,6.)
			target.z=clampf(target.z-stick.y*5.*dt,Net.NET_Z+.2,Net.NET_Z+10.5)
	var driver=g.serve
	var origin:Vector3=endpoint if airborne else driver.preview_origin
	if g.serve_style>=2 and not airborne: origin=station+Vector3(0,g.human.height_cm*.0118+g.jump_inches(0,g.serve_vertical)*.0254,2.15)
	var shot=prepare_curve(g,origin)
	shot.preview_origin=origin
	shot.path_preview=driver.path_preview
	shot.update_path_preview()
	driver.aim_ring.position=Vector3(shot.preview_landing.x,.062,shot.preview_landing.z)

func ready_step(g,controls,dt:float,can_toss:=true) -> void:
	controls.read_pace_input()
	var stick:Vector2=controls.movement_input()
	var velocity:=Vector3(-stick.x,0,stick.y)*Ground.speed(controls.focus_requested,controls.sprint_requested and g.human.stamina.can_sprint())
	var pos:=station+velocity*dt
	pos.x=clampf(pos.x,-4.5,4.5)
	pos.z=clampf(pos.z,-15.1,-5.1)
	velocity=(pos-station)/dt
	g.serve.preview_origin+=pos-station
	station=pos
	g.human.position=pos
	if turning:
		turn_age+=dt
		if turn_age>.18: grip=wrapf(grip+turning*deg_to_rad(100.)*dt,-PI,PI)
	if velocity.length()>.01 or g.human.get_meta("walked_to_serve",false):
		Ground.face(g.human,Vector3.BACK if controls.focus_requested else velocity,dt)
		g.human.play_ground_gait(0. if controls.focus_requested else velocity.length())
		g.human.animator.advance(dt)
		Ground.shuffle(g.human,g.footwork[0],velocity,controls.focus_requested,dt)
		g.human.set_meta("walked_to_serve",true)
		g.serve.ball.global_position=Contact.palm(g.human,"l")+Vector3.UP*.10
	if controls.sprint_requested and velocity.length()>.1: g.human.stamina.spend(g.human.stamina.SPRINT_DRAIN*dt,"Sprint")
	g.serve.ball.basis=Basis(Vector3.UP,grip)
	aim(g,dt)
	if pending<0: return
	hold_time+=dt
	if not can_toss or hold_time<Camp.SERVE_HOLD_SECONDS: return
	pending=-1
	if turning: save_grip()
	turning=0
	g.serve.serve_start=station
	g.serve.reset()
	g.serve.ball.basis=Basis(Vector3.UP,grip)
	g.start_serve()
	contact_time=g.serve.contact_time()

func jump_pose(g,dt:float,after:bool) -> void:
	var human=g.human
	if plant.active: plant.step(human,dt,Vector2.ZERO)
	if swing_age>=0.: swing_age+=dt
	if not plant.active: return
	var height:float=plant.assisted_height*plant.takeoff_effectiveness
	swing.apply(human,plant,"spike" if after else "set",swing_age,struck_phase,g.serve.ball.global_position,toss_origin,endpoint,struck_point,target,shoulder_offset,height,1.,20.,1.45,spin,-1.,false,false,0.)

func step(g,dt:float) -> void:
	var driver=g.serve
	clock+=dt
	driver.swing_time=clock
	driver.elapsed=clock
	aim(g,dt)
	var old:Vector3=driver.ball.position
	if g.serve_style>=2:
		var toss:float=driver.toss_release_time()
		if clock<toss:
			driver.pose(clock)
			return
		if not airborne:
			driver.pose(toss)
			toss_origin=driver.ball.position
			endpoint=g.human.position+Vector3.BACK*2.15
			var height:float=g.jump_inches(0,g.serve_vertical)*.0254*g.human.stamina.effectiveness()
			endpoint.y=.04+g.human.height_cm*.0118+height
			var apex:=maxf(Camp.JUMP_TOSS_APEX[3-g.serve_style],endpoint.y+.1)
			toss_time=sqrt(2.*(apex-toss_origin.y)/9.81)+sqrt(2.*(apex-endpoint.y)/9.81)
			contact_time=toss+toss_time
			airborne=true
		var t:=clock-toss
		driver.ball.position=toss_origin.lerp(endpoint,t/toss_time)+Vector3.UP*4.905*t*(toss_time-t)
		var remaining:=contact_time-clock
		var height:float=g.jump_inches(0,g.serve_vertical)*.0254
		if not plant.active and swing_age<0. and remaining<=plant.flight_duration(height*g.human.stamina.effectiveness(),true)*.48+.94*(plant.LEAD_STEP_TIME+.30)+.025:
			var stance:=Vector3(endpoint.x+.09,.04,endpoint.z-.09)
			var heading:Vector3=(stance-g.human.position).slide(Vector3.UP).normalized()
			g.human.rotation.y=atan2(heading.x,heading.z)
			plant.begin(g.human,Vector2(-heading.x,heading.z),stance,.30*.94,height,3,false,.94,false,.38)
			plant.release()
		if remaining<=.20 and swing_age<0.: swing_age=0.
		jump_pose(g,dt,false)
		if not is_finite(release_at) or swing_age<.055 or Contact.palm(g.human,"r").distance_to(Geometry3D.get_closest_point_to_segment(Contact.palm(g.human,"r"),old,driver.ball.position))>.46:
			if remaining<-.12: fault(g)
			return
	else:
		driver.pose(minf(clock,contact_time))
		if clock<contact_time: return
	var grade:=error()
	if grade<Camp.SERVE_EARLY or grade>Camp.SERVE_LATE or not is_finite(release_at):
		fault(g)
		return
	g.manual.report("Serve",grade,g.manual.window_meter(grade,Camp.SERVE_EARLY,Camp.SERVE_LATE,Camp.SERVE_PERFECT,true))
	var hit:Vector3=Contact.palm(g.human,"r") if airborne else driver.ball.position
	var shot=prepare_curve(g,hit)
	Camp.strike_serve(shot,hit,target,grade,g.serve_style==3,true)
	driver.contact_clock=clock
	driver.external_rally=true
	driver.hide()
	struck_phase=swing_age
	struck_point=hit
	shoulder_offset=g.human.skeleton.to_local(hit)-g.human.skeleton.get_bone_global_pose(g.human.skeleton.find_bone("upperarm_r")).origin
	launched=true
	g.phase=g.Phase.LIVE
	g.stroke="Serve"
	g.play_touch(g.serve_style>=2)
	var angular:Vector3=shot.reception_spin_vector() if shot.has_method("reception_spin_vector") else Vector3.ZERO
	g.launch(hit,shot.velocity,"serve",0,shot.reception_spin_rps(),-1,Vector3.ZERO,Vector3.INF,angular)

func follow(g,dt:float) -> void:
	clock+=dt
	g.serve.swing_time=clock
	if airborne and plant.active: jump_pose(g,dt,true)
	elif not airborne and clock<g.serve.recovery_end() and not g.serve.moved_after_contact: g.serve.pose(clock)

func fault(g) -> void:
	var at:Vector3=g.serve.ball.global_position
	g.serve.hide()
	g.serve.contact_clock=clock
	g.serve.moved_after_contact=true
	plant.active=false
	g.serve.external_rally=true
	g.phase=g.Phase.LIVE
	g.launch(at,Vector3.DOWN*.5,"free",0)
	g.award(1,"Service fault")
