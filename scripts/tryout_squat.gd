extends RefCounted

const FULL_LOAD := 0.92
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
		vec3 c=a<sweet.x?vec3(.19,.55,.70):(a<sweet.y?vec3(.15,.94,.45):vec3(1.,.19,.08));
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

func update(actor: Node3D,delta: float) -> void:
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
	var bend := smoothstep(0,1,depth)
	pose[hips].origin += parent.basis.inverse()*Vector3(0,-.54*bend,-.09*bend)
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,.40*bend)
	for side in ["l","r"]:
		var foot: String = "foot_"+side
		author.limb(pose,"thigh_"+side,"calf_"+side,foot,author.point(baseline,foot),Vector3(0,0,1))
		author.set_world_basis(pose,foot,author.world_pose(baseline,rig.find_bone(foot)).basis)
	rig.set_bone_pose_position(hips,pose[hips].origin)
	for i in rig.get_bone_count():
		rig.set_bone_pose_rotation(i,pose[i].basis.orthonormalized().get_rotation_quaternion())

func release(actor: Node3D,jump: RefCounted) -> String:
	var depth := clampf(seconds/FULL_LOAD,0,1)
	var quality := smoothstep(0,GREEN_START,depth)
	charging = false
	feedback_time = .65
	var height := clampf(actor.attributes.vertical_in,30,60)*.0254*lerpf(.28,1,quality)
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

