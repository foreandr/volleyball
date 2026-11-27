extends Node3D

const HOME_KEYS := ["stance","defender_1","defender_2"]
const DEFAULT_STANCES := [Vector3(-2.433,.052,-2.589),Vector3(.105,.052,-2.544),Vector3(2.69,.052,-2.537)]
const Regions = preload("res://scripts/reception_regions.gd")
const REGION_14 := Vector3i(1,1,1)
const REGION_20 := Vector3i(1,0,2)
const REGION_22 := Vector3i(0,1,2)
const REGION_24 := Vector3i(2,1,2)
const REGION_23 := Vector3i(1,1,2)
const HEAD_CELL := Vector3i(1,2,1)
const MAP_MIN := Vector3i.ZERO
const MAP_MAX := Vector3i(2,2,2)
const CELL_SIZE := Vector3(1.10,2.20/3.,1.10)
const MAP_ORIGIN := Vector3(-1.5,0,-1.5)*CELL_SIZE
var intercept_shift := Vector3.ZERO
var shift_frame := 0.
var reach_adjustment := Vector3.ZERO
var receiving := 0
var defenders: Array[Node3D]=[]
const HandPass = preload("res://scripts/hand_setting_pose.gd")
const HAND_RADIUS := .28
const RECEPTION_CAPSULES := [
	["hand_l","middle_03_l",.055], ["hand_r","middle_03_r",.055],
	["lowerarm_l","hand_l",.085], ["lowerarm_r","hand_r",.085],
	["upperarm_l","lowerarm_l",.095], ["upperarm_r","lowerarm_r",.095],
	["spine_03","upperarm_l",.105], ["spine_03","upperarm_r",.105],
]
const BALL_RADIUS := .105
const FOREARM_CONTACT_GRACE := .02
var incoming_lead_seconds := 0.
var set_intercept := Vector3.ZERO
var approach_plant := preload("res://scripts/setter_jump.gd").new()
var shuffle_by_actor := {}
var posed_lead_foot := "Auto"
const Dive = preload("res://scripts/forward_reception_dive.gd")
const Save = preload("res://scripts/player_reception_save.gd")
var player
var entry_pose: Array[Transform3D]=[]
var entry_frame := 0.
var entry_duration := 0.
var entry_position := Vector3.ZERO
var ready_pose: Array[Transform3D]=[]
var clasp: Array[Transform3D]=[]
var clips: Array=[]
var index := 1
const FOREARM = preload("res://assets/animations/straight_pass_02.res")
var legs := 1
var forearm_frames := {}
const ForearmDrive = preload("res://scripts/reception_pass_drive.gd")
var upper_bones: Array[int]=[]
var pass_goal := Vector3.ZERO
var pass_rise := 1.5
var feed_kmh := 100.

func reception_recipe(c: Dictionary,address: Vector3i,part: int) -> Dictionary:
	if Regions.movement(c) and early_platform(address):
		c=c.duplicate()
		c.platform_front_m=.60
		if address==REGION_14: c.grounded_platform=true
		if address==REGION_14 and part%4<2:
			c.backward_step=true
			c.entry_plant_m=.52
			c.entry_time=.18
			c.entry_speed=2.9
	if c.id==21 and address.y==0 and address.z==2:
		c=c.duplicate()
		c.side*=1.20
		c.forward*=1.12
		c.drop+=.16
		c.stack_knee=true
		c.entry_time=.23
		c.entry_speed=2.65
		c.entry_plant_m=.60
		c.contact_lean_deg=19.
	return c

func early_platform(address: Vector3i) -> bool:
	return address==REGION_14 or (address.y==0 and address.z==1 and address.x!=1)

func reception_segment(rig: Skeleton3D, shape: Array) -> PackedVector3Array:
	var start := rig.get_bone_global_pose(rig.find_bone(shape[0])).origin
	var end := rig.get_bone_global_pose(rig.find_bone(shape[1])).origin
	return PackedVector3Array([rig.to_global(start),rig.to_global(end)])

func zone_interval(start: Vector3,finish: Vector3,bounds: AABB) -> Vector2:
	var interval := Vector2(0.,1.)
	var travel := finish-start
	for axis in 3:
		if is_zero_approx(travel[axis]):
			if start[axis]<bounds.position[axis] or start[axis]>bounds.end[axis]: return Vector2.ZERO
			continue
		var a := (bounds.position[axis]-start[axis])/travel[axis]
		var b := (bounds.end[axis]-start[axis])/travel[axis]
		interval.x=maxf(interval.x,minf(a,b))
		interval.y=minf(interval.y,maxf(a,b))
		if interval.x>=interval.y: return Vector2.ZERO
	return interval

func sample_receiver(c: Dictionary,f: float,active := true,motion_legs := -2) -> void:
	pose_receiver(c,f,active,motion_legs)
	var weight := smoothstep(shift_frame-30.,shift_frame,f)*(1.-smoothstep(shift_frame+4.,shift_frame+32.,f))
	player.global_position+=intercept_shift*weight
	var rig: Skeleton3D=player.skeleton
	var lift := 0.
	for joint in ["foot_l","foot_r","ball_l","ball_r","calf_l","calf_r","pelvis","hand_l","hand_r","Head"]:
		var bone := rig.find_bone(joint)
		if bone<0: continue
		var radius := .055 if joint.begins_with("foot") or joint.begins_with("calf") else .035
		var height := rig.to_global(rig.get_bone_global_pose(bone).origin).y
		lift=maxf(lift,.04+radius-height)
	player.global_position.y+=lift

	if not entry_pose.is_empty() and f<entry_frame+entry_duration:
		var blend := smoothstep(entry_frame,entry_frame+entry_duration,f)
		for bone in entry_pose.size():
			rig.set_bone_pose(bone,entry_pose[bone].interpolate_with(rig.get_bone_pose(bone),blend))
		player.position=entry_position.lerp(player.position,blend)

func pose_receiver(c: Dictionary,f: float,active: bool,motion_legs: int) -> void:
	sample_receiver_base(c,f,active,motion_legs)
	if not active or c.kind=="overhead": return
	var age := (f-float(c.contact))/60.
	var bend := ForearmDrive.forearm_bend_degrees(feed_kmh/3.6)
	ForearmDrive.recoil_platform(player.skeleton,age,bend)
	var blend := smoothstep(-.48,-.065,age)*(1.-smoothstep(.09,.32,age))
	if blend<=0.: return
	var rig: Skeleton3D=player.skeleton
	var goal := rig.to_local(set_intercept)
	# Turn the lower chest into the feed, then aim both shoulders as one platform.
	for joint in ["spine_02","spine_03"]:
		var bone := rig.find_bone(joint)
		var chest := rig.get_bone_global_pose(bone)
		var platform := Vector3.ZERO
		for side in ["l","r"]:
			var segment := reception_segment(rig,["lowerarm_"+side,"hand_"+side])
			platform+=rig.to_local(segment[0].lerp(segment[1],.68))*.5
		var reach := platform-chest.origin
		var toward := goal-chest.origin
		var limit := deg_to_rad(17. if c.get("platform_swing",false) else 9.)
		if joint=="spine_02":
			reach=reach.slide(Vector3.UP)
			toward=toward.slide(Vector3.UP)
			limit=deg_to_rad(38. if c.get("platform_swing",false) else 24.)
			var lean_axis := Vector3.UP.cross(toward)
			if lean_axis.length_squared()>.000001:
				var lean := deg_to_rad(float(c.get("contact_lean_deg",3.)))*smoothstep(.12,.8,toward.length())*blend
				var lean_local := (chest.basis.inverse()*lean_axis).normalized()
				rig.set_bone_pose_rotation(bone,rig.get_bone_pose_rotation(bone)*Quaternion(lean_local,lean))
				chest=rig.get_bone_global_pose(bone)
		var axis := reach.cross(toward)
		if axis.length_squared()<.0000001: continue
		var angle := minf(limit,reach.angle_to(toward))*blend
		var local_axis := (chest.basis.inverse()*axis).normalized()
		rig.set_bone_pose_rotation(bone,rig.get_bone_pose_rotation(bone)*Quaternion(local_axis,angle))

	if c.has("left_shoulder_forward_deg"):
		var chest_id := rig.find_bone("spine_03")
		var chest_pose := rig.get_bone_global_pose(chest_id)
		var turn_axis := (chest_pose.basis.inverse()*Vector3.UP).normalized()
		rig.set_bone_pose_rotation(chest_id,rig.get_bone_pose_rotation(chest_id)*Quaternion(turn_axis,-deg_to_rad(float(c.left_shoulder_forward_deg))*blend))
	if Regions.movement(c):
		var chest_id := rig.find_bone("spine_03")
		var shoulder_line := rig.get_bone_global_pose(rig.find_bone("upperarm_l")).origin-rig.get_bone_global_pose(rig.find_bone("upperarm_r")).origin
		var mid := (rig.get_bone_global_pose(rig.find_bone("hand_l")).origin+rig.get_bone_global_pose(rig.find_bone("hand_r")).origin)*.5
		var world_across := (rig.global_basis*shoulder_line).normalized()
		var offset := (set_intercept-rig.to_global(mid)).dot(world_across)
		var drop := float(c.get("left_shoulder_drop_deg",signf(offset)*20.*smoothstep(.04,.50,absf(offset))))
		if c.has("reach_shoulder_drop_deg"):
			var lateral := absf(defenders[receiving].to_local(set_intercept).x)
			# Target the final shoulder slope, accounting for the lean already in the lunge.
			var slope := asin(clampf(shoulder_line.normalized().y,-1.,1.))
			drop=rad_to_deg(slope)-float(c.reach_shoulder_drop_deg)*smoothstep(.15,.85,lateral)
		if c.has("inside_shoulder_drop_deg"):
			var neutral_line := rig.get_bone_global_rest(rig.find_bone("upperarm_l")).origin-rig.get_bone_global_rest(rig.find_bone("upperarm_r")).origin
			var leftward := (rig.global_basis*neutral_line).slide(Vector3.UP).normalized()
			var reach := (set_intercept-defenders[receiving].global_position).dot(leftward)
			var desired_slope := signf(reach)*float(c.inside_shoulder_drop_deg)*smoothstep(.12,.85,absf(reach))
			drop=rad_to_deg(asin(clampf(shoulder_line.normalized().y,-1.,1.)))-desired_slope
		var roll_axis := shoulder_line.cross(Vector3.DOWN).normalized()
		var local_axis := (rig.get_bone_global_pose(chest_id).basis.inverse()*roll_axis).normalized()
		rig.set_bone_pose_rotation(chest_id,rig.get_bone_pose_rotation(chest_id)*Quaternion(local_axis,deg_to_rad(drop)*blend))
	if Regions.movement(c):
		var head := rig.find_bone("Head")
		var parent := rig.get_bone_global_pose(rig.get_bone_parent(head)).basis.orthonormalized()
		var forward_head := Basis(Vector3.RIGHT,deg_to_rad(float(c.get("chin_tuck_deg",12.))))*rig.get_bone_global_rest(head).basis.orthonormalized()
		var target := (parent.inverse()*forward_head).get_rotation_quaternion()
		rig.set_bone_pose_rotation(head,rig.get_bone_pose_rotation(head).slerp(target,blend))
	if Regions.movement(c):
		# A shared rotation around the shoulder line keeps the clasp and elbow angles intact.
		var left := rig.find_bone("upperarm_l")
		var right := rig.find_bone("upperarm_r")
		var a := rig.get_bone_global_pose(left).origin
		var b := rig.get_bone_global_pose(right).origin
		var hinge := (b-a).normalized()
		var wrists := (rig.get_bone_global_pose(rig.find_bone("hand_l")).origin+rig.get_bone_global_pose(rig.find_bone("hand_r")).origin)*.5
		var current := (wrists-(a+b)*.5).slide(hinge)
		var platform_goal := goal
		if c.has("platform_front_m"):
			var forward := (rig.global_basis.inverse()*defenders[receiving].global_basis.z).normalized()
			var margin := float(c.platform_front_m)-(platform_goal-(a+b)*.5).dot(forward)
			platform_goal+=forward*maxf(0.,margin)
		if c.get("grounded_platform",false):
			var world_goal := rig.to_global(platform_goal)
			world_goal.y=minf(world_goal.y,rig.to_global((a+b)*.5).y-.32)
			platform_goal=rig.to_local(world_goal)
		var desired := (platform_goal-(a+b)*.5).slide(hinge)
		if current.length_squared()>.000001 and desired.length_squared()>.000001:
			var swing := clampf(current.signed_angle_to(desired,hinge),-PI/3.,PI/3.)*blend
			var wrist_height := rig.to_global(wrists).y
			if not c.has("platform_front_m"): swing*=1.-.45*smoothstep(0.,.35,set_intercept.y-wrist_height)
			for shoulder in [left,right]:
				var axis := (rig.get_bone_global_pose(shoulder).basis.inverse()*hinge).normalized()
				rig.set_bone_pose_rotation(shoulder,rig.get_bone_pose_rotation(shoulder)*Quaternion(axis,swing))

func sample_receiver_base(c: Dictionary,f: float,active: bool,motion_legs: int) -> void:
	if motion_legs==-2: motion_legs=legs
	if not active:
		sample_layer(-1,c,f)
		return
	if c.kind=="overhead":
		sample_layer(-1,c,f)
		var goal := set_intercept
		var offset := pass_goal-goal
		var lift := sqrt(2.*9.81*pass_rise)
		var flight := (lift+sqrt(lift*lift+2.*9.81*maxf(0.,goal.y-.145)))/9.81
		var push := (offset.slide(Vector3.UP)/flight+Vector3.UP*lift).normalized()
		var follow := (f-float(c.contact))/60.
		var load_weight := smoothstep(-HandPass.CPU_PREP_LEAD,0.,follow)
		var rig: Skeleton3D=player.skeleton
		var forehead := rig.to_global(rig.get_bone_global_pose(rig.find_bone("Head")).origin).y+.12
		var jump_set: bool=not c.has("step_legs") and (c.get("jump_set",false) or goal.y>forehead+.10)
		if jump_set:
			jump_to_set(goal,follow,c.get("approach_step",false))
			lean_for_hand_pass(goal,load_weight*(1.-smoothstep(.035,.28,follow)),deg_to_rad(5.))
		else:
			if c.get("audition",false):
				if motion_legs>=0: audition_hand_legs(goal,follow,motion_legs)
			elif c.get("step_legs",0)==2:
				grounded_wide_set(goal,forehead,follow,c.get("ground_plant",false))
			else:
				pose_hand_pass_legs(goal,forehead,follow,int(c.get("step_legs",0)))
			var reach_weight := load_weight*(1.-smoothstep(.035,.28,follow))
			lean_for_hand_pass(goal,reach_weight)
		if follow<0.:
			HandPass.standing_set(player,goal,offset,push,follow,load_weight,Vector3.ZERO,jump_set)
		else:
			var delay := HandPass.RELEASE_TIME
			var extension := HandPass.release_extension(follow,delay)
			HandPass.apply(player,goal,HandPass.follow_weight(follow),push*.23*extension,
				HandPass.release_cushion(follow,delay),smoothstep(delay,delay+.10,follow),
				false,Vector3.ZERO,extension,offset,smoothstep(0.,delay,follow),true,
				smoothstep(0.,delay+HandPass.FRONT_WRIST_FOLLOW_TIME,follow),null,Vector3.ZERO,jump_set)
		return
	if not Regions.movement(c):
		sample_layer(motion_legs,c,f)
		return
	var max_shift := float(c.get("entry_plant_m",clips[motion_legs].get("entry_plant_m",0.))) if motion_legs>=0 else 0.
	var shift := Vector3.ZERO
	var progress := 0.
	var leg_frame := f
	if max_shift>0.:
		var goal: Vector3=defenders[receiving].to_local(set_intercept).slide(Vector3.UP)
		var gap := goal-Vector3.BACK*.48
		if c.get("backward_step",false): gap=Vector3(clampf(goal.x,-.18,.18),0.,minf(-.54,goal.z-.95))
		var available := minf(float(c.contact)/60.,incoming_lead_seconds)
		var window := clampf(available-.20,0.,float(c.get("entry_time",approach_plant.APPROACH_LOAD_TIME)))
		var distance := minf(max_shift,minf(maxf(0.,gap.length()-.30),window*float(c.get("entry_speed",1.35))))
		if distance>.025:
			var start := float(c.contact)-available*60.
			var plant := start+window*60.
			progress=clampf(inverse_lerp(start,plant,f),0.,1.)
			shift=gap.normalized()*distance
			if f<c.contact: leg_frame=float(c.contact)*clampf(inverse_lerp(plant,c.contact,f),0.,1.)
	sample_layer(motion_legs,c,leg_frame)
	if not shift.is_zero_approx():
		player.position+=shift*smoothstep(0.,1.,progress)
		if progress>0. and progress<1.:
			sample_approach_plant(shift,(progress-1.)*approach_plant.APPROACH_LOAD_TIME)
	var contact := float(FOREARM.get_meta("contact_time"))
	var time := remap(f,0.,c.contact,0.,contact) if f<=c.contact else remap(f,c.contact,c.get("source_end",c.frames),contact,FOREARM.length)
	var key := roundi(time*60.)
	if not forearm_frames.has(key):
		forearm_frames[key]=Save.sample_clip(player.skeleton,FOREARM,minf(key/60.,FOREARM.length))
	var settle: float=c.frames-3. if c.has("source_end") else c.frames
	var weight := smoothstep(0.,5.,f)*(1.-smoothstep(settle-6.,settle,f))
	for bone in upper_bones:
		player.skeleton.set_bone_pose(bone,ready_pose[bone].interpolate_with(forearm_frames[key][bone],weight))


func lean_for_hand_pass(goal: Vector3, weight: float, limit := deg_to_rad(34.)) -> void:
	if weight<=0.: return
	var rig: Skeleton3D=player.skeleton
	var author=player.get_pose_author()
	var pose: Array[Transform3D]=[]
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var head: Vector3=author.point(pose,"Head")
	var reach := (rig.to_local(goal)-head-Vector3(0,.12,.20)).slide(Vector3.UP)
	if reach.length_squared()<.0001: return
	var axis := Vector3.UP.cross(reach).normalized()
	var lean := minf(limit,reach.length()*1.12)*weight
	for spine in ["spine_01","spine_02","spine_03"]:
		author.rotate_world(pose,spine,axis,lean/3.)
		var id := rig.find_bone(spine)
		rig.set_bone_pose(id,pose[id])

func jump_to_set(goal: Vector3, follow: float, approach_step := false) -> void:
	var rig: Skeleton3D=player.skeleton
	var head := rig.to_global(rig.get_bone_global_pose(rig.find_bone("Head")).origin)
	var pocket: Vector3=head+player.global_basis.z.normalized()*.23+Vector3.UP*.16
	var gap := goal-pocket
	var apex := clampf(gap.y+.10,.19,.76)
	# Allow enough flight time to cover the horizontal gap as well as the rise.
	var contact_rise := clampf(gap.y,.035,apex)
	var descent := sqrt(2.*(apex-contact_rise)/9.81)
	var lead := maxf(sqrt(2.*apex/9.81)+descent,minf(.52,gap.slide(Vector3.UP).length()/4.8))
	var upward_speed := contact_rise/lead+4.905*lead
	var half_air := upward_speed/9.81
	apex=upward_speed*upward_speed/(2.*9.81)
	var t := follow+lead
	var travel: Vector3=player.global_basis.inverse()*gap.slide(Vector3.UP)
	# Limit backward launch velocity so even the landing stays near takeoff.
	if travel.z<0.: travel.z=clampf(travel.z+.05,-.20*lead/(2.*half_air),0.)
	var fraction := clampf(t,0.,2.*half_air)/lead
	var landing := 2.*half_air-lead
	var recover := smoothstep(landing+.10,landing+.57,follow)
	var ground_step := (travel*.60).limit_length(.62) if approach_step else Vector3.ZERO
	var step_progress := smoothstep(-approach_plant.APPROACH_LOAD_TIME,0.,t)
	var offset := ground_step*step_progress+(travel-ground_step).limit_length(5.5*lead)*fraction
	player.position=offset
	player.position.y=maxf(0.,apex-4.905*(t-half_air)*(t-half_air))
	var load := smoothstep(-.32,-.085,t)*(1.-smoothstep(-.085,.07,t))
	var compression := clampf(contact_rise-gap.y,0.,.38)*smoothstep(-.16,0.,t)*(1.-recover)
	var cushion := smoothstep(landing,landing+.06,follow)*(1.-smoothstep(landing+.06,landing+.20,follow))
	bend_for_hand_pass(compression+.17*load+.10*cushion)
	if approach_step and t>=-approach_plant.APPROACH_LOAD_TIME and t<0.:
		sample_approach_plant(ground_step,t)
	# Hold the landing before the studio shuffles back for its next feed.
	var elapsed := follow-landing-.40
	var distance := offset.length()
	if elapsed<=0. or distance<.001: return
	var duration := maxf(.38,distance/1.15)
	var progress := clampf(elapsed/duration,0.,1.)
	player.position=offset*(1.-smoothstep(0.,1.,progress))
	if progress>=1.: return
	sample_shuffle(-offset.normalized(),progress*maxi(1,roundi(duration*1.65)),smoothstep(0.,.16,progress)*(1.-smoothstep(.80,1.,progress)))

func sample_approach_plant(stride: Vector3, takeoff_time: float) -> void:
	var rig: Skeleton3D=player.skeleton
	var author=player.get_pose_author()
	var pose := ready_pose.duplicate()
	var pelvis := rig.find_bone("pelvis")
	pose[pelvis]=rig.get_bone_pose(pelvis)
	# Sample the attack's right plant and closing left step in takeoff-space.
	approach_plant.approach_plant=true
	approach_plant.incoming_plant_speed=1.
	approach_plant.elapsed=takeoff_time+approach_plant.APPROACH_LOAD_TIME
	for side in ["r","l"]:
		approach_plant.plant_legs[side]=Transform3D.IDENTITY
	approach_plant.right_plant=stride
	approach_plant.left_plant=stride
	for side in ["r","l"]:
		var foot: Transform3D=author.feet[side]
		var displacement: Vector3=approach_plant.attack_plant_foot(side)-player.position
		var target: Vector3=foot.origin+rig.global_basis.inverse()*(player.global_basis*displacement)
		var pole := Vector3(.15 if side=="l" else -.15,.08,1.)
		author.limb(pose,"thigh_"+side,"calf_"+side,"foot_"+side,target,pole,1.,162.,true)
		author.set_world_basis(pose,"foot_"+side,foot.basis)
		for joint in ["thigh_","calf_","foot_"]:
			var bone := rig.find_bone(joint+side)
			rig.set_bone_pose(bone,pose[bone])

func sample_shuffle(direction: Vector3, phase: float, weight: float) -> void:
	if not shuffle_by_actor.has(player):
		shuffle_by_actor[player]=preload("res://scripts/directional_footwork.gd").new(player)
	var steps=shuffle_by_actor[player]
	# Sample from replay time so stepping backwards reproduces the same feet.
	steps.phase=phase
	steps.travel=direction
	steps.weight=weight
	steps.step(steps.travel,0.,1.,true,true)

func grounded_wide_set(goal: Vector3, forehead: float, follow: float, plant: bool) -> void:
	var stride := Vector3.ZERO
	var settle := -.30
	if plant:
		var travel: Vector3=player.to_local(goal).slide(Vector3.UP)-Vector3.BACK*.23
		stride=(travel*.72).limit_length(.92)
		var phase := follow-settle
		player.position=stride*smoothstep(-approach_plant.APPROACH_LOAD_TIME,0.,phase)
		if phase<0.:
			if phase>=-approach_plant.APPROACH_LOAD_TIME:
				bend_for_hand_pass(.12*sin(PI*smoothstep(-approach_plant.APPROACH_LOAD_TIME,0.,phase)))
				sample_approach_plant(stride,phase)
			return
	var weight := smoothstep(settle if plant else -.55,-.02,follow)*(1.-smoothstep(.09,.38,follow))
	if weight>0.:
		var delta_to_ball: Vector3=player.to_local(goal).slide(Vector3.UP)-Vector3.BACK*.23
		var recipe: Dictionary=clips[1].duplicate()
		var scale_m: float=player.skeleton.global_basis.x.length()
		var reach := delta_to_ball.limit_length(1.1)
		recipe.side=reach.x/scale_m
		recipe.forward=reach.z*1.8/scale_m
		recipe.drop=clampf(forehead-goal.y,0.,float(recipe.drop)*scale_m)/scale_m
		var pose := ready_pose.duplicate()
		Regions.legs(player,pose,recipe,weight)
		for joint in ["pelvis","thigh_l","calf_l","foot_l","thigh_r","calf_r","foot_r"]:
			var bone: int=player.skeleton.find_bone(joint)
			player.skeleton.set_bone_pose(bone,pose[bone])
	if plant and follow>.4:
		var duration := maxf(.38,stride.length()/1.15)
		var progress := clampf((follow-.4)/duration,0.,1.)
		player.position=stride*(1.-smoothstep(0.,1.,progress))
		if progress<1.:
			sample_shuffle(-stride.normalized(),progress*maxi(1,roundi(duration*1.65)),sin(PI*progress))

func pose_hand_pass_legs(goal: Vector3, standing_height: float, follow: float, step_legs: int) -> void:
	var drop := standing_height-goal.y
	if step_legs==0 and drop < -.10:
		var height := clampf(-drop-.06,.04,.38)
		var half_flight := sqrt(2.*height/9.81)
		var rise := maxf(0.,height-4.905*follow*follow)
		var drift: Vector3=player.to_local(goal).slide(Vector3.UP)-Vector3(0,0,.20)
		player.position+=drift.limit_length(.32)*(rise/height)
		player.position.y=rise
		var before := smoothstep(-half_flight-.19,-half_flight-.09,follow)*(1.-smoothstep(-half_flight-.09,-half_flight,follow))
		var after := smoothstep(half_flight,half_flight+.08,follow)*(1.-smoothstep(half_flight+.08,half_flight+.22,follow))
		bend_for_hand_pass(.10*(before+after))
		return
	var weight := smoothstep(-.36,-.025,follow)*(1.-smoothstep(.035,.32,follow))
	if weight<=0.: return
	var lateral: float=player.to_local(goal).x
	var recipe_id := 6 if drop>.26 else 4
	if drop>.12 and absf(lateral)>.20: recipe_id=7
	if step_legs>0: recipe_id=step_legs
	var recipe: Dictionary=clips[recipe_id-1].duplicate()
	var scale_m: float=player.skeleton.global_basis.x.length()
	recipe.side=minf(absf(lateral)*.55,.15)/scale_m if recipe_id==7 else 0.
	var depth_offset: float=player.to_local(goal).z-.20
	recipe.forward=clampf(depth_offset,-.65,.50)/scale_m
	recipe.drop=minf(float(recipe.drop)+.15,maxf(0.,drop)/scale_m)
	if step_legs>0:
		recipe.side=clampf(absf(lateral)*.8,.015,.38)/scale_m
		recipe.forward=clampf(depth_offset*2.,.12,1.35)/scale_m
	var pose := ready_pose.duplicate()
	Regions.legs(player,pose,recipe,weight,lateral<0.)
	for joint in ["pelvis","thigh_l","calf_l","foot_l","thigh_r","calf_r","foot_r"]:
		var bone: int=player.skeleton.find_bone(joint)
		player.skeleton.set_bone_pose(bone,pose[bone])

func audition_hand_legs(goal: Vector3, follow: float, motion_legs: int) -> void:
	var clip: Dictionary=clips[motion_legs]
	var target: Vector3=player.to_local(goal).slide(Vector3.UP)
	var direction := target.normalized()
	var stride := Vector2(clip.side,clip.forward).length()
	var recipe := clip.duplicate()
	recipe.side=direction.x*stride
	recipe.forward=direction.z*stride
	var weight := smoothstep(-float(clip.contact)/60.,0.,follow)*(1.-smoothstep(.10,float(clip.frames-clip.contact)/60.,follow))
	var pose := ready_pose.duplicate()
	Regions.legs(player,pose,recipe,weight)
	player.position.y=float(clip.get("jump",0.))*weight
	for joint in ["pelvis","thigh_l","calf_l","foot_l","thigh_r","calf_r","foot_r"]:
		var bone: int=player.skeleton.find_bone(joint)
		player.skeleton.set_bone_pose(bone,pose[bone])

func bend_for_hand_pass(depth: float) -> void:
	if depth<=.00001: return
	var rig: Skeleton3D=player.skeleton
	var author=player.get_pose_author()
	var pose := ready_pose.duplicate()
	var pelvis := rig.find_bone("pelvis")
	var parent: Transform3D=author.world_pose(pose,rig.get_bone_parent(pelvis))
	pose[pelvis].origin+=parent.basis.inverse()*rig.global_basis.inverse()*(Vector3.DOWN*depth)
	rig.set_bone_pose(pelvis,pose[pelvis])
	for side in ["l","r"]:
		var hip: String = "thigh_"+side
		var knee: String = "calf_"+side
		var ankle: String = "foot_"+side
		var foot: Transform3D=author.world_pose(ready_pose,rig.find_bone(ankle))
		var axis: Vector3=(foot.origin-author.point(ready_pose,hip)).normalized()
		var pole: Vector3=(author.point(ready_pose,knee)-author.point(ready_pose,hip)).slide(axis).normalized()
		author.limb(pose,hip,knee,ankle,foot.origin,pole)
		var ankle_id := rig.find_bone(ankle)
		var shin: Transform3D=author.world_pose(pose,rig.get_bone_parent(ankle_id))
		pose[ankle_id]=shin.affine_inverse()*foot
		for joint in [hip,knee,ankle]:
			var bone := rig.find_bone(joint)
			rig.set_bone_pose(bone,pose[bone])

func sample_layer(which: int, timeline: Dictionary, f: float) -> void:
	if which<0:
		player.position=Vector3.ZERO
		player.rotation.y=0.
		for bone in ready_pose.size(): player.skeleton.set_bone_pose(bone,ready_pose[bone])
		return
	var c: Dictionary=timeline if timeline.id==clips[which].id else clips[which]
	if which!=index:
		if f<=timeline.contact: f=f*c.contact/timeline.contact
		else: f=remap(f,timeline.contact,timeline.frames,c.contact,c.frames)
	var source_end: float=minf(c.get("source_end",c.frames),c.frames)
	var weight := smoothstep(5.,c.contact,f)*(1.-smoothstep(c.contact+6.,source_end-8.,f))
	if weight<=0.:
		player.position=Vector3.ZERO
		player.rotation.y=0.
		for bone in ready_pose.size(): player.skeleton.set_bone_pose(bone,ready_pose[bone])
		return
	var author=player.get_pose_author()
	var rig: Skeleton3D=player.skeleton
	player.position=Vector3.ZERO
	player.rotation.y=0.
	if c.kind in ["dive","wide_dive","pancake"] and weight>.0001:
		var dir := Vector3(c.side,0,c.forward).normalized()
		var t: float = Dive.WINDUP*clampf((f-5.)/(c.contact-5.),0.,1.)+maxf(0.,f-c.contact)/(c.frames-c.contact-8.)*(Dive.DURATION-Dive.WINDUP)
		player.pose_reception_dive(ready_pose,clasp,Vector3.ZERO,dir,t,dir*(c.forward+.55)+Vector3.UP*.30,Dive.WINDUP+.05,c.kind=="pancake",c.forward+.25,true,"r" if c.kind=="wide_dive" else "")
		var recovery := smoothstep(c.frames-32.,c.frames-8.,f)
		player.position*=1.-recovery
		player.rotation.y*=1.-recovery
		for bone in ready_pose.size():
			rig.set_bone_pose(bone,rig.get_bone_pose(bone).interpolate_with(ready_pose[bone],maxf(recovery,1.-smoothstep(5.,15.,f))))
		return
	var pose: Array=ready_pose.duplicate()
	var direction: Vector3=player.to_local(set_intercept).slide(Vector3.UP).normalized()
	var stride := Vector2(c.side,c.forward).length()
	c=c.duplicate()
	c.lead_foot=posed_lead_foot
	c.side=direction.x*stride+reach_adjustment.x/.65
	c.forward=direction.z*stride+reach_adjustment.z/.34
	c.drop=maxf(0.,float(c.drop)-reach_adjustment.y)
	Regions.legs(player,pose,c,weight)
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,deg_to_rad(c.lean)*weight*.65)
	author.rotate_world(pose,"spine_03",Vector3.RIGHT,deg_to_rad(c.lean)*weight*.35)
	author.rotate_world(pose,"spine_02",Vector3.BACK,-c.side*.36*weight)
	var chest: Vector3=author.point(pose,"spine_03")
	player.position.y=float(c.get("jump",0.))*weight
	for bone in pose.size(): rig.set_bone_pose(bone,pose[bone])

func region_parts(address: Vector3i) -> int:
	if address==REGION_24: return 4
	if address==REGION_22: return 8
	if address==REGION_23: return 0
	if address==REGION_20 or halves_only(address): return 2
	if depth_split(address): return 8
	return 4 if is_subdivided(address) else 1

func is_subdivided(address: Vector3i) -> bool:
	return address==REGION_20 or address==REGION_24 or address==REGION_22 or address==REGION_23 or (address.y==2 and address.z>=1) or depth_split(address)

func halves_only(address: Vector3i) -> bool:
	return address.y==2 and address.z==2 and address.x!=1

func depth_split(address: Vector3i) -> bool:
	return address==Vector3i(1,1,1) or address==Vector3i(1,2,2)

func region_suffix(address: Vector3i,part: int) -> String:
	if address==REGION_20: return ".left" if part==0 else ".right"
	if address==REGION_24: return [".top.near",".bottom.near",".bottom.far",".top.far"][part]
	if address==REGION_22: return [".top.left.far",".bottom.left.near",".bottom.right.left",".bottom.left.far",".top.left.near",".top.right.left",".top.right.right",".bottom.right.right"][part]
	if address==REGION_23: return [".back.top",".front.top",".back.bottom",".front.bottom"][part]
	if depth_split(address):
		return ".%d.%s" % [part%4+1,"front" if part>=4 else "back"]
	return "."+str(part+1) if is_subdivided(address) else ""

func region_number(address: Vector3i,part: int) -> String:
	if address==REGION_22: return "22-23"+region_suffix(address,part)
	return str(1+address.x+3*address.y+9*address.z)+region_suffix(address,part)

func region_size(address: Vector3i,part: int) -> Vector3:
	if address==REGION_20: return CELL_SIZE*Vector3(.5,1.,1.)
	if address==REGION_22: return CELL_SIZE*Vector3(.5,.5,1.)
	if address==REGION_24: return CELL_SIZE*Vector3(.5,.5,1.)
	if address==REGION_23: return CELL_SIZE*Vector3(1.,.5,.5)
	if halves_only(address): return CELL_SIZE*Vector3(1.,.5,1.)
	if depth_split(address): return CELL_SIZE*Vector3(.5,.5,.5)
	return CELL_SIZE*Vector3(.5,.5,1.) if is_subdivided(address) else CELL_SIZE

func region_center(address: Vector3i,part: int,subdivide := true) -> Vector3:
	var center := MAP_ORIGIN+(Vector3(address)+Vector3.ONE*.5)*CELL_SIZE
	if address==REGION_22:
		center.x+=.5*CELL_SIZE.x
		if subdivide:
			center.y+=(.25 if part in [0,4,5,6] else -.25)*CELL_SIZE.y
			center.x+=[-.75,-.25,.25,-.75,-.25,.25,.75,.75][part]*CELL_SIZE.x
	elif address==REGION_20 and subdivide:
		center.x+=(-.25 if part==0 else .25)*CELL_SIZE.x
	elif address==REGION_24 and subdivide:
		center.y+=(.25 if part in [0,3] else -.25)*CELL_SIZE.y
		center.x+=(-.25 if part in [0,1] else .25)*CELL_SIZE.x
	elif halves_only(address) and subdivide:
		center.y+=(.25 if part==0 else -.25)*CELL_SIZE.y
	elif is_subdivided(address) and subdivide:
		var upper := part%4<2
		center+=Vector3(-.25 if part%2==0 else .25,.25 if upper else -.25,0.)*CELL_SIZE
		if depth_split(address):
			center.z+=(.25 if part>=4 else -.25)*CELL_SIZE.z
	return center

func assignment_key(address: Vector3i,part: int) -> String:
	return Regions.key(address)+region_suffix(address,part)

func assigned_action(address: Vector3i,part: int) -> int:
	var child_key := assignment_key(address,part)
	if is_subdivided(address):
		if StorySession.game_options.has_section_key("studio_three_rows",child_key):
			return int(StorySession.game_options.get_value("studio_three_rows",child_key))
		if address==REGION_14: return 4
		if address==REGION_20: return 21
		if address==REGION_22:
			if part in [2,7]: return 72
			if part==4: return 14
			if part in [5,6]: return 4
			if part in [0,3]: return 21
			var parent_suffix := ".top" if part in [0,4,5,6] else (".bottom.left" if part in [1,3] else ".bottom.right")
			return int(StorySession.game_options.get_value("studio_three_rows",Regions.key(address)+parent_suffix,72 if part==1 else 0))
		if address==REGION_24:
			if part in [1,2]: return assigned_action(REGION_22,1 if part==1 else 3)
			return int(StorySession.game_options.get_value("studio_three_rows",Regions.key(address)+".top",assigned_action(REGION_22,4 if part==0 else 0)))
		if address==Vector3i(1,2,2):
			if part<2: return 79
			var parent_key := Regions.key(address)+"."+str(part%4+1)
			if part%4<2:
				var parent_action := int(StorySession.game_options.get_value("studio_three_rows",parent_key,78))
				return 80 if parent_action==78 else parent_action
			if StorySession.game_options.has_section_key("studio_three_rows",parent_key):
				return int(StorySession.game_options.get_value("studio_three_rows",parent_key))
			return 82 if part>=4 else 81
		if address.x!=1:
			var upper := part==0 if halves_only(address) else part<2
			return 80 if upper else 82
		if address==HEAD_CELL and part>=2: return 79
	var key := Regions.key(address)
	if StorySession.game_options.has_section_key("studio_three_rows",key):
		return int(StorySession.game_options.get_value("studio_three_rows",key))
	if address.y==0 and address.z==1 and address.x!=1: return 21
	if address.y==2 and address.z==0: return 78
	if address.x!=1 and ((address.y==1 and address.z==1) or (address.y==0 and address.z==2)): return 21
	if address.y==1: return 0
	if address.z==0: return 0
	var previous := Vector3i(address.x,0 if address.y==0 else 1,address.z)
	var default_action := 10 if previous==Vector3i(1,1,1) else 0
	return int(StorySession.game_options.get_value("dig_regions",Regions.key(previous),default_action))

func default_mirror(address: Vector3i,part: int,clip: Dictionary) -> bool:
	if clip.is_empty(): return false
	if address==REGION_20: return (part==0)!=(float(clip.side)<0.)
	return address.x!=1 and ((address.x<1)!=(float(clip.side)<0.))

func lead_foot(address: Vector3i,part: int) -> String:
	var default_foot := "Auto"
	if address==REGION_20: default_foot="Right" if part==0 else "Left"
	if address==REGION_22 and part==2: default_foot="Right"
	if address==REGION_22 and part==7: default_foot="Left"
	return StorySession.game_options.get_value("studio_lead_foot",assignment_key(address,part),default_foot)


func bind_receiver(actor: Node3D) -> void:
	player=actor
	ready_pose.assign(player.get_pose_author().baseline)
	var rig: Skeleton3D=player.skeleton
	upper_bones.clear()
	forearm_frames.clear()
	var spine := rig.find_bone("spine_01")
	for bone in rig.get_bone_count():
		if bone==spine or rig.get_bone_parent(bone) in upper_bones:
			upper_bones.append(bone)
	var clip=preload("res://assets/animations/straight_pass_02.res")
	clasp=Save.sample_clip(player.skeleton,clip,clip.get_meta("contact_time"))
