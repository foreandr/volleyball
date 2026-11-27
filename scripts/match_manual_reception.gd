extends Node3D

const Map=preload("res://scripts/mapped_reception.gd")
const Contact=preload("res://scripts/gym_physics.gd")
const Accuracy=preload("res://scripts/reception_accuracy.gd")
var mapper:=Map.new()
var anchor:=Node3D.new()
var boxes:Array[Dictionary]
var motion:={}
var held:=false
var released:=INF
var grade:={}
var contact_at:=INF
var axis:=Vector3.FORWARD
var speed:=1.
var next_check:=0.
var prepare_weight:=0.
var steering:=Vector3.ZERO
var mapped_shift:=Vector3.ZERO
var landing_actor:Node3D
var fall_speed:=0.

func _ready() -> void:
	add_child(mapper)
	add_child(anchor)
	mapper.pose_origin=anchor
	mapper.defenders.append(anchor)
	mapper.clips=JSON.parse_string(FileAccess.get_file_as_string("res://assets/reception_studio.json"))
	boxes=mapper.assigned_boxes()

func stop_pose() -> void:
	if not motion.is_empty():
		var actor:Node3D=mapper.player
		var facing:=anchor.global_basis.z
		actor.global_basis=Basis(Vector3.UP,atan2(facing.x,facing.z))*Basis.from_scale(mapper.athlete_scale)
		if actor.position.y>.05:
			landing_actor=actor
			fall_speed=0.
		else: actor.position.y=.04
		for modifier in actor.skeleton.get_children():
			if modifier is SkeletonModifier3D: modifier.active=true
		actor.play_action("idle",.16)
		mapper.player=null
	motion={}
	grade={}
	released=INF
	next_check=0.

func land(dt:float) -> void:
	if not is_instance_valid(landing_actor): return
	fall_speed+=9.81*dt
	landing_actor.position.y=maxf(.04,landing_actor.position.y-fall_speed*dt)
	if landing_actor.position.y<=.04: landing_actor=null

func button(down:bool,g) -> void:
	if down and not held:
		released=INF
		grade={}
		next_check=0.
	elif not down and held and g.phase==g.Phase.LIVE:
		released=g.elapsed
		if not motion.is_empty(): grade=meter(g,g.path_point(released))
	held=down

func eligible(g) -> bool:
	return g.phase==g.Phase.LIVE and g.receiving_team==0 and g.last_player!=0 and (g.flight_kind=="serve" or g.defensive_ball()) and not g.blocks.has(0)

func meter(g,point:Vector3) -> Dictionary:
	if not grade.is_empty(): return grade
	var face:=Contact.joint(g.human,"Head").dot(axis)-.09
	return Map.release_grade(point.dot(axis),face,mapper.set_intercept.dot(axis),speed,mapper.segment_touch(motion,point-axis*.001,point),mapper.player.effective_rating("Hand reception" if motion.get("kind","")=="overhead" else "Forearm reception"))

func plan(g,previous:float) -> void:
	var actor:Node3D=g.human
	var home:=actor.global_position
	home.y=.04
	var source:Vector3=g.players[g.last_player].global_position
	var yaw:=atan2(source.x-home.x,source.z-home.z)
	var finish:=minf(g.flight_end(),previous+.40)
	var p:Vector3=g.path_point(previous)
	var t:=previous
	while t<finish:
		var end:=minf(finish,t+.04)
		var q:Vector3=g.path_point(end)
		var a:=(p-home).rotated(Vector3.UP,-yaw)
		var b:=(q-home).rotated(Vector3.UP,-yaw)
		if AABB(mapper.MAP_ORIGIN,mapper.CELL_SIZE*3.).intersects_segment(a,b)!=null:
			var first:=INF
			var best:={}
			for box in boxes:
				var span:=mapper.zone_interval(a,b,box.bounds)
				if span.y>span.x and span.x<first:
					first=span.x
					best=box
			if not best.is_empty():
				contact_at=lerpf(t,end,first)
				var velocity:Vector3=(q-p)/maxf(.001,end-t)
				speed=maxf(.1,velocity.slide(Vector3.UP).length())
				axis=velocity.slide(Vector3.UP).normalized()
				if mapper.early_platform(best.cell): contact_at=maxf(previous,contact_at-.55/speed)
				mapper.set_intercept=g.path_point(contact_at)
				mapper.incoming_lead_seconds=contact_at-previous
				mapper.feed_kmh=velocity.length()*3.6
				mapper.pass_goal=g.frames[0].to_global(Vector3(-1.4,.15,2.8))
				mapper.pass_rise=3.4 if g.defensive_ball() else 3.05
				landing_actor=null
				motion=mapper.begin_mapped_motion(anchor,actor,home,source,best,.12 if g.defensive_ball() else 0.)
				contact_at=mapper.align_contact(motion,g.path_point,contact_at,previous,g.flight_end())
				mapper.incoming_lead_seconds=contact_at-previous
				mapper.entry_frame=clampf(motion.contact-mapper.incoming_lead_seconds*60.,minf(6.,motion.contact),motion.contact)
				mapper.entry_duration=clampf(motion.contact-mapper.entry_frame,.01,12.)
				mapped_shift=mapper.intercept_shift
				steering=Vector3.ZERO
				return
		p=q
		t=end

func step(g,previous:float,delta:float,controls) -> bool:
	if not eligible(g):
		prepare_weight=0.
		return false
	if motion.is_empty():
		prepare_weight=move_toward(prepare_weight,1. if held else 0.,delta*5.)
		if prepare_weight>0.:
			var platform_pose=g.platforms[0]
			platform_pose.knee_bend_depth=.12*prepare_weight
			platform_pose.apply_knee_bend()
			platform_pose.knee_bend_depth=0.
	if motion.is_empty():
		if not held or g.elapsed<next_check: return false
		next_check=g.elapsed+.035
		plan(g,previous)
		if motion.is_empty(): return false
	else:
		controls.read_pace_input()
		var stick:Vector2=controls.movement_input()
		var shift:=Vector3(-stick.x,0,stick.y)*delta*preload("res://scripts/player_ground_controls.gd").speed(controls.focus_requested,controls.sprint_requested)
		anchor.position+=shift
		steering+=shift
		mapper.intercept_shift=mapped_shift-steering.limit_length(.45)
	var rate:=1.+.8*smoothstep(40.,110.,mapper.feed_kmh) if g.defensive_ball() else 1.
	var offset:float=g.elapsed-contact_at
	var frame:=float(motion.contact)+offset*60.
	if offset<0.: frame=motion.contact+minf(0.,(mapper.incoming_lead_seconds+offset)*rate-mapper.incoming_lead_seconds)*60.
	mapper.sample_receiver(motion,clampf(frame,0.,motion.frames),true,mapper.legs)
	g.animated[0]=true
	var a:Vector3=g.path_point(previous)
	var b:Vector3=g.ball.global_position
	var cutoff:=Contact.joint(g.human,"Head").dot(axis)-.09+.20
	if a.dot(axis)>cutoff or g.elapsed>contact_at+.25:
		stop_pose()
		next_check=g.flight_end()
		return false
	var advance:=(b-a).dot(axis)
	if advance>.0001 and b.dot(axis)>cutoff: b=a.lerp(b,clampf((cutoff-a.dot(axis))/advance,0.,1.))
	if not mapper.segment_touch(motion,a,b): return false
	if not held and not grade.get("playable",false): return false
	for i in 7:
		var mid:=a.lerp(b,.5)
		if mapper.segment_touch(motion,a,mid): b=mid
		else: a=mid
	var hands:bool=motion.kind=="overhead"
	var timing:=.8 if held else clampf(absf(grade.offset)/.21,0.,1.)
	var stat:=("Hand" if hands else "Forearm")+(" defense" if g.defensive_ball() else " reception")
	var miss:=Accuracy.sample_offset(Accuracy.spread(timing,mapper.feed_kmh/3.6,g.spin,g.human.effective_rating(stat),false))
	var goal:=mapper.pass_goal+miss.slide(Vector3.UP)
	var rise:=mapper.pass_rise
	var lift:=sqrt(19.62*rise)
	var duration:=(lift+sqrt(19.62*maxf(.05,b.y+rise-1.8)))/9.81
	var outgoing:=(goal-b).slide(Vector3.UP)/duration+Vector3.UP*lift
	g.platforms[0].hand_setting=hands
	g.platforms[0].touch_time=g.elapsed
	if held:
		var state:=meter(g,b).duplicate()
		state.merge({"perfect":Vector2(.33,.67),"contact":Vector2(.08,.90),"released":false,"grade":"Held at contact"},true)
		g.manual.report("Dig" if g.defensive_ball() else "Pass",0.,state)
	g.receive_contact(0,b,outgoing,1 if hands else 0)
	return true
