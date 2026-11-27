extends Node

const Hands = preload("res://scripts/hand_setting_pose.gd")
const Physics = preload("res://scripts/gym_physics.gd")
const Marker = preload("res://scripts/ball_landing_marker.gd")
const Kit = preload("res://scripts/practice_kit.gd")
const FLIGHT := 1.15
const RELEASE := .065

var game
var participants: Array[Node3D] = []
var coaches: Array[Node3D] = []
var partners: Array[Node3D] = []
var seats: Array = []
var seat_elapsed := PackedFloat32Array()
var orb := MeshInstance3D.new()
var speaker_clock := 0.
var holder := 0
var flight_time := -1.
var hold_time := 0.
var clearance_time := 0.
var origin := Vector3.ZERO
var destination := Vector3.ZERO
var talk_to_player := false

func populate(host) -> void:
	game = host
	for actor in game.world.get_children():
		if actor.has_method("get_pose_author") and actor.visible:
			participants.append(actor)
	var remaining := 20 - participants.size()
	if remaining < 6: return
	for i in 2:
		var adult: Node3D = game.athlete(Vector3(-6.7-i*.95,0,4.3+i*.5),"505957")
		Kit.apply(adult,true,3+i)
		adult.play_action("base/Idle",0.)
		adult.animator.seek(i*.67,true)
		coaches.append(adult)
	make_pair(Vector3(9.2,0,7.),6)
	var second = get_script().new()
	add_child(second)
	second.game=host
	second.participants=participants
	second.make_pair(Vector3(-9.2,0,-6.),4)
	for i in 2:
		coaches[i].look_at(coaches[1-i].global_position,Vector3.UP,true)
	seats = game.gym.seat_teammates(game.athlete,game.register_student,mini(10,remaining-6),true)
	seat_elapsed.resize(seats.size())
	for i in seats.size():
		seat_elapsed[i]=float(i)/maxi(1,seats.size())/24.
		seats[i].actor.fabric_interval=1./24.
	talk_to_player = randf()<.5
	print("Practice gym: ",participants.size()+6+seats.size()," people, including ",seats.size()," seated teammates.")

func make_pair(start: Vector3, variant: int) -> void:
	for i in 2:
		var player: Node3D = game.athlete(start+Vector3(0,0,i*3.),"a4293c")
		game.register_student(player,variant+i)
		Kit.apply(player,false,variant+i)
		player.play_action("idle",0.)
		partners.append(player)
	for i in 2:
		partners[i].look_at(partners[1-i].global_position,Vector3.UP,true)
	orb.mesh=game.ball.mesh
	orb.material_override=game.ball.material_override
	orb.scale=game.ball.scale
	game.world.add_child(orb)
	Marker.attach(orb,landing)

func landing() -> Vector3:
	return Marker.parabola(origin,destination,FLIGHT,1.6) if flight_time>=0. else Vector3.INF

func close_to_pair(point: Vector3) -> bool:
	if not point.is_finite(): return false
	var xy := Vector2(point.x,point.z)
	return xy.distance_to(Geometry2D.get_closest_point_to_segment(xy,Vector2(partners[0].position.x,partners[0].position.z),Vector2(partners[1].position.x,partners[1].position.z)))<3.5

func _process(delta: float) -> void:
	if partners.is_empty() or game.settings.visible: return
	speaker_clock += delta
	for i in seats.size():
		seat_elapsed[i]+=delta
		if seat_elapsed[i]<1./24.: continue
		var step:=float(seat_elapsed[i])
		seat_elapsed[i]=0.
		var seat = seats[i]
		seat.actor.animator.advance(step)
		seat.update()
		seat.watch(seats[i^1].actor.position+Vector3.UP if (i^1)<seats.size() else game.coach.position,step)
	for i in coaches.size():
		var adult := coaches[i]
		adult.animator.advance(delta)
		var speaking := int(speaker_clock/3.)%2==i
		var listener: Node3D = seats[0].actor if talk_to_player and not seats.is_empty() and int(speaker_clock/6.)%2==1 else coaches[1-i]
		var dir := listener.position-adult.position
		adult.rotation.y=rotate_toward(adult.rotation.y,atan2(dir.x,dir.z),delta*1.6)
		var rig: Skeleton3D = adult.skeleton
		var elbow := rig.find_bone("lowerarm_r")
		if elbow>=0 and speaking:
			var rest := rig.get_bone_pose_rotation(elbow)
			rig.set_bone_pose_rotation(elbow,rest*Quaternion(Vector3.RIGHT,.32+.24*sin(speaker_clock*4.)))
	var occupied: bool = game.ball.visible and (close_to_pair(game.ball.position) or close_to_pair(game.projected_landing()))
	for actor in participants:
		if actor.visible and close_to_pair(actor.position): occupied=true
	clearance_time = 0. if occupied else clearance_time+delta
	var receiver := 1-holder
	for i in 2:
		var actor := partners[i]
		actor.animator.advance(delta)
		var forward := actor.global_basis.z.normalized()
		var contact := Physics.joint(actor,"Head")+Vector3.UP*.12+forward*.24
		var offset := partners[1-i].position-actor.position
		var push := (offset+Vector3.UP*5.).normalized()
		if i==receiver and flight_time>=0.:
			Hands.standing_set(actor,contact,offset,push,-1.,smoothstep(FLIGHT-.34,FLIGHT-.04,flight_time))
		elif i==holder:
			if flight_time<0.:
				var follow := hold_time if clearance_time>1. else -1.
				Hands.standing_set(actor,contact,offset,push,follow,1.)
			elif flight_time+RELEASE<Hands.CPU_FOLLOW_TIME:
				Hands.standing_set(actor,origin,offset,push,flight_time+RELEASE,1.)
		if i==receiver: destination=contact
	if flight_time<0.:
		orb.position=Hands.contact_center(partners[holder])
		hold_time=hold_time+delta if clearance_time>1. else 0.
		if clearance_time>1. and hold_time>=RELEASE:
			origin=orb.position
			flight_time=0.
	else:
		flight_time+=delta
		var t := clampf(flight_time/FLIGHT,0.,1.)
		orb.position=origin.lerp(destination,t)+Vector3.UP*6.4*t*(1.-t)
		if t>=1.:
			holder=receiver
			flight_time=-1.
			hold_time=0.
