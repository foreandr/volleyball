extends RefCounted

const HandPose = preload("res://scripts/hand_setting_pose.gd")
const Net = preload("res://scripts/net_collision.gd")
const Jump = preload("res://scripts/setter_jump.gd")
const STUFF_SPEED_RETENTION := 0.60
const MAX_CHEST_ABOVE_TAPE := .07

static func maximum_block_lift(player: Node3D) -> float:
	var rig:Skeleton3D=player.skeleton
	var chest:=rig.to_global(rig.get_bone_global_rest(rig.find_bone("spine_03")).origin)
	return maxf(0., Net.NET_TOP + MAX_CHEST_ABOVE_TAPE - chest.y)

static func loaded_height(full_height: float, depth: float) -> float:
	return full_height*lerpf(.60,1.,clampf(depth,0.,1.))

static func lateral_scale(seconds: float) -> float:
	var depth := clampf(seconds/preload("res://scripts/tryout_squat.gd").FULL_LOAD,0.,1.)
	return lerpf(.78,.42,depth)

static func bonus_height(player: Node3D, base_vertical: float) -> float:
	return base_vertical * 0.10 * clampf(player.effective_rating("Blocking") / 100.0, 0.0, 1.0)

const START := 0.16
const CPU_LEAD := .035
const AIR := 0.74
const BODY_RADII := [.1575,.09,.13225]
const BODY_PARTS := ["shoulder","neck","head"]
var body_chains := []

static func body_geometry(left: Vector3,right: Vector3,neck: Vector3,head: Vector3) -> Array:
	var up := neck.direction_to(head)
	return [[left,neck,head,head+up*.11],[right,neck]]

func body_hit(previous: Vector3,current: Vector3,ball_radius: float) -> Dictionary:
	var best := {}
	var nearest := INF
	for side in body_chains.size():
		var chain: Array=body_chains[side]
		for segment in chain.size()-1:
			var pair := Geometry3D.get_closest_points_between_segments(previous,current,chain[segment],chain[segment+1])
			var travel := previous.distance_squared_to(pair[0])
			if travel<nearest and pair[0].distance_to(pair[1])<=ball_radius+BODY_RADII[segment]:
				nearest=travel
				best={"point":pair[0],"part":BODY_PARTS[segment],"side":side if segment==0 else -1}
	return best

const ARM_RADII := [.085,.1425,.144]
const HEIGHT := 1.16
var actor: Node3D
var age := 0.0
var tempo := 1.0
var upper_body_rate := 1.0
var jump_height := HEIGHT
var landing_recovery := 0.13
var overpass_swing := false
var net_heading := INF
var swing_load := 0.
var square_block := false
var late_quick_x := INF
var aggressive_press := false
var track_near_ball := false
var kong_direction := 0.
var close_direction := 0.
var lean_input := 0.
var reach_input := Vector2.ZERO
var lean := 0.
var reach := Vector2.ZERO
var court_aim := Vector3.INF
var elbows: Array[Vector3] = []
var shoulders: Array[Vector3] = []
var min_hand_x := -INF
var max_hand_x := INF
var base: Vector3
var previous_hands: Array[Vector3] = []
var hands: Array[Vector3] = []
var wrists: Array[Vector3] = []
var previous_wrists: Array[Vector3] = []

# Cache the final skinning pose, including the joint-limit modifier.
var displayed_chains := []
var palm_faces: Array[Vector3]=[]

func capture_displayed_chains() -> void:
	var rig: Skeleton3D=actor.skeleton
	displayed_chains=[]
	palm_faces.clear()
	for side in ["l","r"]:
		var chain := []
		for bone in ["upperarm_","lowerarm_","hand_","middle_03_"]:
			chain.append(rig.get_bone_global_pose(rig.find_bone(bone+side)).origin)
		displayed_chains.append(chain)
		var across:=rig.get_bone_global_pose(rig.find_bone("index_01_"+side)).origin-rig.get_bone_global_pose(rig.find_bone("pinky_01_"+side)).origin
		var face:Vector3=(rig.global_basis*(chain[3]-chain[2]).cross(across)).normalized()
		if face.dot(actor.global_basis.z)<0.: face=-face
		palm_faces.append(face)
	displayed_chains.append([rig.get_bone_global_pose(rig.find_bone("neck_01")).origin,rig.get_bone_global_pose(rig.find_bone("Head")).origin])

func use_displayed_geometry() -> void:
	var rig: Skeleton3D=actor.skeleton
	if displayed_chains.size()==3 and hands.size()==2:
		for i in 2:
			shoulders[i]=rig.to_global(displayed_chains[i][0])
			elbows[i]=rig.to_global(displayed_chains[i][1])
			wrists[i]=rig.to_global(displayed_chains[i][2])
			hands[i]=rig.to_global(displayed_chains[i][3])
		body_chains=body_geometry(shoulders[0],shoulders[1],rig.to_global(displayed_chains[2][0]),rig.to_global(displayed_chains[2][1]))
	if not rig.skeleton_updated.is_connected(capture_displayed_chains):
		rig.skeleton_updated.connect(capture_displayed_chains,CONNECT_ONE_SHOT)

func first_block_touch(start:Vector3,finish:Vector3,ball_radius:float) -> Dictionary:
	var best:Dictionary={}
	for c in hands.size()+body_chains.size():
		var arm:=c<hands.size()
		var side:=c if arm else c-hands.size()
		var chain:Array=[shoulders[c],elbows[c],wrists[c],hands[c]] if arm else body_chains[side]
		for part in chain.size()-1:
			var radius:float=ARM_RADII[part] if arm else BODY_RADII[part]
			var hit:=first_capsule_touch(start,finish,chain[part],chain[part+1],ball_radius+radius)
			if hit.is_empty() or (not best.is_empty() and hit.fraction>=best.fraction): continue
			best=hit
			best.merge({"arm":arm,"side":side,"segment":part,"part":["upper arm","forearm","hand"][part] if arm else BODY_PARTS[part]})
	return best

func block_rebound(hit:Dictionary,incoming:Vector3,attack_direction:float) -> Dictionary:
	var normal:Vector3=hit.normal
	if normal.is_zero_approx(): normal=-incoming.normalized()
	var palm_contact:bool=hit.arm and hit.segment==2 and palm_faces.size()==2
	if palm_contact:
		var face:=palm_faces[int(hit.side)]
		if face.dot(normal)>.45 and incoming.dot(face)<0.: normal=face
	var reflection:=incoming.bounce(normal)
	var distal:bool=hit.arm and (hit.segment==2 or hit.segment==1 and hit.surface.distance_to(wrists[hit.side])<.14)
	var net:=preload("res://scripts/net_collision.gd")
	var stuff:bool=distal and -incoming.normalized().dot(normal)>.55 and hit.surface.y>net.NET_TOP+.10 and (hit.surface.z-net.NET_Z)*attack_direction<-.04
	var outgoing:=Vector3(reflection.x*.42,maxf(2.5,absf(reflection.y)*.48+1.),reflection.z*.42)
	if stuff:
		var down:=Vector3(reflection.x,-maxf(absf(reflection.y),incoming.length()*.65),-attack_direction*maxf(absf(reflection.z),2.))
		outgoing=down.normalized()*incoming.length()*STUFF_SPEED_RETENTION
	elif palm_contact and normal.y<-.2 and reflection.y<0.:
		outgoing=reflection*.42
	return {"stuff":stuff,"velocity":outgoing}

static func first_capsule_touch(start: Vector3,finish: Vector3,a: Vector3,b: Vector3,radius: float) -> Dictionary:
	var pair := Geometry3D.get_closest_points_between_segments(start,finish,a,b)
	if pair[0].distance_squared_to(pair[1])>radius*radius: return {}
	var lo := 0.
	var hi := clampf((pair[0]-start).dot(finish-start)/maxf(.00000001,start.distance_squared_to(finish)),0.,1.)
	for j in 10:
		var t := (lo+hi)*.5
		var p := start.lerp(finish,t)
		if p.distance_squared_to(Geometry3D.get_closest_point_to_segment(p,a,b))<=radius*radius: hi=t
		else: lo=t
	var point := start.lerp(finish,hi)
	var surface := Geometry3D.get_closest_point_to_segment(point,a,b)
	return {"fraction":hi,"point":point,"normal":surface.direction_to(point),"surface":surface}

static func manual_push_time(depth:float) -> float:
	return START*(1.-depth) if depth<=.05 else lerpf(START,.20,depth)

var takeoff_pose:Array[Transform3D]=[]
var takeoff_target:Array[Transform3D]=[]
var drive_elapsed:=0.
var drive_duration:=0.

func begin(player: Node3D, held_depth := 0., base_vertical := -1.) -> void:
	if held_depth>.05:
		drive_duration=manual_push_time(held_depth)
		for i in player.skeleton.get_bone_count():
			takeoff_pose.append(player.skeleton.get_bone_pose(i))
	actor = player
	if not overpass_swing:
		jump_height += bonus_height(player, jump_height if base_vertical < 0.0 else base_vertical)
		jump_height = minf(jump_height, maximum_block_lift(player)/Jump.COURT_VERTICAL_SCALE)
	upper_body_rate=1.+.5*clampf(player.effective_rating("Blocking")/100.,0.,1.)
	base = player.position
	swing_load=float(player.get_meta("swing_block_load",0.))
	player.set_meta("swing_block_load",0.)
	actor.play_action("idle",0.0)
	actor.animator.seek(0.0,true)
	for i in takeoff_pose.size():
		var end_pose:Transform3D=actor.skeleton.get_bone_pose(i)
		var bone_name:String=actor.skeleton.get_bone_name(i)
		if bone_name.begins_with("upperarm_") or bone_name.begins_with("lowerarm_") or bone_name.begins_with("hand_"):
			end_pose.basis=takeoff_pose[i].basis
		takeoff_target.append(end_pose)
		actor.skeleton.set_bone_pose(i,takeoff_pose[i])

func read_air_lane(ball_at: Vector3,partners: Array) -> void:
	if shoulders.size()!=2 or overpass_swing: return
	var gap := ball_at.x-actor.global_position.x
	min_hand_x=-INF
	max_hand_x=INF
	for partner in partners:
		if partner==actor or not partner.visible: continue
		var offset: Vector3=partner.global_position-actor.global_position
		if absf(offset.z)>.8 or absf(offset.x)>1.35: continue
		var seam: float=actor.global_position.x+offset.x*.5
		if offset.x<0.: min_hand_x=maxf(min_hand_x,seam+.06)
		else: max_hand_x=minf(max_hand_x,seam-.06)
	var open := not is_finite(min_hand_x) if gap<0. else not is_finite(max_hand_x)
	if square_block:
		reach_input=Vector2.ZERO
		lean_input=0.
		return
	var amount := smoothstep(.20,.78,absf(gap)) if open else 0.
	var left := (shoulders[0].x-shoulders[1].x)*gap>0.
	reach_input=Vector2(amount,0.) if left else Vector2(0.,amount)
	lean_input=clampf(gap,-.65,.65) if open else 0.

func step(delta: float, world_ball: Vector3) -> bool:
	if is_finite(net_heading): actor.rotation.y=rotate_toward(actor.rotation.y,net_heading,delta*9.)
	if drive_elapsed<drive_duration:
		drive_elapsed=minf(drive_duration,drive_elapsed+delta*tempo)
		var blend:=smoothstep(0.,drive_duration,drive_elapsed)
		var skeleton:Skeleton3D=actor.skeleton
		var drive_pose:Array[Transform3D]=[]
		for i in takeoff_pose.size():
			drive_pose.append(takeoff_pose[i].interpolate_with(takeoff_target[i],blend))
		var drive_author:RefCounted=actor.get_pose_author()
		for side in ["l","r"]:
			var hip:String="thigh_"+side
			var knee:String="calf_"+side
			var foot:String="foot_"+side
			var id:=skeleton.find_bone(foot)
			var planted:Transform3D=drive_author.world_pose(takeoff_pose,id)
			var push_end:Transform3D=drive_author.world_pose(takeoff_target,id)
			var ankle:=planted.interpolate_with(push_end,blend)
			var pole:Vector3=drive_author.point(drive_pose,knee)-drive_author.point(drive_pose,hip)
			drive_author.limb(drive_pose,hip,knee,foot,ankle.origin,pole)
			drive_author.set_world_basis(drive_pose,foot,ankle.basis)
		for i in drive_pose.size(): skeleton.set_bone_pose(i,drive_pose[i])
		if drive_elapsed>=drive_duration: age=START
		return true
	age += delta*tempo
	var phase := clampf((age-START)/AIR,0.0,1.0)
	var lift := 4.0*jump_height*preload("res://scripts/setter_jump.gd").COURT_VERTICAL_SCALE*phase*(1.0-phase)
	var load := sin(PI*clampf(age/START,0.0,1.0))
	var since_landing := age-START-AIR
	var absorb := smoothstep(0.0,0.055,since_landing)*(1.0-smoothstep(0.055,0.145,since_landing))
	var squat := 0.20*load*load+0.14*absorb
	actor.position = base+Vector3.UP*(lift-squat)
	actor.animator.seek(0.0,true)
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var lower_start := 0.71 if overpass_swing else 0.79
	var lower_end := 0.97 if overpass_swing else 1.02
	var weight := smoothstep(0.04,START+(0.30-START)/upper_body_rate,age)*(1.0-smoothstep(lower_start,lower_end,age))
	var aim := rig.to_local(world_ball)
	var scale_: float = rig.global_basis.y.length()
	if squat > 0.00001:
		var drop := rig.global_basis.inverse()*(Vector3.UP*squat)
		for side in ["l","r"]:
			var thigh: String = "thigh_"+side
			var knee: String = "calf_"+side
			var foot: String = "foot_"+side
			var ankle: Transform3D = author.world_pose(pose,rig.find_bone(foot))
			var bend: Vector3 = author.point(pose,knee)-author.point(pose,thigh)
			author.limb(pose,thigh,knee,foot,ankle.origin+drop,bend)
			author.set_world_basis(pose,foot,ankle.basis)
	if court_aim.is_finite() and phase>0. and phase<1.:
		var pike_weight := (1.-smoothstep(.52,.85,phase))*smoothstep(.30,.80,lift)
		var pike := smoothstep(.19,.50,phase)*pike_weight
		var torso_pike := smoothstep(.19,.19+.31/upper_body_rate,phase)*pike_weight
		var forward := actor.global_basis.z.normalized()
		actor.position-=forward*.19*pike
		author.rotate_world(pose,"spine_01",Vector3.RIGHT,.24*torso_pike)
		author.rotate_world(pose,"spine_02",Vector3.RIGHT,.13*torso_pike)
		for side in ["l","r"]:
			var thigh: String="thigh_"+side
			var calf: String="calf_"+side
			var foot: String="foot_"+side
			var hip: Vector3=author.point(pose,thigh)
			var leg_length := rig.to_global(hip).distance_to(rig.to_global(author.point(pose,calf)))+rig.to_global(author.point(pose,calf)).distance_to(rig.to_global(author.point(pose,foot)))
			var clearance := maxf(0.,rig.to_global(hip).z-preload("res://scripts/net_collision.gd").NET_Z-.19)
			var angle := minf(deg_to_rad(47.),asin(clampf(clearance/maxf(.01,leg_length),0.,1.)))
			var direction := Vector3(.10 if side=="l" else -.10,-cos(angle),sin(angle)).normalized()
			var leg: Vector3=(author.point(pose,calf)-hip).normalized()
			author.aim_joint(pose,thigh,calf,hip+leg.slerp(direction,pike))
			var knee: Vector3=author.point(pose,calf)
			var shin: Vector3=(author.point(pose,foot)-knee).normalized()
			author.aim_joint(pose,calf,foot,knee+shin.slerp(direction,pike*.96))
	var apex_press:=smoothstep(.24,.24+.24/upper_body_rate,phase)*(1.-smoothstep(.59,.88,phase))
	if not court_aim.is_finite() and not overpass_swing:
		author.rotate_world(pose,"spine_01",Vector3.RIGHT,.19*apex_press)
		author.rotate_world(pose,"spine_02",Vector3.RIGHT,.13*apex_press)
	var air_weight := smoothstep(0.,.12,phase)*(1.-smoothstep(.82,1.,phase))
	lean=lerpf(lean,lean_input,1.-exp(-14.*delta*(upper_body_rate if phase>0. and phase<1. else 1.)))
	reach=reach.lerp(reach_input,1.-exp(-16.*delta*(upper_body_rate if phase>0. and phase<1. else 1.)))
	if absf(lean)*air_weight>.0001:
		var axis_local := (rig.global_basis.inverse()*Vector3.BACK).normalized()
		author.rotate_world(pose,"spine_01",axis_local,-lean*.20*air_weight)
		author.rotate_world(pose,"spine_02",axis_local,-lean*.15*air_weight)
	if close_direction!=0. and air_weight>0.:
		var yaw_axis := (rig.global_basis.inverse()*Vector3.UP).normalized()
		author.rotate_world(pose,"spine_02",yaw_axis,-close_direction*.14*air_weight)
	previous_hands = hands.duplicate()
	previous_wrists = wrists.duplicate()
	hands.clear()
	elbows.clear()
	shoulders.clear()
	wrists.clear()
	for side in ["l","r"]:
		var arm: String = "upperarm_"+side
		var shoulder: Vector3 = author.point(pose,arm)
		var outward := 1.0 if side == "l" else -1.0
		var press := smoothstep(0.32,0.70,lift) if aggressive_press else smoothstep(0.45,0.95,lift)
		if not overpass_swing:
			press=apex_press*smoothstep(Net.NET_TOP+.06,Net.NET_TOP+.34,rig.to_global(shoulder).y+.58)
		var below_tape := 1.0-smoothstep(2.50,2.80,rig.to_global(shoulder).y+0.62)
		var depth := lerpf(lerpf(0.20,0.55,press),0.17,below_tape)
		var forward_press := press*(1.-below_tape) if not overpass_swing else 0.
		depth+=.21*forward_press
		var lateral_limit := 0.24 if aggressive_press else 0.18
		var target := shoulder+Vector3(clampf(aim.x-shoulder.x,-lateral_limit,lateral_limit)-outward*0.06,0.62-.09*forward_press,depth)/scale_
		if square_block: target.x=shoulder.x
		var spread := (reach.x if side=="l" else reach.y)*air_weight
		var opposite := (reach.y if side=="l" else reach.x)*air_weight
		var shoulder_offset := rig.to_global(shoulder).x-rig.to_global(author.point(pose,"spine_03")).x
		var inside_arm := is_finite(min_hand_x) if shoulder_offset<0. else is_finite(max_hand_x)
		if inside_arm: spread=0.
		var direct := 0.
		if track_near_ball and not overpass_swing:
			var distance := rig.to_global(shoulder).distance_to(world_ball)
			direct=air_weight*(1.-smoothstep(.68,1.05,distance))*smoothstep(2.43,2.60,world_ball.y)
			spread*=1.-direct
			opposite*=1.-direct
		var balance := opposite*(1.-spread) if not inside_arm or kong_direction!=0. else 0.
		var spine: Vector3=author.point(pose,"spine_03")
		var side_sign := signf(shoulder.x-spine.x)
		var diagonal := Vector3(side_sign*1.05,.19,.37)
		var counterweight := Vector3(side_sign*.48,-.47,.12)
		target=target.lerp(shoulder+counterweight/scale_,balance)
		target=target.lerp(shoulder+diagonal/scale_,spread)
		if is_finite(min_hand_x) or is_finite(max_hand_x):
			var world_target := rig.to_global(target)
			var forward := actor.global_basis.z.normalized()
			if court_aim.is_finite(): world_target.x+=clampf(court_aim.x-world_target.x,-1.,1.)*.09*press
			world_target+=forward*.18*press*(1.-below_tape)
			world_target.x=clampf(move_toward(world_target.x,world_ball.x,.12*press*(1.-maxf(spread,balance))),min_hand_x,max_hand_x)
			target=rig.to_local(world_target)
		if direct>0.:
			var hand_goal := world_ball+world_ball.direction_to(rig.to_global(shoulder))*.09
			hand_goal.x=clampf(hand_goal.x+shoulder_offset*.24,min_hand_x,max_hand_x)
			target=target.lerp(rig.to_local(hand_goal),direct)
		if square_block and not overpass_swing:
			# Each hand stays in its own shoulder lane. Reach vertically, then press at apex.
			var elbow_at:Vector3=author.point(pose,"lowerarm_"+side)
			var arm_length:=shoulder.distance_to(elbow_at)+elbow_at.distance_to(author.point(pose,"hand_"+side))
			var vertical:Vector3=(rig.global_basis.inverse()*Vector3.UP).normalized()
			var ahead:Vector3=(rig.global_basis.inverse()*actor.global_basis.z).normalized()
			var angle:=deg_to_rad(lerpf(8.,65.,press))
			var direction:=vertical*cos(angle)+ahead*sin(angle)
			if is_finite(late_quick_x):
				var gap:=late_quick_x-actor.global_position.x
				if signf(shoulder_offset)==signf(gap):
					var sideways:Vector3=(rig.global_basis.inverse()*Vector3.RIGHT).normalized()
					direction+=sideways*clampf(gap,-1.,1.)*.80
				else:
					arm_length*=.76
			var upright:=shoulder+direction.normalized()*arm_length*.99
			target=target.lerp(upright,air_weight)
		var pole := Vector3(outward*0.38,-0.55,0.30)
		if overpass_swing and side == "r":
			var draw := smoothstep(0.11,0.30,age)*(1.0-smoothstep(0.30,0.47,age))
			var strike := smoothstep(0.30,0.51,age)
			var follow := smoothstep(0.53,0.74,age)
			var contact := aim+Vector3(0.0,-0.055,-0.07)/scale_
			target = (target+Vector3(-0.13,-0.23,-0.40)*draw/scale_).lerp(contact,strike)
			target = target.lerp(shoulder+Vector3(-0.16,-0.35,0.30)/scale_,follow)
			pole = pole.lerp(Vector3(-0.75,-0.27,-0.42),draw)
		elif overpass_swing:
			target = target.lerp(shoulder+Vector3(0.12,0.04,0.30)/scale_,smoothstep(0.30,0.56,age))
		if swing_load>.01 and not overpass_swing:
			var sweep := swing_load*(1.-smoothstep(.04,.28,age))
			target=target.lerp(shoulder+Vector3(outward*.13,-.38,-.32)/scale_,sweep)
			weight=maxf(weight,sweep)
		var extension := 174.
		var wrist_clearance := rig.to_global(target).y-Net.NET_TOP
		var press_weight := press*smoothstep(.02,.20,wrist_clearance)*(1.-balance) if not overpass_swing else 0.
		if court_aim.is_finite() and not overpass_swing:
			var reach_weight:=smoothstep(.04,.04+.28/upper_body_rate,phase)*(1.-smoothstep(.76,.98,phase))
			extension=lerpf(132.,177.,maxf(reach_weight,press_weight))
			extension=lerpf(extension,178.,spread*smoothstep(.0,.14,wrist_clearance))
			var elbow:Vector3=author.point(pose,"lowerarm_"+side)
			var length:=shoulder.distance_to(elbow)+elbow.distance_to(author.point(pose,"hand_"+side))
			target=target.lerp(shoulder+shoulder.direction_to(target)*length,maxf(reach_weight*(1.-balance)*.90,press_weight))
		author.limb(pose,arm,"lowerarm_"+side,"hand_"+side,target,pole,weight,extension)
		if spread>.001:
			var elbow: Vector3=author.point(pose,"lowerarm_"+side)
			var wrist_at: Vector3=author.point(pose,"hand_"+side)
			var upper_axis := shoulder.direction_to(target)
			var straight := shoulder+upper_axis*(shoulder.distance_to(elbow)+elbow.distance_to(wrist_at))
			var straight_world := rig.to_global(straight)
			var seam_room := minf(straight_world.x-min_hand_x,max_hand_x-straight_world.x)
			var clearance := minf(rig.to_global(elbow).y,straight_world.y)-preload("res://scripts/net_collision.gd").NET_TOP
			var own_side := minf(rig.to_global(elbow).z,straight_world.z)-preload("res://scripts/net_collision.gd").NET_Z
			var clear_path := maxf(smoothstep(.0,.10,clearance),smoothstep(.04,.10,own_side))
			var straighten := spread*clear_path*smoothstep(.0,.08,seam_room)
			author.aim_joint(pose,arm,"lowerarm_"+side,elbow.lerp(shoulder+upper_axis*shoulder.distance_to(elbow),straighten))
			elbow=author.point(pose,"lowerarm_"+side)
			wrist_at=author.point(pose,"hand_"+side)
			author.aim_joint(pose,"lowerarm_"+side,"hand_"+side,wrist_at.lerp(elbow+upper_axis*elbow.distance_to(wrist_at),.98*straighten))
		for digit in ["thumb","index","middle","ring","pinky"]:
			for segment in ["01","02","03"]:
				var bone := rig.find_bone("%s_%s_%s" % [digit,segment,side])
				pose[bone].basis = pose[bone].basis.slerp(rig.get_bone_rest(bone).basis,weight)
		var hand_name: String = "hand_"+side
		var wrist: Transform3D = author.world_pose(pose,rig.find_bone(hand_name))
		var finger_direction: Vector3 = author.point(pose,"middle_01_"+side)-wrist.origin
		var across: Vector3 = author.point(pose,"index_01_"+side)-author.point(pose,"pinky_01_"+side)
		var palm_normal := Vector3(clampf(aim.x-wrist.origin.x,-0.18,0.18),-0.45,1.0).normalized()
		if court_aim.is_finite():
			var incoming := world_ball.direction_to(rig.to_global(wrist.origin))
			var outgoing := rig.to_global(wrist.origin).direction_to(court_aim)
			var normal := (outgoing-incoming).normalized()
			if normal.length_squared()>.5: palm_normal=(rig.global_basis.inverse()*normal).normalized()
		var up := Vector3.UP.slide(palm_normal).normalized()
		if spread>.001:
			var forearm: Vector3=wrist.origin-author.point(pose,"lowerarm_"+side)
			var fingertips := forearm.slide(palm_normal)
			if fingertips.length_squared()>.0001: up=up.slerp(fingertips.normalized(),spread).normalized()
		if press_weight>0.:
			var forward_local:Vector3=(rig.global_basis.inverse()*actor.global_basis.z).normalized()
			var over_tape:Vector3=(forward_local+Vector3.DOWN*.12).normalized()
			var pitch_weight:=press_weight*(1.-.35*spread)
			up=up.slerp(over_tape,pitch_weight).normalized()
			palm_normal=palm_normal.slerp((Vector3.DOWN-forward_local*.12).normalized(),pitch_weight).normalized()
		var edge := up.cross(palm_normal)*-outward
		var palm := HandPose.hand_basis(up,edge)*HandPose.hand_basis(finger_direction,across).inverse()*wrist.basis
		author.set_world_basis(pose,hand_name,wrist.basis.orthonormalized().slerp(palm.orthonormalized(),weight))
		if drive_duration>0. and phase<.18:
			var lift_blend:=smoothstep(0.,.18,phase)
			for joint:String in [arm,"lowerarm_"+side,hand_name]:
				var index:=rig.find_bone(joint)
				pose[index]=takeoff_target[index].interpolate_with(pose[index],lift_blend)
		var hand: Vector3 = author.point(pose,"hand_"+side)
		var tip: Vector3 = author.point(pose,"middle_03_"+side)
		shoulders.append(rig.to_global(shoulder))
		elbows.append(rig.to_global(author.point(pose,"lowerarm_"+side)))
		hands.append(rig.to_global(tip))
		wrists.append(rig.to_global(hand))
	body_chains=body_geometry(shoulders[0],shoulders[1],rig.to_global(author.point(pose,"neck_01")),rig.to_global(author.point(pose,"Head")))
	if previous_hands.is_empty():
		previous_hands = hands.duplicate()
		previous_wrists = wrists.duplicate()
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,pose[bone].basis.orthonormalized().get_rotation_quaternion())
	if court_aim.is_finite() or not overpass_swing:
		var own_side:=1. if actor.global_position.z>=Net.NET_Z else -1.
		var retreat := Net.pose_retreat(actor,own_side)
		if retreat>0.:
			var shift:=retreat*own_side
			actor.global_position.z+=shift
			for points in [shoulders,elbows,wrists,hands]:
				for i in points.size(): points[i].z+=shift
			for chain in body_chains:
				for i in chain.size(): chain[i].z+=shift
	if age < START+AIR+0.02+landing_recovery:
		use_displayed_geometry()
		return true
	actor.position = base
	actor.animator.seek(0.0,true)
	return false
