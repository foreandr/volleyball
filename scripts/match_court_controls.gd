extends Node3D

const Xbox=preload("res://scripts/xbox_controls.gd")
const Setting=preload("res://scripts/indoor_practice.gd")
const Attack=preload("res://scripts/attacking_camp.gd")
const Hands=preload("res://scripts/hand_setting_pose.gd")
const Flight=preload("res://scripts/pass_flight.gd")
const Ground=preload("res://scripts/player_ground_controls.gd")
var g
var service:=preload("res://scripts/match_manual_serve.gd").new()
var reception:=preload("res://scripts/match_manual_reception.gd").new()
var load_block:=preload("res://scripts/tryout_squat.gd").new()
var block_buffer:=-1.
enum BlockCall { AUTO, LEFT, RIGHT, COMMIT, OFF }
var block_call:=BlockCall.AUTO
var middle_blocker:=-1
var committed_flight:=-1
var call_notice:=""
var call_until:=-INF

func call_block(button:int) -> void:
	block_call={JOY_BUTTON_DPAD_LEFT:BlockCall.LEFT,JOY_BUTTON_DPAD_RIGHT:BlockCall.RIGHT,JOY_BUTTON_DPAD_UP:BlockCall.COMMIT,JOY_BUTTON_DPAD_DOWN:BlockCall.OFF}[button]
	g.block_lane_flight[0]=-1
	call_notice=["","Block left shoulder","Block right shoulder","Middle commit","No block"][block_call]
	call_until=g.match_clock+1.

func called_line(attacker_x:float) -> bool:
	return (attacker_x<=0.)==(block_call==BlockCall.RIGHT)

func middle_for_call() -> int:
	if middle_blocker>=0: return middle_blocker
	var best:=INF
	for i in range(1,g.team_size):
		var actor=g.players[i]
		var position:String=preload("res://scripts/player_profile.gd").natural_position(actor.attributes)
		var cost:=absf(actor.position.x)+.5*absf(3.42-actor.position.z)
		if position in ["M1","M2"]: cost-=12.
		if position=="Libero": cost+=15.
		if cost<best:
			best=cost
			middle_blocker=i
	return middle_blocker

var owners:={}
var modifiers:Array[int]=[]
var lane:=-1
var attack_lane:=-1
var spike_error:=INF
var aim:=Vector3.ZERO
var set_release:=INF
var set_met:=INF
var set_point:=Vector3.ZERO
var set_jump:=false
var bump_set:=false
var bump_lateral:=0.
var bump_touch:=-INF
var bump_point:=Vector3.ZERO
var high:=false
var show_arc:=false
var feedback:={}
var feedback_until:=0.
var feedback_text:=""

func configure(game) -> void:
	g=game
	add_child(service)
	add_child(reception)
	load_block.configure(self)

func clear_input() -> void:
	owners.clear()
	modifiers.clear()
	service.pending=-1
	if service.turning: service.save_grip()
	service.turning=0
	reception.held=false
	load_block.cancel()
	block_buffer=-1.
	lane=-1
	attack_lane=-1
	bump_set=false
	set_jump=false

func new_point() -> void:
	block_call=BlockCall.AUTO
	call_until=-INF
	middle_blocker=-1
	committed_flight=-1
	clear_input()
	reception.landing_actor=null
	service.reset(g)
	spike_error=INF
	set_release=INF
	set_met=INF
	bump_touch=-INF
	feedback={}
	feedback_until=0.

func axis(which:int) -> float:
	var pads:=Input.get_connected_joypads()
	return Input.get_joy_axis(pads[0],which) if pads.size() else 0.

func context() -> String:
	if g.phase==g.Phase.READY: return "serve" if g.is_human(g.server_index()) else "receive"
	if g.phase!=g.Phase.LIVE: return ""
	if g.flight_kind=="pass" and g.human_can_set() and g.touches==1: return "set"
	if g.expected_hitter==0 or (g.flight_kind=="pass" and g.possession_team==0 and g.touches==1): return "attack"
	if g.human.position.z>=2.25 and (g.blocks.has(0) or g.possession_team==1 or g.expected_hitter>=g.team_size) and g.flight_kind!="serve": return "block"
	return "receive"

func handle(event:InputEvent) -> bool:
	if g.spectator: return false
	var button:=-1
	if event is InputEventJoypadButton:
		var pads:=Input.get_connected_joypads()
		if pads.size() and event.device!=pads[0]: return false
		for logical in [JOY_BUTTON_A,JOY_BUTTON_B,JOY_BUTTON_X,JOY_BUTTON_Y,JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER,JOY_BUTTON_LEFT_STICK,JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_DOWN]:
			if event.button_index==Xbox.physical(logical): button=logical
	elif event is InputEventKey and not event.echo:
		var key:int=event.physical_keycode if event.physical_keycode else event.keycode
		button={KEY_SPACE:JOY_BUTTON_A,KEY_Q:JOY_BUTTON_A,KEY_J:JOY_BUTTON_X,KEY_I:JOY_BUTTON_Y,KEY_L:JOY_BUTTON_B,KEY_Z:JOY_BUTTON_LEFT_SHOULDER,KEY_C:JOY_BUTTON_RIGHT_SHOULDER,KEY_V:JOY_BUTTON_LEFT_STICK,KEY_UP:JOY_BUTTON_DPAD_UP,KEY_DOWN:JOY_BUTTON_DPAD_DOWN,KEY_LEFT:JOY_BUTTON_DPAD_LEFT,KEY_RIGHT:JOY_BUTTON_DPAD_RIGHT}.get(key,-1)
		if key==KEY_Y: button=JOY_BUTTON_Y
		if key==KEY_B: button=JOY_BUTTON_B
		if key==KEY_SPACE and (context()=="attack" if event.pressed else owners.get(JOY_BUTTON_X)=="attack"): button=JOY_BUTTON_X
	if button<0: return false
	if event.is_pressed() and owners.has(button): return true
	var down:=event.is_pressed()
	var mode:=context() if down else str(owners.get(button,""))
	if down: owners[button]=mode
	else: owners.erase(button)
	if g.phase==g.Phase.LIVE and button in [JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN]:
		if down: call_block(button)
		return true
	if mode=="serve":
		var face:=service.Camp.FACE.find(button)
		if face>=0:
			var previous_release:float=service.release_at
			service.button(g,3-face,down)
			if not is_finite(previous_release) and is_finite(service.release_at) and not down and is_finite(service.contact_time):
				var error:=service.error()
				report("Serve",error,window_meter(error,service.Camp.SERVE_EARLY,service.Camp.SERVE_LATE,service.Camp.SERVE_PERFECT,true))
		var spin:=[JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_DOWN].find(button)
		if spin>=0 and down: service.spin=spin
		if not g.serve_pending and button in [JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER]: service.turn(1 if button==JOY_BUTTON_LEFT_SHOULDER else -1,down)
		return true
	if button==JOY_BUTTON_A:
		if mode=="block":
			if down: load_block.begin(g.human)
			elif load_block.charging:
				block_buffer=clampf(load_block.seconds/load_block.FULL_LOAD,0.,1.)
				load_block.cancel()
				jump_if_ready()
		elif mode=="receive":
			reception.button(down,g)
			if not down: release_feedback()
		elif mode=="attack" and down and g.team_size>=3 and g.expected_hitter<0: g.input_space(true); g.space_held=false
		return true
	if button in [JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER]:
		modifiers.erase(button)
		if down: modifiers.append(button)
		if mode=="set":
			if down and button==JOY_BUTTON_RIGHT_SHOULDER: high=not high
			if down and button==JOY_BUTTON_LEFT_SHOULDER and lane>=0: set_jump=true
		return true
	if mode=="set" and button==JOY_BUTTON_LEFT_STICK and down: show_arc=not show_arc
	var index:=Setting.BUTTONS.find(button)
	if index<0: return true
	if mode=="set":
		if down:
			lane=index
			set_release=INF
			set_jump=JOY_BUTTON_LEFT_SHOULDER in modifiers
			bump_set=false
		elif lane==index: release_set()
	elif mode=="attack":
		var driver=g.attackers[0]
		if down:
			attack_lane=index
			spike_error=INF
			aim=Vector3([3.75,0.,-3.75][index],.065,8.5)
			if g.expected_hitter==0: driver.queue_jump(Vector2.ZERO)
		elif attack_lane==index:
			if g.expected_hitter==0:
				spike_error=attack_offset()
				driver.release_approach_jump()
				report("Attack",spike_error,attack_meter(spike_error,true))
			else: attack_lane=-1
	return true

func report(label:String,error:float,state:Dictionary) -> void:
	if state.get("released",false):
		var band:Vector2=state.contact
		var value:float=state.value
		ContactTiming.scored(label,error,state.grade=="Perfect",state.get("playable",value>=band.x and value<=band.y))
	feedback=state.duplicate()
	feedback_until=g.match_clock+.7
	feedback_text="%s  /  %s  (%+d ms)"%[label,state.get("grade","Early" if error<0. else "Late"),roundi(error*1000.)]
	feedback["label"]=feedback_text
	feedback["offset"]=error

func jump_if_ready() -> void:
	if owners.get(JOY_BUTTON_A)=="receive" and context()=="block" and g.flight_kind in ["pass","set"]:
		owners[JOY_BUTTON_A]="block"
		reception.held=false
		load_block.begin(g.human)
	if block_buffer<0. or g.blocks.has(0) or g.phase!=g.Phase.LIVE: return
	g.start_block(0)
	if g.blocks.has(0):
		var jump=g.blocks[0]
		jump.age=jump.START*block_buffer
		jump.net_heading=0.
		jump.aggressive_press=true
		jump.track_near_ball=false
		jump.jump_height=g.Block.loaded_height(maxf(.1,jump.jump_height*g.human.stamina.effectiveness()),block_buffer)
		g.human.stamina.spend(5,"Block jump")
		block_buffer=-1.

func aim_set() -> Vector3:
	var x:float=-3.75*bump_lateral if bump_set else [3.75,0.,-3.75][maxi(0,lane)]
	return Vector3(x,.065,3.2)

func set_apex() -> float:
	return 5.20 if high else 3.65

func draw_set_arc() -> void:
	var origin:=Hands.contact_center(g.human)
	var driver=g.attackers[0]
	var apex:=maxf(origin.y+.18,set_apex())
	var motion:Vector3=driver.set_toward_pin(origin,aim_set(),apex,driver.set_contact_height(apex))
	var duration:float=driver.descending_time(origin,motion,driver.set_contact_height(apex))
	g.trajectory.clear_surfaces()
	g.trajectory.surface_begin(Mesh.PRIMITIVE_LINE_STRIP,g.trajectory_style)
	for i in 33:
		var t:=duration*i/32.
		g.trajectory.surface_add_vertex(origin+motion*t+Vector3.DOWN*Flight.GRAVITY*.5*t*t)
	g.trajectory.surface_end()
	g.trajectory_node.show()

func set_offset() -> float:
	if is_finite(set_met): return g.elapsed-set_met-.055+Setting.RELEASE_ADVANCE
	if bump_set: return g.elapsed-g.arrival(g.human.height_cm*.0055)
	return g.elapsed-g.arrival(2.4 if set_jump else g.human.height_cm*.0108)+Setting.RELEASE_ADVANCE

func setting_meter(error:float,released:bool) -> Dictionary:
	var window:=Setting.set_window(g.human,bump_set)
	var late:=window+.055 if bump_set else minf(window,Setting.HAND_CUSHION-.055+Setting.RELEASE_ADVANCE)
	return window_meter(error,-window-.065,late,Setting.BUMP_ON_TIME if bump_set else Setting.ON_TIME,released)

func release_set() -> void:
	set_release=g.elapsed
	var error:=set_offset()
	report("Set",error,setting_meter(error,true))

func attack_offset() -> float:
	return g.elapsed-g.attackers[0].pin_arrival+Attack.RELEASE_LEAD+Attack.GRADE_ADVANCE

func attack_release_valid() -> bool:
	return spike_error>=Attack.EARLY_LIMIT and spike_error<=Attack.LATE_LIMIT

func attack_meter(error:float,released:bool) -> Dictionary:
	var clean:=error>=-Attack.CLEAN_EARLY and error<=Attack.CLEAN_LATE
	return {"value":clampf(inverse_lerp(Attack.METER_START,Attack.METER_END,error),0.,1.),"perfect":Vector2(inverse_lerp(Attack.METER_START,Attack.METER_END,-Attack.CLEAN_EARLY),inverse_lerp(Attack.METER_START,Attack.METER_END,Attack.CLEAN_LATE)),"contact":Vector2(inverse_lerp(Attack.METER_START,Attack.METER_END,Attack.EARLY_LIMIT),inverse_lerp(Attack.METER_START,Attack.METER_END,Attack.LATE_LIMIT)),"released":released,"grade":"Perfect" if clean else ("Early" if error<0. else "Late")}

func window_meter(error:float,early:float,late:float,green:float,released:bool) -> Dictionary:
	var lo:=early-.08
	var hi:=late+.025
	return {"value":clampf(inverse_lerp(lo,hi,error),0.,1.),"perfect":Vector2(inverse_lerp(lo,hi,-green),inverse_lerp(lo,hi,green)),"contact":Vector2(inverse_lerp(lo,hi,early),inverse_lerp(lo,hi,late)),"released":released,"grade":"Perfect" if absf(error)<=green else ("Early" if error<0. else "Late")}

func timing() -> Dictionary:
	if g.match_clock<feedback_until: return feedback
	if g.phase==g.Phase.READY and g.serve_pending and g.is_human(g.server_index()):
		return window_meter(service.error(),service.Camp.SERVE_EARLY,service.Camp.SERVE_LATE,service.Camp.SERVE_PERFECT,is_finite(service.release_at))
	if not reception.motion.is_empty():
		var result:=reception.meter(g,g.ball.global_position).duplicate()
		result.merge({"perfect":Vector2(.33,.67),"contact":Vector2(.08,.90),"released":not reception.held})
		return result
	if load_block.charging: return window_meter(load_block.seconds/load_block.FULL_LOAD-.65,-.65,.35,.11,false)
	if context()=="set" and lane>=0: return setting_meter(set_offset(),is_finite(set_release))
	if g.expected_hitter==0 and attack_lane>=0: return attack_meter(attack_offset(),is_finite(spike_error))
	return {}

func release_feedback() -> void:
	if not reception.grade.is_empty():
		var state:=reception.grade.duplicate()
		state.merge({"perfect":Vector2(.33,.67),"contact":Vector2(.08,.90),"released":true})
		report("Dig" if g.defensive_ball() else "Pass",state.offset,state)

func flight_changed(kind:String) -> void:
	reception.stop_pose()
	set_met=INF
	bump_touch=-INF
	set_release=INF
	set_jump=false
	lane=-1
	bump_set=false
	if kind!="set":
		attack_lane=-1
		spike_error=INF

# A player can hold a target while moving into a set or approach.
# Preserve its release owner when the previous touch changes the rally role.
func claim_held_target() -> void:
	var mode:=context()
	if mode not in ["set","attack"]: return
	for key in owners:
		var index:=Setting.BUTTONS.find(key)
		if index<0 or owners[key] not in ["receive","attack"]: continue
		owners[key]=mode
		if mode=="set":
			lane=index
			set_jump=JOY_BUTTON_LEFT_SHOULDER in modifiers
		else:
			attack_lane=index
			aim=Vector3([3.75,0.,-3.75][index],.065,8.5)

func attack_step(dt:float) -> void:
	if g.expected_hitter!=0 or attack_lane<0: return
	var driver=g.attackers[0]
	var lane_x:float=[3.75,0.,-3.75][attack_lane]
	if driver.jump.active:
		var move:=Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y))
		aim.x=clampf(aim.x-move.x*3.*dt,lane_x-2.5,lane_x+2.5)
		aim.z=clampf(aim.z-move.y*10.*dt,4.65,16.)
	driver.swing_aim=aim
	var last:int=-1 if modifiers.is_empty() else modifiers.back()
	driver.rally_shot="roll" if last==JOY_BUTTON_LEFT_SHOULDER else ("tip" if last==JOY_BUTTON_RIGHT_SHOULDER else "spike")

func aim_bump(stick:Vector2) -> void:
	if stick.length()>.55 and (lane<0 or bump_set) and not is_finite(set_release):
		bump_set=true
		bump_lateral=stick.normalized().x
		lane=0 if stick.x<-.32 else (2 if stick.x>.32 else 1)
	elif bump_set and stick.length()<.25 and not is_finite(set_release): release_set()


func manual_set(previous:float) -> bool:
	if context()!="set": return false
	aim_bump(Vector2(axis(JOY_AXIS_RIGHT_X),axis(JOY_AXIS_RIGHT_Y)))
	if lane<0: return false
	var actor=g.human
	var point:Vector3=g.ball.global_position
	var hands:=Hands.contact_center(actor)
	var offset:=set_offset()
	if set_jump and not g.jump_set_started[0] and offset>=-.39:
		g.jump_set_started[0]=true
		g.set_jumps[0].begin_set_jump(actor,.07,.52)
	g.animated[0]=true
	if not bump_set:
		var facing:Vector3=aim_set()-actor.position
		if lane==2: facing=-facing
		Ground.face(actor,facing,maxf(0.,g.elapsed-previous))
		var forehead:Vector3=actor.global_position+Vector3.UP*actor.height_cm*.0108+actor.global_basis.z*.19
		var goal:Vector3=forehead+(point-forehead).limit_length(.43)*(1.-smoothstep(.12,.8,absf(offset)))
		var push:Vector3=aim_set()-point
		Hands.standing_set(actor,goal,push,push.normalized(),-1.,smoothstep(-.45,-.10,offset))
		var proximity:=1.-smoothstep(.18,.6,point.distance_to(forehead))
		if proximity>0.: preload("res://scripts/gym_physics.gd").track_hands(actor,point,true,proximity,159.,.68)
		hands=Hands.contact_center(actor)
		if not is_finite(set_met):
			var closest:=Geometry3D.get_closest_point_to_segment(hands,g.path_point(previous),point)
			if hands.distance_to(closest)<=.29:
				set_met=g.elapsed
				set_point=closest
		if is_finite(set_met) and g.elapsed-set_met<=Setting.HAND_CUSHION:
			g.ball.global_position=set_point
		elif is_finite(set_met): return false
		if not is_finite(set_release) or not is_finite(set_met): return false
		if set_release<set_met-Setting.set_window(actor,false)-.065 or set_release>set_met+Setting.HAND_CUSHION: return false
	else: return bump_step(previous)
	g.platforms[0].height=set_apex()
	g.platforms[0].hand_setting=true
	g.platforms[0].release_time=set_release
	g.platforms[0].touch_time=g.elapsed
	var contact:=set_point
	var push:=aim_set()-contact
	g.receive_contact(0,contact,Vector3.UP*6.,2 if set_jump else 1)
	if g.recoveries.has(0): g.recoveries[0]["set_push"]={"point":contact,"direction":push}
	return true

func bump_step(previous:float) -> bool:
	var actor=g.human
	var point:Vector3=g.ball.global_position
	var sampler=g.platforms[0]
	var height:float=actor.height_cm*.0055
	var at:float=g.arrival(height)
	var predicted:Vector3=g.path_point(at)
	var remaining:float=at-g.elapsed
	sampler.apply_pose(sampler.contact_frame,1.-smoothstep(.14,.48,remaining))
	sampler.pose_bump_receive(-remaining)
	predicted.y=clampf(predicted.y,actor.position.y+.27,actor.position.y+actor.height_cm*.0081)
	sampler.reach_platform(predicted-sampler.platform_center(),1.-smoothstep(.055,.38,remaining),.77,true,false)
	var before:Vector3=g.path_point(previous)
	var hit:=Setting.bump_overlap(actor,before,point)
	if before.y>point.y and hit.gap<=.27:
		bump_touch=g.elapsed
		bump_point=hit.point
	if not is_finite(set_release) or g.elapsed-bump_touch>Setting.BUMP_ON_TIME+.035: return false
	var timing:float=set_release-at
	if timing< -Setting.set_window(actor,true)-.065 or timing>Setting.set_window(actor,true)+.055: return false
	sampler.destination=Vector2(aim_set().x,aim_set().z)
	sampler.forearm_setting=true
	sampler.height=set_apex()
	sampler.touch_time=g.elapsed
	g.receive_contact(0,bump_point,Vector3.UP*6.,0)
	return true
