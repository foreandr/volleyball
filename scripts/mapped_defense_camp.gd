extends "res://scripts/serving_camp.gd"

const PassAccuracy = preload("res://scripts/reception_accuracy.gd")
const Map = preload("res://scripts/mapped_reception.gd")
var defense_map := Map.new()
var defense_anchor := Node3D.new()
var defense_recipe := {}
var defense_at := INF
var defense_contact := -INF
var first_dig_touch := -INF
var feedback_rally := -1
const PASS_RELEASE_LEAD := .050
const DIG_WINDOW := .125
const DIG_PERFECT := .055
var dig_reach := .12
var boxes: Array[Dictionary]=[]

func start_drill() -> void:
	world.add_child(defense_map)
	world.add_child(defense_anchor)
	defense_map.defenders.append(defense_anchor)
	defense_map.clips=JSON.parse_string(FileAccess.get_file_as_string("res://assets/reception_studio.json"))
	defense_map.pass_goal=Vector3(0.,.15,BallNet.NET_Z-1.5)
	boxes=defense_map.assigned_boxes()
	super.start_drill()

var dig_recovery_age := 0.

func release_dig_pose() -> void:
	var actor=defense_map.player
	if actor==null: return
	var facing := defense_anchor.rotation.y
	actor.reparent(world,true)
	actor.global_basis=Basis(Vector3.UP,facing)*Basis.from_scale(defense_map.athlete_scale)
	actor.position.y=.04
	for bone in defense_map.ready_pose.size():
		actor.skeleton.set_bone_pose(bone,defense_map.ready_pose[bone])
	for modifier in actor.skeleton.get_children():
		if modifier is SkeletonModifier3D: modifier.active=true
	actor.play_action("idle",0.)
	actor.animator.seek(0.,true)
	defense_map.player=null

func recover_digger(delta: float) -> bool:
	if defense_recipe.is_empty(): return super.recover_digger(delta)
	if defense_map.player==null:
		last_digger.animator.advance(delta)
		return false
	dig_recovery_age+=delta
	sample_attack_dig()
	var blend := smoothstep(.12,.85,dig_recovery_age)
	var rig: Skeleton3D=last_digger.skeleton
	for bone in defense_map.ready_pose.size():
		rig.set_bone_pose(bone,rig.get_bone_pose(bone).interpolate_with(defense_map.ready_pose[bone],blend))
	last_digger.position.y=lerpf(last_digger.position.y,0.,blend)
	if dig_recovery_age>=.85: release_dig_pose()
	return false

func next_serve() -> void:
	release_dig_pose()
	dig_recovery_age=0.
	defense_recipe={}
	defense_at=INF
	defense_contact=-INF
	first_dig_touch=-INF
	super.next_serve()

func bind_contact_motion(mapper: Map,root: Node3D,actor: Node3D,home: Vector3,source: Vector3,best: Dictionary) -> Dictionary:
	return mapper.begin_mapped_motion(root,actor,home,source,best,dig_reach if mapper==defense_map else 0.)

func mapped_touch(mapper: Map,motion: Dictionary,previous: Vector3) -> bool:
	return mapped_segment_touch(mapper,motion,previous,ball.position)

func mapped_segment_touch(mapper: Map,motion: Dictionary,previous: Vector3,end: Vector3) -> bool:
	return mapper.segment_touch(motion,previous,end)

func sample_attack_dig() -> void:
	var offset := dig_clock-defense_at
	var frame := float(defense_recipe.contact)+offset*60.
	if offset<0.:
		var pace := smoothstep(40.,110.,defense_map.feed_kmh)
		var lead := defense_map.incoming_lead_seconds
		var elapsed := maxf(0.,lead+offset)
		# Start at the usual entry pose, then form the platform early and hold it through contact.
		frame=float(defense_recipe.contact)+minf(0.,elapsed*(1.+.8*pace)-lead)*60.
	defense_map.sample_receiver(defense_recipe,clampf(frame,0.,defense_recipe.frames),true,defense_map.legs)

func walk_server(delta: float,defending := false) -> void:
	if defending and defense_map.player!=null:
		sample_attack_dig()
		return
	super.walk_server(delta,defending)

func dig_defender() -> Node3D:
	return hitter

func dig_chases_feed() -> bool:
	return true

func cpu_dig() -> bool:
	return false

func block_on_flight_segment(previous: Vector3) -> bool:
	if phase!="serve_return" or not attack_floor_pending: return false
	var dt := previous.distance_to(ball.position)/maxf(.01,drop_velocity.length())
	dig_clock+=dt
	if defense_recipe.is_empty():
		if not dig_armed(): return false
		var ahead := minf(.32,preload("res://scripts/pass_flight.gd").landing_time(ball.position,drop_velocity))
		var source := pin_hitter.global_position
		var actor := dig_defender()
		var fall := preload("res://scripts/pass_flight.gd").landing_time(ball.position-Vector3.UP*.72,drop_velocity)
		var intercept := ball.position+drop_velocity*fall+Vector3.DOWN*4.905*fall*fall
		if cpu_dig() and dig_chases_feed():
			var facing := (source-actor.position).slide(Vector3.UP).normalized()
			var stance := intercept.slide(Vector3.UP)-facing*.52+Vector3.UP*actor.position.y
			if stance.distance_to(actor.position)>.22:
				move_receiver(actor,stance,dt,source-actor.position,GroundControls.speed(true,true),true)
		var yaw := atan2(source.x-actor.position.x,source.z-actor.position.z)
		var start := (previous-dig_defender().position).rotated(Vector3.UP,-yaw)
		var predicted := ball.position+drop_velocity*ahead+Vector3.DOWN*4.905*ahead*ahead
		var end := (predicted-dig_defender().position).rotated(Vector3.UP,-yaw)
		var first := INF
		var best := {}
		for box in boxes:
			var span := defense_map.zone_interval(start,end,box.bounds)
			if span.y>span.x and span.x<first:
				first=span.x
				best=box
		var lead := maxf(0.,(ahead+dt)*first-dt)
		if best.is_empty():
			var gap := (intercept-actor.position).slide(Vector3.UP).length()
			if not cpu_dig() or fall>.20 or gap>1.75: return false
			var local := (intercept-actor.position).rotated(Vector3.UP,-yaw)
			var cell:=Vector3i(0 if local.x<0. else 2,0,2)
			var assigned:=defense_map.assigned_action(cell,0)
			if assigned<=0: return false
			best={"id":assigned,"cell":cell,"part":0}
			lead=fall
		defense_at=dig_clock+lead
		defense_map.set_intercept=ball.position+drop_velocity*lead+Vector3.DOWN*4.905*lead*lead
		defense_map.incoming_lead_seconds=lead
		defense_map.feed_kmh=drop_velocity.length()*3.6
		defense_recipe=bind_contact_motion(defense_map,defense_anchor,dig_defender(),dig_defender().position,source,best)
		trace("defense_reception_grid",{"clip":defense_recipe.id,"motion_kind":defense_recipe.kind,"cell":str(best.cell)})
	sample_attack_dig()
	var timing_error := dig_contact_error(previous)
	if timing_error<0.: return false
	last_digger=dig_defender()
	dig_incoming=drop_velocity
	var bounds: Vector2=PassAccuracy.spread(timing_error,drop_velocity.length(),received_spin_rps,last_digger.effective_rating("Forearm reception"),false)
	var miss: Vector3=PassAccuracy.sample_offset(bounds)
	var goal := defense_map.pass_goal+miss.slide(Vector3.UP)
	var apex := ball.position.y+maxf(1.,3.4+miss.y)
	var flight := sqrt(2.*(apex-ball.position.y)/9.81)+sqrt(2.*(apex-goal.y)/9.81)
	drop_velocity=(goal-ball.position)/flight+Vector3.UP*4.905*flight
	drop_net_hit.clear()
	hard_spike_floor_pending=false
	floor_linger=0.
	phase="server_dig"
	message.text="Dig"
	trace("mapped_dig",{"actor":last_digger.display_name,"cpu":cpu_dig(),"clip":defense_recipe.id,"contact":defense_contact,"prediction":defense_at,"release":str(dig_platforms[last_digger].pressed_at),"apex":apex,"landing_target":str(goal)})
	return true

func dig_armed() -> bool:
	return true

func dig_contact_error(previous: Vector3) -> float:
	if mapped_touch(defense_map,defense_recipe,previous):
		defense_contact=dig_clock
		if not is_finite(first_dig_touch): first_dig_touch=dig_clock
	if cpu_dig():
		if is_finite(defense_contact): dig_platforms[dig_defender()].queue_bump(dig_clock)
	else: update_dig_feedback()
	var release: float=dig_platforms[dig_defender()].pressed_at
	if not is_finite(defense_contact) or not is_finite(release) or minf(absf(release-defense_at+PASS_RELEASE_LEAD),absf(release-defense_contact+PASS_RELEASE_LEAD))>DIG_WINDOW or absf(defense_contact-dig_clock)>DIG_WINDOW: return -1.
	return clampf(absf(release-defense_at+PASS_RELEASE_LEAD)/DIG_WINDOW,0.,1.)

func update_dig_feedback() -> void:
	var release: float=dig_platforms[dig_defender()].pressed_at
	if not is_finite(release) or not is_finite(defense_at): return
	var measured := is_finite(first_dig_touch)
	var reference := first_dig_touch if measured else defense_at
	if feedback_rally!=replay_rally:
		feedback_rally=replay_rally
		ContactTiming.window("Dig",release-reference+PASS_RELEASE_LEAD,-DIG_WINDOW,DIG_WINDOW,-DIG_PERFECT,DIG_PERFECT,not measured)

func attack_surface_contact(point: Vector3,floor_hit: bool) -> void:
	if phase=="serve_return" and attack_floor_pending and floor_hit:
		trace("mapped_dig_miss",{"assigned":not defense_recipe.is_empty(),"pose_contact":str(defense_contact),"prediction":str(defense_at),"release":str(dig_platforms[dig_defender()].pressed_at),"floor":str(point)})
	super.attack_surface_contact(point,floor_hit)
