extends RefCounted

# All pairs face across the court, on the same side of the net as their partner.
const CENTERS := [Vector3(1.6,.04,-2.9),Vector3(-1.6,.04,1.1),Vector3(-1.6,.04,6.9),Vector3(1.6,.04,10.9)]
const FEED := .72
const TOSS_BANDS := [Vector2(.8,1.15),Vector2(1.4,1.95),Vector2(2.3,3.1)]
const Physics=preload("res://scripts/gym_physics.gd")
const Map=preload("res://scripts/mapped_reception.gd")
var released:Dictionary={}
var touched_at:=-INF
var studio:Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/reception_studio.json"))
var zones:Array[Dictionary]=[]
var pairs:Array[Dictionary]=[]
var game
var score:=0
var holding:=false
var needs_release:=false
var pressed_at:=INF
var feedback:Label
var finished:=false
var demonstrating:=false
var moving:=false
var pass_target:Node3D
var base:=Vector3.ZERO
var chase:=Vector3.ZERO
var focus_cued:=false
var steps:RefCounted
const Ground=preload("res://scripts/player_ground_controls.gd")

func configure(host,readout:Label,completed:int) -> void:
	game=host
	feedback=readout
	score=clampi(completed,0,5)
	var athletes:Array=host.rotation_drill.roster.duplicate()
	for worker in host.rotation_drill.workers: athletes.append(worker.actor)
	if demonstrating:
		var human=athletes[0]
		athletes[0]=athletes[8]
		athletes[8]=human
	if moving:
		pass_target=athletes[1]
		pass_target.position=Vector3(.9,.04,2.85)
		pass_target.rotation.y=PI
		for slot in range(2,8):
			athletes[slot].position=Vector3(5.65,.04,-4.+slot*.86)
			athletes[slot].rotation.y=-PI*.5
	for i in (1 if moving else 4):
		var receiver:Node3D=athletes[2*i]
		var feeder:Node3D=host.coach if moving else athletes[2*i+1]
		var direction:=Vector3.RIGHT if i%2==0 else Vector3.LEFT
		receiver.position=Vector3(0,.04,CENTERS[i].z)-direction*4.25
		feeder.position=Vector3(0,.04,CENTERS[i].z)+direction*4.25
		receiver.rotation.y=atan2(direction.x,direction.z)
		feeder.rotation.y=receiver.rotation.y+PI
		if moving:
			receiver.position=Vector3(-2.75,.04,-2.65)
			feeder.position=Vector3(2.7,.04,10.8)
			receiver.look_at(feeder.position,Vector3.UP,true)
			feeder.look_at(receiver.position,Vector3.UP,true)
			base=receiver.position
			steps=preload("res://scripts/directional_footwork.gd").new(receiver)
		# The coach toss is authored from the relaxed standing idle.
		feeder.play_action("base/Idle",0.)
		feeder.animator.advance(.18)
		var author:RefCounted=feeder.get_pose_author()
		for id in feeder.skeleton.get_bone_count(): author.baseline[id]=feeder.skeleton.get_bone_pose(id)
		var orb:MeshInstance3D=host.ball if i==0 else MeshInstance3D.new()
		if i!=0:
			orb.mesh=host.ball.mesh
			orb.material_override=host.ball.material_override
			host.world.add_child(orb)
		orb.show()
		var mapper:=Map.new()
		host.world.add_child(mapper)
		var anchor:=Node3D.new()
		host.world.add_child(anchor)
		mapper.pose_origin=anchor
		mapper.defenders.append(anchor)
		mapper.clips=studio
		if zones.is_empty(): zones=mapper.assigned_boxes()
		var outcomes:=preload("res://scripts/demo_outcomes.gd").new(25)
		pairs.append({"bands":[],"last_band":-1,"rise":randf_range(2.35,3.05),"outcomes":outcomes,"cpu_misses":outcomes.next_misses(),"receiver":receiver,"feeder":feeder,"ball":orb,"age":-i*.21,"caught":false,"platform":receiver.global_position+Vector3.UP,"home":receiver.global_transform,"mapper":mapper,"zone_step":i,"motion":{},"flying":false,"hit":false,"swing":false,"origin":hands(feeder)})
		choose_toss(pairs.back())
	athletes[8].position=Vector3(-5.3,.04,2.)
	feedback.text="%d / 5 passes"%score
	if score==5: complete()

func choose_toss(pair:Dictionary) -> void:
	if pair.bands.is_empty():
		pair.bands.assign([0,1,2])
		pair.bands.shuffle()
		if pair.bands.back()==pair.last_band: pair.bands.reverse()
	pair.last_band=pair.bands.pop_back()
	var band:Vector2=TOSS_BANDS[pair.last_band]
	pair.toss_rise=randf_range(band.x,band.y)
	if moving: pair.toss_rise=maxf(2.75,pair.toss_rise+.65)
	pair.flight_time=sqrt(8.*pair.toss_rise/9.81)

func plan_reception(pair:Dictionary) -> void:
	var mapper:Map=pair.mapper
	var receiver:Node3D=pair.receiver
	receiver.global_transform=pair.home
	# Work through center, side, low and high feeds in receiver-local space.
	var lanes:=[Vector3(0,1.05,.55),Vector3(.62,.9,.55),Vector3(-.65,.42,.75),Vector3(0,1.85,.42),Vector3(-.68,1.15,.45),Vector3(.68,.45,.7)]
	var aim:Vector3=lanes[int(pair.zone_step)%lanes.size()]
	pair.zone_step+=1
	var best:Dictionary={}
	var distance:=INF
	for zone in zones:
		var bounds:AABB=zone.bounds
		var error:=aim.distance_squared_to(aim.clamp(bounds.position,bounds.end))
		if error<distance:
			best=zone
			distance=error
	var bounds:AABB=best.bounds
	var local:=aim.clamp(bounds.position+Vector3.ONE*.001,bounds.end-Vector3.ONE*.001)
	mapper.set_intercept=receiver.to_global(local)
	mapper.incoming_lead_seconds=float(pair.flight_time)
	mapper.pass_goal=pass_target.global_position+Vector3.UP*1.8 if moving else pair.feeder.global_position
	mapper.pass_rise=pair.rise
	mapper.feed_kmh=3.6*pair.origin.distance_to(mapper.set_intercept)/(float(pair.flight_time))
	pair.motion=mapper.begin_mapped_motion(mapper.pose_origin,receiver,receiver.global_position,pair.origin,best,0.)
	mapper.sample_receiver(pair.motion,pair.motion.contact,true,mapper.legs)
	pair.platform=mapper.platform_center(pair.motion)
	mapper.sample_receiver(pair.motion,0.,false,mapper.legs)
	if moving:
		# Lock the feed at release; moving the passer only moves the pose anchor.
		var angle:=randf()*TAU
		var landing:=base+Vector3(cos(angle),0,sin(angle))*randf_range(.8,1.85)
		landing.x=clampf(landing.x,-4.2,4.2)
		landing.z=clampf(landing.z,-4.7,2.7)
		chase=base+(landing-Vector3(pair.platform.x,base.y,pair.platform.z))
		pair.platform.x=landing.x
		pair.platform.z=landing.z
		mapper.set_intercept+=chase-base
		receiver.global_transform=pair.home
	game.trace("pepper_grid",{"region":mapper.region_number(best.cell,best.part),"animation":pair.motion.id,"kind":pair.motion.kind,"receiver":receiver.display_name})

func start_human_turn() -> void:
	demonstrating=false
	var pair:=pairs[0]
	var demo:Node3D=pair.receiver
	var human:Node3D=game.setter
	human.global_position=pair.home.origin
	human.rotation.y=atan2(pair.feeder.position.x-human.position.x,pair.feeder.position.z-human.position.z)
	pair.home=human.global_transform
	demo.global_basis=Basis(Vector3.UP,PI*.5)
	demo.position=Vector3(-game.gym.FRONT_BENCH_X,.04,-2.9)
	for modifier in demo.skeleton.get_children():
		if modifier is SkeletonModifier3D: modifier.active=true
	demo.play_action("base/Sitting_Talking",0.)
	demo.animator.seek(.62,true)
	var seat:=preload("res://scripts/bleacher_seat.gd").new()
	seat.configure(demo,game.gym.benches[0],null,-1,-2.9)
	game.seats_in_use.append(seat)
	pair.receiver=human
	if moving:
		base=human.position
		steps=preload("res://scripts/directional_footwork.gd").new(human)
		focus_cued=false
	pair.motion={}
	pair.zone_step=0
	human.play_action("idle",0.)
	pair.age=0.
	pair.hit=false
	pair.caught=false
	pair.swing=false
	pair.flying=false

func hands(actor:Node3D) -> Vector3:
	var physics=preload("res://scripts/gym_physics.gd")
	return (physics.joint(actor,"hand_l")+physics.joint(actor,"hand_r"))*.5+Vector3.UP*.075

func release_state() -> Dictionary:
	var pair:=pairs[0]
	var axis:Vector3=(pair.platform-pair.origin).slide(Vector3.UP).normalized()
	var speed:=maxf(1.,absf((pair.platform-pair.origin).dot(axis))/(float(pair.flight_time)))
	return Map.release_grade(pair.ball.position.dot(axis),Physics.joint(pair.receiver,"Head").dot(axis)-.09,pair.platform.dot(axis),speed,pair.age-touched_at<=.095)

func meter() -> Dictionary:
	if finished or demonstrating or pairs.is_empty() or (not holding and released.is_empty()): return {}
	var state:=release_state() if released.is_empty() else released
	return {"value":state.value,"perfect":Vector2(.33,.67),"contact":Vector2(.08,.90),"released":not released.is_empty()}

func button(down:bool) -> void:
	if finished or demonstrating: return
	if not down and holding and not needs_release and not pairs[0].caught and released.is_empty(): released=release_state()

	if not down: needs_release=false
	if down and not holding: pressed_at=pairs[0].age
	holding=down

func move_passer(pair:Dictionary,dt:float) -> bool:
	var actor:Node3D=pair.receiver
	var focused:bool=demonstrating or Ground.focus(game.axis)
	var stick:=Vector2(game.axis(JOY_AXIS_LEFT_X),game.axis(JOY_AXIS_LEFT_Y))
	if stick.length()<.15: stick=Vector2.ZERO
	stick+=Input.get_vector("ui_left","ui_right","ui_up","ui_down")
	stick+=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	var velocity:=Vector3(-stick.x,0,-stick.y).limit_length(1.)*Ground.speed(focused,false)
	if demonstrating:
		velocity=(chase-base).limit_length(dt*2.9)/maxf(.001,dt) if pair.flying and not pair.caught else Vector3.ZERO
	base+=velocity*dt
	base.x=clampf(base.x,-4.4,4.4)
	base.z=clampf(base.z,-4.9,3.)
	pair.home.origin=base
	if not pair.swing:
		actor.global_position=base
		if focused: Ground.face(actor,pair.feeder.position-base,dt)
		elif velocity.length()>.1: Ground.face(actor,velocity,dt)
		pair.home.basis=actor.global_basis
		if focused: actor.play_action("idle",.14)
		else: actor.play_travel_gait(velocity)
		Ground.shuffle(actor,steps,velocity,focused,dt)
	if pair.flying: pair.mapper.pose_origin.global_position=base
	var toward:Vector3=(pair.feeder.position-base).slide(Vector3.UP).normalized()
	return focused and actor.global_basis.z.normalized().dot(toward)>.93

func tick(delta:float) -> void:
	if finished: return
	for i in pairs.size():
		var pair:=pairs[i]
		if moving:
			var facing:=move_passer(pair,delta)
			if not demonstrating and not pair.flying and not focus_cued:
				game.moving_prompt(true)
				focus_cued=true
			if not facing and not pair.flying and not demonstrating:
				pair.age=0.
				pair.ball.position=game.coach_motion.toss(pair.feeder,0.)
				continue
		pair.age+=delta
		var t:float=pair.age
		var arrival:float=FEED+pair.flight_time
		var orb:MeshInstance3D=pair.ball
		var receiver:Node3D=pair.receiver
		var feeder:Node3D=pair.feeder
		var human:=i==0 and not demonstrating
		var previous:=orb.position
		var active:bool=not pair.cpu_misses if demonstrating or i!=0 else (holding or not released.is_empty()) and not needs_release
		if t<FEED:
			pair.origin=game.coach_motion.toss(feeder,clampf((t-FEED+.30)/.30,0.,1.))
			orb.position=pair.origin
		else:
			if not pair.flying:
				pair.flying=true
				if moving and human: game.moving_prompt(false)
				pair.origin=game.coach_motion.toss(feeder,1.)
				plan_reception(pair)
			if t<FEED+.16: game.coach_motion.toss(feeder,1.)
			elif t<arrival:
				feeder.play_action("base/Idle",.18)
				feeder.animator.advance(delta)
			if not pair.caught:
				var u:float=(t-FEED)/(float(pair.flight_time))
				orb.position=pair.origin.lerp(pair.platform,u)+Vector3.UP*4.*float(pair.toss_rise)*u*(1.-u)
			var mapper:Map=pair.mapper
			var frame:=clampf(pair.motion.contact+60.*(t-arrival),0.,pair.motion.frames)
			if active: pair.swing=true
			if pair.swing: mapper.sample_receiver(pair.motion,frame,true,mapper.legs)
			if human and active and not pair.caught and mapper.segment_touch(pair.motion,previous,orb.position): touched_at=t
			var human_hit:=human and not released.is_empty() and bool(released.playable) and t-touched_at<=.095
			if not pair.caught and (human_hit or t>=arrival+(.14 if human else 0.)):
				if human: active=human_hit
				pair.contact_age=t
				pair.contact_point=orb.position
				pair.caught=true
				pair.hit=active
				if i==0 and demonstrating: game.coach_react("praise" if active else "miss")
				if i==0 and not demonstrating:
					game.coach_react("praise" if active else "miss")
					if active:
						score+=1
						var grade:String=released.grade
						feedback.text="%d / 5 passes   ·   %s"%[score,grade]
						CareerSession.checkpoint("moving_reception" if moving else "pepper",score)
					else: feedback.text="%d / 5 passes   ·   Missed"%score
			if pair.caught:
				var u:=clampf((t-float(pair.contact_age))/sqrt(8.*float(pair.rise)/9.81),0.,1.)
				if pair.hit:
					var catch_at:Vector3=game.coach_motion.toss(pass_target if moving else feeder,0.)
					orb.position=game.arc(pair.contact_point,catch_at,u,pair.rise)
				else:
					orb.position=pair.contact_point.lerp(receiver.position+receiver.basis.z*-.42+Vector3.UP*.105,minf(1.,u*2.))
		if not pair.flying: receiver.animator.advance(delta)
		if t>=arrival+1.93:
			choose_toss(pair)
			pair.rise=randf_range(2.35,3.05)
			if human:
				focus_cued=false
				released.clear()
				touched_at=-INF
			if demonstrating or i!=0: pair.cpu_misses=pair.outcomes.next_misses()
			if i==0 and score>=5:
				complete()
				return
			pair.age=0.
			pair.hit=false
			pair.caught=false
			pair.swing=false
			pair.flying=false
			receiver.global_transform=pair.home
			receiver.play_action("idle",.16)
			if i==0: needs_release=holding

func complete() -> void:
	finished=true
	CareerSession.checkpoint("moving_reception_complete" if moving else "pepper_complete",5)
	feedback.text="Moving reception complete   /   5 passes to setter" if moving else "Pepper complete   /   5 passes"
	game.finish_pepper()
