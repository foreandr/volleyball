extends RefCounted

const AnimationCatalog = preload("res://scripts/volleyball_animations.gd")
const HandPose = preload("res://scripts/hand_setting_pose.gd")
const Court = preload("res://scripts/preview_court.gd")
const LOAD_TIME := 0.24
const APPROACH_LOAD_TIME := 0.36
const FULL_AIR_TIME := 1.02
const LAND_TIME := 0.16
const FULL_HEIGHT := 1.27
const TAP_HEIGHT := 0.18
const AIR_TRAVEL_FRACTION := 0.38
const AIR_STEER_SPEED := 1.00
const AIR_STEER_ACCELERATION := 5.0
var active := false
var load_bend_extra := 0.0
var attack_arm_lift := false
var load_arm_extra := 0.0
var front_limit := 2.5
var back_limit := Court.RUNOFF_NEAR_BASELINE
var elapsed := 0.0
var held := false
var hold_time := 0.0
var max_height := FULL_HEIGHT
var height := FULL_HEIGHT
var air_time := FULL_AIR_TIME
var start: Vector3
var heading: Vector3
var stride := 0.0
var carry_velocity := Vector3.ZERO
var air_velocity := Vector3.ZERO
var air_offset := Vector3.ZERO
const LEAD_STEP_TIME := 0.24
var lead_time := 0.0
var lead_step_duration := LEAD_STEP_TIME
var air_glide_duration := 0.58
var entry_time := 0.0
var entry_distance := 0.0
var lead_arm_clip: Animation
var lead_distance := 0.0
var approach_plant := false
var setting_jump := false
var assisted_load_time := APPROACH_LOAD_TIME
var assisted_height := 0.0
var standing_load_time := LOAD_TIME
var approach_lunge := Vector3.ZERO
var right_foot_start: Vector3
var left_foot_start: Vector3
var right_plant: Vector3
var left_plant: Vector3
var plant_legs := {}
var plant_ground := 0.0
var entry_leg_rotations := {}
var entry_body_pose := {}
var incoming_plant_speed := 0.0
var attack_glide := 0.0

func load_lead_arm_clip() -> void:
	var copies := AnimationCatalog.custom_entries()
	for index in range(copies.size()-1,-1,-1):
		var entry := copies[index]
		if entry.get("source") == "approach_first_left_step":
			lead_arm_clip = load(entry.path) as Animation
			return

func begin(actor: Node3D, input: Vector2, ball_target := Vector3.INF, plant_time := APPROACH_LOAD_TIME, jump_height := 0.0, approach_steps := 2, from_sprint := false, tempo := 1.0, for_setting := false, glide := 0.0) -> void:
	if active: return
	active = true
	held = true
	hold_time = 0.0
	height = TAP_HEIGHT
	elapsed = 0.0
	air_velocity = Vector3.ZERO
	carry_velocity = Vector3.ZERO
	air_offset = Vector3.ZERO
	start = actor.position
	var travel := Vector3(-input.x,0,input.y)
	stride = 0.17+0.31*travel.length()
	heading = travel.normalized() if not travel.is_zero_approx() else actor.basis.z.normalized()
	approach_lunge = Vector3.ZERO
	approach_plant = ball_target.is_finite()
	setting_jump = for_setting
	standing_load_time = LOAD_TIME
	assisted_load_time = plant_time
	assisted_height = jump_height
	lead_step_duration = LEAD_STEP_TIME*tempo
	air_glide_duration = 0.58*lerpf(0.72,1.0,tempo)
	lead_time = lead_step_duration*(approach_steps-2)
	entry_time = lead_step_duration if approach_steps == 4 else 0.0
	entry_distance = 0.0
	lead_distance = 0.0
	plant_legs.clear()
	entry_leg_rotations.clear()
	entry_body_pose.clear()
	incoming_plant_speed = 0.0
	attack_glide = 0.0
	if approach_plant and not setting_jump:
		var rig: Skeleton3D = actor.skeleton
		var parent := actor.get_parent_node_3d()
		for side in ["l","r"]:
			var foot := rig.find_bone("foot_"+side)
			plant_legs[side] = parent.global_transform.affine_inverse()*rig.global_transform*rig.get_bone_global_pose(foot)
		plant_ground = minf(plant_legs.l.origin.y,plant_legs.r.origin.y)
		for joint in ["pelvis","spine_01","spine_02","spine_03","neck_01","head"]:
			var bone := rig.find_bone(joint)
			if bone >= 0: entry_body_pose[bone] = rig.get_bone_pose(bone)
		for joint in ["thigh_l","thigh_r","calf_l","calf_r","foot_l","foot_r","ball_l","ball_r"]:
			var bone := rig.find_bone(joint)
			entry_leg_rotations[bone] = rig.get_bone_pose_rotation(bone)
	if from_sprint:
		actor.model.rotation.y = 0.0
		actor.animator.speed_scale = 1.0
		actor.play_action("idle",0.0)
		actor.animator.advance(0.0)
	if approach_plant:
		var ball_offset := (ball_target-start).slide(Vector3.UP)
		if entry_time > 0.0: entry_distance = clampf(ball_offset.length()-1.85,0.45,1.15)
		if lead_time > 0.0: lead_distance = clampf(ball_offset.length()-entry_distance-1.12,0.40,0.90)
		stride = minf(0.40,minf(stride,maxf(0.08,ball_offset.length()*0.60)))
		var rig: Skeleton3D = actor.skeleton
		right_foot_start = actor.get_parent_node_3d().to_local(rig.to_global(rig.get_bone_global_pose(rig.find_bone("foot_r")).origin))
		left_foot_start = actor.get_parent_node_3d().to_local(rig.to_global(rig.get_bone_global_pose(rig.find_bone("foot_l")).origin))
		if not plant_legs.is_empty():
			right_foot_start = plant_legs.r.origin
			left_foot_start = plant_legs.l.origin
		right_plant = right_foot_start+heading*(entry_distance+lead_distance+stride*0.68)
		var toward_ball := (ball_target-right_plant).slide(Vector3.UP).normalized()
		var reach := (ball_target-start-heading*(stride+entry_distance+lead_distance)).slide(Vector3.UP)
		approach_lunge = reach.normalized()*clampf(reach.length()-0.055,0.0,0.95)
		attack_glide = minf(glide,stride*0.68)
		stride -= attack_glide
		if toward_ball.is_zero_approx(): toward_ball = heading.slide(Vector3.UP).normalized()
		var plant_width := -0.19 if actor.mirror_animation else 0.19
		left_plant = right_plant+toward_ball*0.43+Vector3.UP.cross(toward_ball)*plant_width
		right_plant.y = minf(right_foot_start.y,left_foot_start.y)
		left_plant.y = right_plant.y
		if not plant_legs.is_empty():
			# Aim the last two steps around the body's takeoff spot.
			var center := start+heading*(entry_distance+lead_distance+stride)
			var width := heading.cross(Vector3.UP)*plant_width
			right_plant = center-heading*0.19+width
			left_plant = center+heading*0.20-width
			right_plant.y = plant_ground
			left_plant.y = plant_ground
	if not from_sprint: actor.play_action("idle")

func carry_run_into_plant(velocity: Vector3) -> void:
	var entry_speed := velocity.dot(heading)
	if entry_speed <= 0.0: return
	# Reserve the longer stride for the right, then close through to the left.
	var running_left := (left_foot_start-start).dot(heading)
	var width := (right_plant-start).dot(heading.cross(Vector3.UP))
	var lateral := heading.cross(Vector3.UP)*width
	var right_step := 0.80
	var left_step := 0.42
	# Shorten the plant if the set leaves too little time for two full strides.
	var fit_time := clampf((entry_speed*load_duration()-running_left+0.16)/right_step,0.20,1.0)
	var timed_fit := lerpf(fit_time,1.0,smoothstep(0.16,0.25,load_duration()))
	right_step *= timed_fit
	left_step *= timed_fit
	if heading.z > 0.0:
		var available := (front_limit-start.z-absf(lateral.z))/heading.z-running_left
		var fit := clampf(available/(right_step+left_step),0.0,1.0)
		right_step *= fit
		left_step *= fit
	var right_distance := running_left+right_step
	var left_distance := right_distance+left_step
	right_plant = start+heading*right_distance+lateral
	left_plant = start+heading*left_distance-lateral
	right_plant.y = plant_ground
	left_plant.y = plant_ground
	var ground_advance := maxf(0.0,right_distance-0.16-stride)
	stride += ground_advance
	incoming_plant_speed = minf(entry_speed,3.0*stride/load_duration())
	approach_lunge = approach_lunge.move_toward(Vector3.ZERO,ground_advance*(1.0+AIR_TRAVEL_FRACTION))

func begin_set_jump(actor: Node3D, load: float, jump_height := 0.56) -> void:
	if active: return
	begin(actor,Vector2.ZERO,Vector3.INF,APPROACH_LOAD_TIME,jump_height,2,false,1.0,true)
	standing_load_time = load
	stride = 0.0

func release() -> void:
	held = false

func horizontal_velocity() -> Vector3:
	return carry_velocity+air_velocity+heading*(stride*AIR_TRAVEL_FRACTION/air_time+attack_glide*glide_speed())

func glide_speed() -> float:
	return (1.0-smoothstep(0.46,0.66,elapsed-load_duration()))/0.46

func load_duration() -> float:
	return assisted_load_time+lead_time if approach_plant else standing_load_time

func flight_duration(jump_height: float, assisted: bool) -> float:
	return FULL_AIR_TIME*sqrt(jump_height/FULL_HEIGHT)*(1.09 if assisted else 1.0)

func step(actor: Node3D, delta: float, input: Vector2) -> void:
	var load_time := load_duration()
	if elapsed < load_time:
		if held: hold_time += minf(delta,load_time-elapsed)
		height = assisted_height if assisted_height > 0.0 else lerpf(TAP_HEIGHT,max_height,clampf(hold_time/LOAD_TIME,0.0,1.0))
		air_time = flight_duration(height,assisted_height > 0.0)
	var previous_flight := clampf(elapsed-load_time,0.0,air_time)
	elapsed += delta
	var air_delta := clampf(elapsed-load_time,0.0,air_time)-previous_flight
	if air_delta > 0.0:
		var steering := Vector3(-input.x,0.0,input.y).limit_length()*AIR_STEER_SPEED
		air_velocity = air_velocity.move_toward(steering,AIR_STEER_ACCELERATION*air_delta)
		air_offset += (carry_velocity+air_velocity)*air_delta
	var flight := clampf((elapsed-load_time)/air_time,0.0,1.0)
	var pose_time := minf(maxf(0.0,elapsed-lead_time),load_time-lead_time)*LOAD_TIME/(load_time-lead_time)+maxf(0.0,elapsed-load_time)
	var first := smoothstep(0.015,0.12,pose_time)
	var second := smoothstep(0.12,0.225,pose_time)
	if lead_time > 0.0:
		first = smoothstep(0.045,0.135,pose_time)
		second = smoothstep(0.135,0.21,pose_time)
	var lead_age := elapsed-entry_time
	var lead_progress := smoothstep(0.0,lead_step_duration,lead_age) if lead_time > 0.0 else 0.0
	var entry_progress := smoothstep(0.0,entry_time,elapsed) if entry_time > 0.0 else 0.0
	var distance := entry_distance*entry_progress+lead_distance*lead_progress+stride*(0.34*first+0.66*second+AIR_TRAVEL_FRACTION*flight)
	var transfer_hop := 0.0
	if lead_time > 0.0:
		transfer_hop = 0.05*smoothstep(lead_step_duration*0.82,lead_step_duration,lead_age)*(1.0-smoothstep(0.0,0.135,pose_time))
	if not plant_legs.is_empty() and lead_time > 0.0:
		# Let the longer approach transfer weight without a separate hop between steps.
		transfer_hop *= 0.30
		# Carry momentum between the lead step and the final plant.
		var ground_distance := entry_distance+lead_distance+stride
		var stepped_distance := distance-stride*AIR_TRAVEL_FRACTION*flight
		var continuous_distance := ground_distance*smoothstep(0.0,load_time,elapsed)
		distance += (continuous_distance-stepped_distance)*0.32
	if incoming_plant_speed > 0.0:
		var progress := clampf(elapsed/load_time,0.0,1.0)
		var plant_distance := stride*smoothstep(0.0,1.0,progress)
		plant_distance += incoming_plant_speed*load_time*progress*(1.0-progress)**2
		distance = plant_distance+stride*AIR_TRAVEL_FRACTION*flight
	var base := start+heading*distance+Vector3.UP*(4.0*height*flight*(1.0-flight)+transfer_hop)
	var lunge := approach_lunge*smoothstep(0.0,air_glide_duration,elapsed-load_time)
	# Carry part of the approach stride through the air and ease it out after the strike.
	var air_age := maxf(0.0,elapsed-load_time)
	var fade := clampf((air_age-0.46)/0.20,0.0,1.0)
	var glide_fraction := (minf(air_age,0.46)+0.20*(fade-fade**3+0.5*fade**4))/0.46
	var glide := heading*attack_glide*(glide_fraction+AIR_TRAVEL_FRACTION*flight)
	var position := base+air_offset+lunge+glide
	actor.position = Court.clamp_setter(position,front_limit,back_limit)
	if air_delta > 0.0: air_offset += actor.position-position
	actor.animator.advance(delta)
	var landing := elapsed-load_time-air_time
	if landing >= LAND_TIME:
		active = false
		return
	var lead_load := 0.70*smoothstep(0.0,lead_step_duration*0.78,lead_age) if lead_time > 0.0 else 0.0
	var load_in := lerpf(lead_load,1.0,smoothstep(0.035 if lead_time > 0.0 else 0.02,0.12 if lead_time > 0.0 else 0.19,pose_time))
	var entry_load := run_entry_load(pose_time)
	var load := maxf(load_in,entry_load*0.66)*(1.0-smoothstep(0.19,LOAD_TIME+0.055,pose_time))
	var impact := smoothstep(-0.025,0.04,landing)*(1.0-smoothstep(0.04,LAND_TIME,landing))
	var knee_impact := impact
	if not plant_legs.is_empty():
		knee_impact = smoothstep(-0.065,0.065,landing)*(1.0-smoothstep(0.065,LAND_TIME,landing))
	var arm_drive := smoothstep(0.17,0.37,pose_time)*(1.0-smoothstep(LOAD_TIME+air_time*0.56,LOAD_TIME+air_time*0.93,pose_time))
	pose_jump(actor,first,second,load,impact,arm_drive,pose_time,flight,load_in,transfer_hop,knee_impact)

func run_entry_load(pose_time: float) -> float:
	if incoming_plant_speed <= 0.0: return 0.0
	return smoothstep(0.0,0.075,pose_time)*(1.0-smoothstep(0.095,0.17,pose_time))

func attack_plant_foot(side: String) -> Vector3:
	var left := side == "l"
	var from: Vector3 = plant_legs[side].origin
	var to := left_plant if left else right_plant
	var end := load_duration()
	var start_step := lead_time*0.48 if not left else lead_time*0.92
	var end_step := lead_time+(end-lead_time)*(0.53 if not left else 0.96)
	if incoming_plant_speed > 0.0:
		if left: start_step = end*0.36
		end_step = end*(0.91 if left else 0.65)
	if (left and lead_time > 0.0) or (not left and entry_time > 0.0):
		var early_start := entry_time*0.70 if left else 0.0
		var early_end := lead_time*0.86 if left else entry_time*0.88
		var early := smoothstep(early_start,early_end,elapsed)
		var step_end := from+heading*(entry_distance+lead_distance if left else entry_distance)
		step_end.y = plant_ground
		from = from.lerp(step_end,early)+Vector3.UP*(0.09*pow(sin(PI*early),2.0))
	var step := smoothstep(start_step,end_step,elapsed)
	return from.lerp(to,step)+Vector3.UP*((0.095 if left else 0.075)*pow(sin(PI*step),2.0))

func pose_jump(actor: Node3D, first: float, second: float, load: float, impact: float, arm_drive: float, pose_time: float, flight: float, load_in: float, transfer_hop: float, knee_impact: float) -> void:
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var original := pose.duplicate()
	var pelvis := rig.find_bone("pelvis")
	var parent := rig.get_bone_parent(pelvis)
	var hips: Transform3D = author.world_pose(pose,parent)
	var scale_: float = rig.global_basis.y.length()
	var lead_age := elapsed-entry_time
	var backswing_peak := 0.
	if attack_arm_lift and approach_plant and lead_time>0.:
		# Load over the long right step, then unfold through the closing left plant.
		var plant_phase := (elapsed-lead_time)/(load_duration()-lead_time)
		backswing_peak = smoothstep(.035,.53,plant_phase)*(1.-smoothstep(.53,1.,plant_phase))
		author.rotate_world(pose,"spine_01",Vector3.RIGHT,deg_to_rad(24.)*backswing_peak)
		author.rotate_world(pose,"spine_02",Vector3.RIGHT,deg_to_rad(14.)*backswing_peak)
	var lead_plant_load := 0.0
	if lead_time > 0.0:
		lead_plant_load = smoothstep(lead_step_duration*0.38,lead_step_duration*0.82,lead_age)*(1.0-smoothstep(0.0,0.135,pose_time))
	pose[pelvis].origin -= hips.basis.inverse()*Vector3.UP*(0.15*load+0.14*impact+0.035*lead_plant_load)/scale_
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,(0.16+load_bend_extra)*load+0.13*impact-0.22*arm_drive)
	if approach_plant and not setting_jump:
		var penultimate_plant := 0.135 if lead_time > 0.0 else 0.105
		var rise := 0.0
		if entry_time > 0.0:
			rise = 0.58*smoothstep(0.045,penultimate_plant,pose_time)
		rise = lerpf(rise,1.0,smoothstep(penultimate_plant,LOAD_TIME,pose_time))
		var upright := rise*(1.0-smoothstep(LOAD_TIME,LOAD_TIME+0.12,pose_time))
		# Start unfolding during the penultimate step and finish over the push-off.
		upright = lerpf(upright,smoothstep(0.07,LOAD_TIME+0.055,pose_time)*(1.0-smoothstep(LOAD_TIME+0.055,LOAD_TIME+0.15,pose_time)),0.75)
		var torso: Vector3 = author.point(pose,"neck_01")-author.point(pose,"spine_02")
		var pitch := atan2(torso.z,torso.y)
		author.rotate_world(pose,"spine_02",Vector3.RIGHT,(-deg_to_rad(5.0)-pitch)*upright)
	var body_entry := 1.0-smoothstep(0.0,0.14,elapsed)
	if body_entry > 0.0:
		for bone in entry_body_pose:
			pose[bone] = pose[bone].interpolate_with(entry_body_pose[bone],body_entry)
	var travel := actor.basis.inverse()*heading*stride/scale_
	if actor.mirror_animation: travel.x = -travel.x
	var stagger := 0.34*(first-second)
	var tuck := sin(PI*flight)
	var leg_pose := pose
	if not plant_legs.is_empty():
		# Absorb the landing over more frames while keeping the torso and arm tracks intact.
		leg_pose = pose.duplicate()
		leg_pose[pelvis].origin -= hips.basis.inverse()*Vector3.UP*(0.14*(knee_impact-impact))/scale_
	for side in ["l","r"]:
		var left: bool = side == "l"
		var foot: String = "foot_"+side
		var foot_pose: Transform3D = author.world_pose(original,rig.find_bone(foot))
		var lift := sin(PI*first) if left else sin(PI*second)
		var target := foot_pose.origin+travel*stagger*(1.0 if left else -1.0)+Vector3.UP*(0.085*lift+0.07*tuck)
		if not plant_legs.is_empty() and pose_time < LOAD_TIME+0.14:
			var takeoff := smoothstep(LOAD_TIME,LOAD_TIME+0.14,pose_time)
			var planted := attack_plant_foot(side)
			# Once airborne, carry the feet up with the body before folding the knees.
			planted.y += maxf(0.0,actor.position.y-start.y)*smoothstep(LOAD_TIME-0.04,LOAD_TIME+0.035,pose_time)
			target = rig.to_local(actor.get_parent_node_3d().to_global(planted)).lerp(target,takeoff)
			var entry_basis: Basis = plant_legs[side].basis
			var entry_world := actor.get_parent_node_3d().global_basis*entry_basis
			var entry_local := (rig.global_basis.inverse()*entry_world).orthonormalized()
			foot_pose.basis = entry_local.slerp(foot_pose.basis,smoothstep(0.0,0.16,elapsed))
		elif approach_plant and pose_time < LOAD_TIME+0.08:
			var step_progress := smoothstep(0.105,0.21,pose_time) if left else smoothstep(0.015,0.105,pose_time)
			if lead_time > 0.0:
				step_progress = smoothstep(0.135,0.21,pose_time) if left else smoothstep(0.045,0.135,pose_time)
			var plant_from := left_foot_start if left else right_foot_start
			if not left and entry_time > 0.0:
				var entry_progress := smoothstep(0.0,entry_time*0.86,elapsed)
				plant_from += heading*(entry_distance+0.07)*entry_progress+Vector3.UP*0.10*sin(PI*entry_progress)
			if left and lead_time > 0.0:
				var lead_progress := smoothstep(0.0,lead_step_duration*0.82,lead_age)
				plant_from += heading*(entry_distance+lead_distance+0.07)*lead_progress+Vector3.UP*0.08*sin(PI*lead_progress)
			var plant_to := left_plant if left else right_plant
			var planted := plant_from.lerp(plant_to,step_progress)
			planted.y += transfer_hop+sin(PI*step_progress)*(0.12 if left else 0.09)
			var release_weight := smoothstep(LOAD_TIME,LOAD_TIME+0.08,pose_time)
			target = rig.to_local(actor.get_parent_node_3d().to_global(planted)).lerp(target,release_weight)
		var pole := Vector3(0.15 if left else -0.15,0.08,1.0) if not plant_legs.is_empty() else Vector3(0.09 if left else -0.09,0.25,1.0)
		if plant_legs.is_empty():
			author.limb(pose,"thigh_"+side,"calf_"+side,foot,target,pole)
		else:
			author.limb(leg_pose,"thigh_"+side,"calf_"+side,foot,target,pole,1.0,162.0,true)
			for joint in ["thigh_"+side,"calf_"+side]:
				var bone := rig.find_bone(joint)
				pose[bone].basis = leg_pose[bone].basis
		author.set_world_basis(pose,foot,foot_pose.basis)
		if setting_jump: continue
		var upper_arm: String = "upperarm_"+side
		var forearm: String = "lowerarm_"+side
		var arm_load := load
		if approach_plant:
			# Carry the plant's backswing into the spike instead of pumping overhead first.
			arm_load = maxf(load_in,run_entry_load(pose_time)*0.58)*(1.0-smoothstep(LOAD_TIME,LOAD_TIME+0.17,pose_time))
		var front_swing := 0.0
		if lead_time > 0.0:
			var sweep_back := smoothstep(0.0,0.12,pose_time)
			front_swing = 0.20*smoothstep(0.0,lead_step_duration*0.72,lead_age)*(1.0-sweep_back)
			arm_load *= sweep_back
			if attack_arm_lift and approach_plant:
				# Start both hands back with the long right step, then drive
				# them forward as the closing left foot accepts weight.
				var plant_phase := (elapsed-lead_time)/(load_duration()-lead_time)
				var sweep := smoothstep(lead_time*.44,lead_time+(load_duration()-lead_time)*.53,elapsed)
				arm_load = sweep*(1.-smoothstep(.66,1.10,plant_phase))
		var jump_drive := arm_drive if not approach_plant or attack_arm_lift else 0.0
		author.rotate_world(pose,upper_arm,Vector3.RIGHT,(1.52+load_arm_extra)*arm_load-front_swing+deg_to_rad(15.)*backswing_peak)
		author.rotate_world(pose,forearm,Vector3.RIGHT,-0.25*jump_drive)
		var shoulder: Vector3 = author.point(pose,upper_arm)
		var elbow: Vector3 = author.point(pose,forearm)
		if approach_plant and arm_load > 0.0:
			var upper_direction := elbow-shoulder
			var tucked_direction := upper_direction
			tucked_direction.x *= 1.0-0.65*arm_load
			var upper_pose: Transform3D = author.world_pose(pose,rig.find_bone(upper_arm))
			var tuck_rotation := Quaternion(upper_direction.normalized(),tucked_direction.normalized())
			author.set_world_basis(pose,upper_arm,Basis(tuck_rotation)*upper_pose.basis)
			elbow = author.point(pose,forearm)
		var wrist: Vector3 = author.point(pose,"hand_"+side)
		var extension := (0.52+0.20*arm_load if approach_plant else 0.52)*smoothstep(0.02,0.16,(shoulder.z-elbow.z)*scale_)
		if extension > 0.0:
			var forearm_pose: Transform3D = author.world_pose(pose,rig.find_bone(forearm))
			var straighten := Quaternion((wrist-elbow).normalized(),(elbow-shoulder).normalized())
			author.set_world_basis(pose,forearm,Basis(Quaternion.IDENTITY.slerp(straighten,extension))*forearm_pose.basis)
		if jump_drive > 0.0:
			var outward := 1.0 if left else -1.0
			var hand: String = "hand_"+side
			var overhead := shoulder+Vector3(-outward*0.065,0.49,0.16)/scale_
			var raised := pose.duplicate()
			author.limb(raised,upper_arm,forearm,hand,overhead,Vector3(outward*0.50,-0.42,0.52),1.0,151.0)
			for joint in [upper_arm,forearm]:
				var bone := rig.find_bone(joint)
				pose[bone].basis = pose[bone].basis.slerp(raised[bone].basis,jump_drive)
			var base: Transform3D = author.world_pose(pose,rig.find_bone(hand))
			var fingers: Vector3 = author.point(pose,"middle_01_"+side)-base.origin
			var across: Vector3 = author.point(pose,"index_01_"+side)-author.point(pose,"pinky_01_"+side)
			var hand_orientation := HandPose.hand_basis(Vector3(-outward*0.24,0.85,0.34),Vector3(-outward*0.72,-0.24,-0.52))
			var rotation := hand_orientation*HandPose.hand_basis(fingers,across).inverse()
			author.set_world_basis(pose,hand,Basis(Quaternion.IDENTITY.slerp(rotation.get_rotation_quaternion(),jump_drive*0.75))*base.basis)
	if lead_time > 0.0 and lead_arm_clip != null and lead_age >= 0.0 and elapsed < lead_time+0.10:
		var track := lead_arm_clip.find_track(^"Armature/Skeleton3D:upperarm_r",Animation.TYPE_ROTATION_3D)
		if track >= 0:
			var bone := rig.find_bone("upperarm_r")
			var clip_time := minf(lead_age/lead_step_duration,1.0)*lead_arm_clip.length
			var edited := lead_arm_clip.rotation_track_interpolate(track,clip_time)
			var blend := smoothstep(0.0,0.035,lead_age)*(1.0-smoothstep(lead_time,lead_time+0.10,elapsed))
			pose[bone].basis = Basis(pose[bone].basis.get_rotation_quaternion().slerp(edited,blend))
	rig.set_bone_pose_position(pelvis,pose[pelvis].origin)
	var entry := 1.0-smoothstep(0.0,0.085,elapsed)
	for bone in rig.get_bone_count():
		var rotation: Quaternion = pose[bone].basis.get_rotation_quaternion()
		if entry > 0.0 and entry_leg_rotations.has(bone):
			rotation = rotation.slerp(entry_leg_rotations[bone],entry)
		rig.set_bone_pose_rotation(bone,rotation)
