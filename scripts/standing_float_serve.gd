extends "res://scripts/underhand_serve.gd"

const FLOAT_CONTACT := 0.79
const TOSS_RELEASE := 0.34

var toss_origin: Vector3

func configure(actor: Node3D, start := START, yaw := 0.0) -> void:
	apex = 3.85
	super.configure(actor,start,yaw)
	var marker := aim_ring.material_override as StandardMaterial3D
	marker.albedo_color = Color("64cfff")

func contact_time() -> float:
	return FLOAT_CONTACT

func toss_release_time() -> float:
	return TOSS_RELEASE

func reset() -> void:
	super.reset()
	pose(toss_release_time())
	toss_origin = ball.position
	pose(0.0)

func pose(time: float) -> void:
	var contact := contact_time()
	var toss_release := toss_release_time()
	var bones := prepare_serve_pose(time,0.88,1.02,0.075,0.07,0.52,0.91,0.48)
	var rig: Skeleton3D = player.skeleton
	var author: RefCounted = player.get_pose_author()
	var scale_: float = rig.global_basis.get_scale().y
	var windup := smoothstep(0.09,contact-0.21,time)
	var drive := smoothstep(contact-0.22,contact,time)
	var follow := smoothstep(contact,contact+0.40,time)
	author.rotate_world(bones,"spine_03",Vector3.UP,-0.34*windup*(1.0-drive)+0.30*drive*(1.0-0.60*follow))
	author.rotate_world(bones,"spine_02",Vector3.RIGHT,-0.17*windup*(1.0-drive)+0.22*follow)
	var left_shoulder: Vector3 = author.point(bones,"upperarm_l")
	var right_shoulder: Vector3 = author.point(bones,"upperarm_r")
	var toss_lift := smoothstep(0.07,toss_release,time)
	var left_drop := smoothstep(toss_release,0.72,time)
	var left_wrist := left_shoulder+Vector3(-0.14-0.12*toss_lift,-0.37+0.48*toss_lift,0.41)/scale_
	var left_ready: Vector3 = author.point(bones,"hand_l")
	author.limb(bones,"upperarm_l","lowerarm_l","hand_l",left_wrist.lerp(left_ready,left_drop),Vector3(0.30,-0.9,-0.15))
	orient_palm(bones,rig,author,"l",Vector3.BACK,Vector3.LEFT,1.0-left_drop)
	var low_right := right_shoulder+Vector3(-0.08,-0.53,0.03)/scale_
	var drawn_right := right_shoulder+Vector3(-0.24,0.34,-0.35)/scale_
	var contact_right := right_shoulder+Vector3(-0.045,0.53,0.28)/scale_
	var follow_right := right_shoulder+Vector3(0.36,-0.42,0.30)/scale_
	var right_wrist := low_right.lerp(drawn_right,windup).lerp(contact_right,drive).lerp(follow_right,follow)
	author.limb(bones,"upperarm_r","lowerarm_r","hand_r",right_wrist,Vector3(-0.85,0.05,-0.25).lerp(Vector3(-0.35,-0.3,0.6),drive),1.0,176.0)
	orient_palm(bones,rig,author,"r",Vector3(0.0,1.0,0.10),Vector3.RIGHT,windup*(1.0-0.75*follow))
	prepare_toss_hands(bones,rig,author,time)
	for bone in rig.get_bone_count(): rig.set_bone_pose_rotation(bone,bones[bone].basis.get_rotation_quaternion())
	if time <= toss_release:
		var palm: Vector3 = toss_palm(bones,rig,author,time)
		ball.position = to_local(rig.to_global(palm))+Vector3.UP*(BallPreview.RADIUS+0.012)
	elif is_equal_approx(time,contact):
		var palm: Vector3 = author.point(bones,"hand_r").lerp(author.point(bones,"middle_01_r"),0.76)
		ball.position = to_local(rig.to_global(palm))+forward*(BallPreview.RADIUS+0.012)
	elif time < contact:
		var portion := (time-toss_release)/(contact-toss_release)
		ball.position = toss_origin.lerp(preview_origin,portion)+Vector3.UP*toss_curve_height()*4.0*portion*(1.0-portion)

func toss_curve_height() -> float:
	return 0.25

func prepare_toss_hands(_pose: Array, _rig: Skeleton3D, _author: RefCounted, _time: float) -> void:
	pass

func toss_palm(pose: Array, _rig: Skeleton3D, author: RefCounted, _time: float) -> Vector3:
	return author.point(pose,"hand_l").lerp(author.point(pose,"middle_01_l"),0.72)

func orient_palm(pose: Array, rig: Skeleton3D, author: RefCounted, side: String, direction: Vector3, across: Vector3, weight: float) -> void:
	var hand := "hand_"+side
	var base: Transform3D = author.world_pose(pose,rig.find_bone(hand))
	var fingers: Vector3 = author.point(pose,"middle_01_"+side)-base.origin
	var width: Vector3 = author.point(pose,"index_01_"+side)-author.point(pose,"pinky_01_"+side)
	var basis := HandPose.hand_basis(direction,across)*HandPose.hand_basis(fingers,width).inverse()*base.basis
	author.set_world_basis(pose,hand,base.basis.slerp(basis,weight))
	for digit in ["thumb","index","middle","ring","pinky"]:
		for joint in ["01","02","03"]:
			var bone := rig.find_bone("%s_%s_%s" % [digit,joint,side])
			if bone >= 0: pose[bone].basis = pose[bone].basis.slerp(rig.get_bone_rest(bone).basis,weight)
