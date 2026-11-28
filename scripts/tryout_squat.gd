extends RefCounted

const FULL_LOAD := 0.38
const GREEN_START := 0.58
const GREEN_END := 0.76
var charging := false
var seconds := 0.0
var ring := MeshInstance3D.new()
var paint := ShaderMaterial.new()
var feedback_time := 0.0
var baseline: Array = []

func configure(world: Node3D) -> void:
	var disc := PlaneMesh.new()
	disc.size = Vector2(1.88,1.88)
	ring.mesh = disc
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = """shader_type spatial;
	render_mode unshaded,cull_disabled;
	uniform float progress;
	uniform vec2 sweet;
	void fragment(){
		vec2 p=UV-.5;
		float r=length(p), a=fract(atan(p.x,-p.y)/6.283185+1.);
		float band=smoothstep(.355,.371,r)*(1.-smoothstep(.458,.473,r));
		vec3 c=a<progress?vec3(.32,.80,.92):vec3(.09,.12,.14);
		float tick=1.-smoothstep(.005,.014,abs(a-clamp(progress,.008,.99)));
		ALBEDO=mix(c*(a<progress?1.:.62),vec3(1.),tick);
		ALPHA=band*.98;
	}"""
	paint.shader = shader
	paint.set_shader_parameter("sweet",Vector2(GREEN_START,GREEN_END))
	ring.material_override = paint
	world.add_child(ring)
	ring.hide()

func begin(actor: Node3D) -> void:
	charging = true
	seconds = 0
	baseline.clear()
	for i in actor.skeleton.get_bone_count(): baseline.append(actor.skeleton.get_bone_pose(i))
	ring.show()

func update(actor: Node3D,delta: float,pose_depth := 1., beach_block := false) -> void:
	ring.position = Vector3(actor.position.x,.085,actor.position.z)
	if not charging:
		feedback_time -= delta
		if feedback_time<=0: ring.hide()
		return
	seconds += delta
	var depth := clampf(seconds/FULL_LOAD,0,1)
	paint.set_shader_parameter("progress",depth)
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var pose := baseline.duplicate()
	var hips := rig.find_bone("pelvis")
	var parent: Transform3D = author.world_pose(pose,rig.get_bone_parent(hips))
	var bend := smoothstep(0,1,depth)*pose_depth
	var sink:=.48 if beach_block else .54
	pose[hips].origin += parent.basis.inverse()*Vector3(0,-sink*bend,(-.17 if beach_block else -.09)*bend)
	var stance_axis:=Vector3.RIGHT
	if beach_block:
		var left:Vector3=author.point(baseline,"foot_l")
		var right:Vector3=author.point(baseline,"foot_r")
		stance_axis=(left-right).slide(Vector3.UP).normalized()
		var hip_center:Vector3=(author.point(pose,"thigh_l")+author.point(pose,"thigh_r"))*.5
		var shift:=stance_axis*((left+right)*.5-hip_center).dot(stance_axis)
		pose[hips].origin+=parent.basis.inverse()*shift*bend
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,.40*bend)
	for side in ["l","r"]:
		if beach_block:
			var upper:String="upperarm_"+side
			var shoulder:Vector3=author.point(pose,upper)
			var hand:String="hand_"+side
			var low:=Vector3(-.035 if side=="l" else .035,-.47,.14)
			var lower:String="lowerarm_"+side
			var arm_id:=rig.find_bone(upper)
			var elbow_id:=rig.find_bone(lower)
			var start_arm:Transform3D=pose[arm_id]
			var start_elbow:Transform3D=pose[elbow_id]
			author.limb(pose,upper,lower,hand,shoulder+low,Vector3(.20 if side=="l" else -.20,0,-1),1.,147.)
			pose[arm_id]=start_arm.interpolate_with(pose[arm_id],bend)
			pose[elbow_id]=start_elbow.interpolate_with(pose[elbow_id],bend)
		var foot: String = "foot_"+side
		var pole:=Vector3.BACK
		if beach_block:
			var forward:=Vector3.BACK.slide(stance_axis).normalized()
			var thigh:Vector3=author.point(baseline,"thigh_"+side)
			var ankle:Vector3=author.point(baseline,foot)
			var knee:Vector3=author.point(baseline,"calf_"+side)
			var initial_pole:=(knee-thigh).slide(thigh.direction_to(ankle)).normalized()
			pole=initial_pole.lerp(forward+stance_axis*(.65 if side=="l" else -.65),bend)
		author.limb(pose,"thigh_"+side,"calf_"+side,foot,author.point(baseline,foot),pole)
		author.set_world_basis(pose,foot,author.world_pose(baseline,rig.find_bone(foot)).basis)
	rig.set_bone_pose_position(hips,pose[hips].origin)
	for i in rig.get_bone_count():
		rig.set_bone_pose_rotation(i,pose[i].basis.orthonormalized().get_rotation_quaternion())

func release(actor: Node3D,jump: RefCounted, height_override := -1., ability := 65.) -> String:
	var depth := clampf(seconds/FULL_LOAD,0,1)
	var quality := smoothstep(0,GREEN_START*lerpf(1.26,.86,ability/100.),depth)
	charging = false
	feedback_time = .65
	var maximum := height_override if height_override>0. else clampf(actor.attributes.vertical_in,30,60)*.0254
	var height := maximum*lerpf(.28,1,quality)
	jump.begin_set_jump(actor,.02,height)
	jump.height = height
	jump.air_time = jump.flight_duration(height,true)
	jump.elapsed = jump.load_duration()
	jump.release()
	return "Early release" if depth<GREEN_START else ("Deep release" if depth>GREEN_END else "Perfect depth")

func cancel() -> void:
	charging = false
	feedback_time = 0
	ring.hide()

