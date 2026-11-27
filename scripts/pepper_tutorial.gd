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
var attempts:=0
var turn_makes:=0
var waiting:Array[Node3D]=[]
var holding:=false
var needs_release:=false
var pressed_at:=INF
var feedback:Label
var finished:=false
var demonstrating:=false
var moving:=false
# From the near baseline, positive X is left. Five is the left backcourt.
const FIVE_MIN:=Vector2(.65,-2.45)
const FIVE_MAX:=Vector2(3.85,1.45)
const FIVE_HOME:=preload("res://scripts/player_ground_controls.gd").BACK_LEFT
var final_deposit:=false
var cart_service:=preload("res://scripts/reception_cart_service.gd").new()
const SETTER_TWO_AND_HALF:=Vector3(-1.5,.04,2.85)
var pin_collector:Node3D
var pass_target:Node3D
var base:=Vector3.ZERO
var chase:=Vector3.ZERO
var human_steps:RefCounted
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
		pass_target.position=SETTER_TWO_AND_HALF
		pass_target.rotation.y=PI
		pin_collector=athletes[2]
		pin_collector.position=Vector3(4.1,.04,2.5)
		pin_collector.look_at(pass_target.position,Vector3.UP,true)
		for slot in range(3,8):
			waiting.append(athletes[slot])
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
			receiver.position=FIVE_HOME
			feeder.position=Vector3(2.7,.04,10.8)
			receiver.look_at(feeder.position,Vector3.UP,true)
			feeder.look_at(receiver.position,Vector3.UP,true)
			var cart:Node3D=host.rotation_drill.basket
			cart.rotation.y=feeder.rotation.y
			cart.position=feeder.to_global(Vector3(.90,0.,.13))
			cart.show()
			for stored in host.rotation_drill.stock:
				stored.position=host.rotation_drill.cart_slot(cart,stored.get_meta("cart_slot"))
				stored.show()
			cart_service.configure(host.rotation_drill,pin_collector,feeder)
			cart_service.home_dock=pin_collector.position+Vector3(.95,0,0)
			host.rotation_drill.bins[0].position=cart_service.home_dock
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
		var prediction:=projected_landing.bind(pairs.back())
		if i==0: host.landing_ring.location=prediction
		else: preload("res://scripts/ball_landing_marker.gd").attach(orb,prediction)
		choose_toss(pairs.back())
		choose_return(pairs.back(),demonstrating or i!=0)
	athletes[8].position=Vector3(-5.3,.04,2.)
	feedback.text="%d / 5 passes"%score
	if score==5:
		if moving: host.call_deferred("start_setting_lesson")
		else: complete()

func projected_landing(pair:Dictionary) -> Vector3:
	if pair.has("pin_end"):
		return preload("res://scripts/ball_landing_marker.gd").parabola(pair.return_end,pair.pin_end,1.15,1.65)
	if not pair.flying or pair.ball.position.y<=.15: return Vector3.INF
	var marker=preload("res://scripts/ball_landing_marker.gd")
	if not pair.caught or not pair.hit:
		return marker.parabola(pair.origin,pair.platform,pair.flight_time,pair.toss_rise)
	if not pair.has("return_end"): return Vector3.INF
	var duration:=sqrt(8.*float(pair.rise)/9.81)
	if pair.age>=pair.contact_age+duration: return Vector3.INF
	return marker.parabola(pair.contact_point,pair.return_end,duration,pair.rise)

const Accuracy=preload("res://scripts/reception_accuracy.gd")

func choose_return(pair:Dictionary,_cpu:bool) -> void:
	pair.rise=Accuracy.IDEAL_APEX-1.5

func pass_skill(pair:Dictionary) -> float:
	return pair.receiver.effective_rating("Hand reception" if pair.motion.get("kind","")=="overhead" else "Forearm reception")

func plan_return(pair:Dictionary,timing:float) -> void:
	var target:Vector3=Physics.joint(pass_target,"Head")+Vector3.UP*.21 if moving else game.coach_motion.toss(pair.feeder,0.)
	var spread:=Accuracy.spread(timing,pair.mapper.feed_kmh/3.6,0.,pass_skill(pair),false)
	var miss:=Accuracy.sample_offset(spread)
	pair.return_end=target+miss.slide(Vector3.UP)
	if moving: pair.catch_stance=pass_target.position+miss.slide(Vector3.UP)
	var peak:=maxf(maxf(pair.contact_point.y,target.y)+.15,Accuracy.IDEAL_APEX+miss.y)
	var duration:=sqrt(2.*(peak-pair.contact_point.y)/9.81)+sqrt(2.*(peak-target.y)/9.81)
	pair.rise=9.81*duration*duration/8.

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
	var entry_root:=receiver.global_transform
	receiver.global_transform=pair.home
	# Work through center, side, low and high feeds in receiver-local space.
	var lanes:=[Vector3(0,1.05,.55),Vector3(.08,2.17,.67),Vector3(-.65,.42,.75),Vector3(-.08,1.98,.68),Vector3(-.68,1.15,.45),Vector3(.68,.45,.7)]
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
		# Constrain the untouched ball's floor landing as well as its playable contact.
		var curve:float=4.*pair.toss_rise
		var slope:float=pair.platform.y-pair.origin.y+curve
		var floor_u:float=(slope+sqrt(slope*slope+4.*curve*(pair.origin.y-.15)))/(2.*curve)
		var source_xz:=Vector2(pair.origin.x,pair.origin.z)
		var low:=FIVE_MIN.max(source_xz.lerp(Vector2(-4.30,-4.80),1./floor_u))
		var high:=FIVE_MAX.min(source_xz.lerp(Vector2(4.30,3.80),1./floor_u))
		var landing:=Vector3(clampf(base.x,low.x,high.x),base.y,clampf(base.z,low.y,high.y))
		for attempt in 32:
			var candidate:=Vector3(randf_range(low.x,high.x),base.y,randf_range(low.y,high.y))
			if candidate.distance_to(base)<=1.85:
				landing=candidate
				break
		pair.floor_u=floor_u
		chase=base+(landing-Vector3(pair.platform.x,base.y,pair.platform.z))
		pair.platform.x=landing.x
		pair.platform.z=landing.z
		mapper.set_intercept+=chase-base
		receiver.global_transform=pair.home
	receiver.global_transform=entry_root
	for bone in mapper.entry_pose.size(): receiver.skeleton.set_bone_pose(bone,mapper.entry_pose[bone])
	game.trace("pepper_grid",{"region":mapper.region_number(best.cell,best.part),"animation":pair.motion.id,"kind":pair.motion.kind,"receiver":receiver.display_name})

func start_human_turn() -> void:
	demonstrating=false
	attempts=maxi(int(CareerSession.data.get_value(CareerSession.key(),"moving_attempts",score)),score) if moving else 0
	turn_makes=score
	var pair:=pairs[0]
	choose_return(pair,false)
	var demo:Node3D=pair.receiver
	var human:Node3D=game.setter
	if moving:
		if pair.has("outgoing"):
			# Finish the previous exchange before bringing the human onto court.
			pair.deferred_entry=true
			demonstrating=true
			return
		pair.outgoing=demo
		pair.sideline=human.position
		pair.exit_lane=Vector3(human.position.x+.8,human.position.y,demo.position.z-1.)
		for modifier in demo.skeleton.get_children():
			if modifier is SkeletonModifier3D: modifier.active=true
		base=human.position
		pair.home=human.global_transform
		steps=preload("res://scripts/directional_footwork.gd").new(human)
		focus_cued=false
	else:
		human.global_position=pair.home.origin
		human.rotation.y=atan2(pair.feeder.position.x-human.position.x,pair.feeder.position.z-human.position.z)
		pair.home=human.global_transform
		demo.global_basis=Basis(Vector3.UP,PI*.5)*Basis.from_scale(demo.global_basis.get_scale().abs())
		demo.position=Vector3(-game.gym.FRONT_BENCH_X,.04,-2.9)
		for modifier in demo.skeleton.get_children():
			if modifier is SkeletonModifier3D: modifier.active=true
		demo.play_action("base/Sitting_Talking",0.)
		demo.animator.seek(.62,true)
		var seat:=preload("res://scripts/bleacher_seat.gd").new()
		seat.configure(demo,game.gym.benches[0],null,-1,-2.9)
		game.seats_in_use.append(seat)
	pair.receiver=human
	pair.erase("reset_to_five")
	pair.erase("follow_heading")
	pair.erase("release_pose")
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
	return Map.release_grade(pair.ball.position.dot(axis),Physics.joint(pair.receiver,"Head").dot(axis)-.09,pair.platform.dot(axis),speed,pair.age-touched_at<=.095,pass_skill(pair))

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

func human_velocity(focused:bool) -> Vector3:
	var stick:=Vector2(game.axis(JOY_AXIS_LEFT_X),game.axis(JOY_AXIS_LEFT_Y))
	if stick.length()<.15: stick=Vector2.ZERO
	stick+=Input.get_vector("ui_left","ui_right","ui_up","ui_down")
	stick+=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	return Vector3(-stick.x,0,-stick.y).limit_length(1.)*Ground.speed(focused,Ground.sprint(game.axis))

func move_off_turn(dt:float) -> void:
	var actor:Node3D=game.setter
	if human_steps==null: human_steps=preload("res://scripts/directional_footwork.gd").new(actor)
	var focused:=Ground.focus(game.axis)
	var velocity:=human_velocity(focused)
	actor.position=human_bounds(actor.position+velocity*dt)
	if focused: Ground.face(actor,game.coach.position-actor.position,dt)
	elif velocity.length()>.1: Ground.face(actor,velocity,dt)
	if focused: actor.play_action("idle",.14)
	else: actor.play_travel_gait(velocity)
	actor.animator.advance(dt)
	Ground.shuffle(actor,human_steps,velocity,focused,dt)

func human_bounds(point:Vector3) -> Vector3:
	return Vector3(clampf(point.x,-6.,6.),point.y,clampf(point.z,-5.8,3.65))

func move_passer(pair:Dictionary,dt:float) -> bool:
	var actor:Node3D=pair.receiver
	var focused:bool=demonstrating or Ground.focus(game.axis)
	var velocity:=human_velocity(focused)
	if demonstrating:
		velocity=(chase-base).limit_length(dt*2.9)/maxf(.001,dt) if pair.flying and not pair.caught else Vector3.ZERO
	base+=velocity*dt
	if demonstrating:
		base.x=clampf(base.x,-4.4,4.4)
		base.z=clampf(base.z,-4.9,3.)
	else:
		base=human_bounds(base)
		if pair.has("release_pose"):
			var shift:Vector3=base-pair.home.origin
			var recovery_root:Transform3D=pair.release_root
			recovery_root.origin+=shift
			pair.release_root=recovery_root
	pair.home.origin=base
	if not pair.swing:
		actor.global_position=base
		if focused: Ground.face(actor,pair.feeder.position-base,dt)
		elif velocity.length()>.1: Ground.face(actor,velocity,dt)
		pair.home.basis=actor.global_basis
		if focused: actor.play_action("idle",.14)
		else: actor.play_travel_gait(velocity)
		actor.animator.advance(dt)
		Ground.shuffle(actor,steps,velocity,focused,dt)
	if pair.flying: pair.mapper.pose_origin.global_position=base
	var toward:Vector3=(pair.feeder.position-base).slide(Vector3.UP).normalized()
	return focused and actor.global_basis.z.normalized().dot(toward)>.93

# Sample the idle underneath the captured procedural pose so unkeyed bones
# and the player's placement both follow a continuous recovery.
func recover_receiver(pair:Dictionary,dt:float) -> void:
	var actor:Node3D=pair.receiver
	var rig:Skeleton3D=actor.skeleton
	if not pair.has("release_pose"):
		var pose:Array[Transform3D]=[]
		for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
		pair.release_pose=pose
		pair.recovery_age=0.
		pair.release_root=actor.global_transform
		if moving:
			base=Vector3(actor.position.x,base.y,actor.position.z)
			pair.home.origin=base
		actor.play_action("idle",0.)
	pair.recovery_age+=dt
	var blend:=smoothstep(0.,.70,float(pair.recovery_age))
	actor.animator.advance(dt)
	# Interpolating opposite-handed bases drives all three scale axes through zero.
	var start_root:Transform3D=pair.release_root
	if moving and (demonstrating or Ground.focus(game.axis)):
		# Follow the departing pass briefly, then ease the gaze back to the feeder.
		var age:float=pair.recovery_age
		var to_ball:Vector3=pair.ball.position-actor.position
		var to_coach:Vector3=pair.feeder.position-actor.position
		var desired:=lerp_angle(atan2(to_ball.x,to_ball.z),atan2(to_coach.x,to_coach.z),smoothstep(.08,.70,age))
		var heading:float=pair.get("follow_heading",atan2(start_root.basis.z.x,start_root.basis.z.z))
		var turn:=angle_difference(heading,desired)
		heading+=clampf(turn*(1.-exp(-dt*6.)),-2.4*dt,2.4*dt)
		pair.follow_heading=heading
		pair.home.basis=Basis(Vector3.UP,heading)*Basis.from_scale(pair.home.basis.get_scale().abs())
	var end_root:Transform3D=pair.home
	if start_root.basis.determinant()*end_root.basis.determinant()<0.:
		end_root.basis.x=-end_root.basis.x
	actor.global_transform=start_root.interpolate_with(end_root,blend)
	if blend==1.: actor.global_transform=pair.home
	if blend<1.:
		for bone in rig.get_bone_count():
			var start:Transform3D=pair.release_pose[bone]
			rig.set_bone_pose(bone,start.interpolate_with(rig.get_bone_pose(bone),blend))

func square_up(actor:Node3D,target:Vector3,dt:float) -> bool:
	var direction:=(target-actor.position).slide(Vector3.UP).normalized()
	var yaw:=atan2(direction.x,direction.z)
	var difference:=angle_difference(actor.rotation.y,yaw)
	actor.rotation.y+=clampf(difference*(1.-exp(-dt*7.)),-2.8*dt,2.8*dt)
	return actor.global_basis.z.normalized().dot(direction)>.995

func walk_rotation(actor:Node3D,destination:Vector3,dt:float) -> bool:
	var toward:=destination-actor.position
	if toward.length()<.015:
		actor.play_action("idle",.18)
		actor.animator.advance(dt)
		return true
	# Brake before the mark so the last stride can plant.
	var speed:=minf(3.5,sqrt(2.*5.5*toward.length()))
	var velocity:=toward.normalized()*speed
	Ground.face(actor,toward,dt)
	actor.play_travel_gait(velocity)
	actor.animator.advance(dt)
	actor.position=actor.position.move_toward(destination,velocity.length()*dt)
	return false

func tick(delta:float) -> void:
	if finished: return
	for i in pairs.size():
		var pair:=pairs[i]
		if final_deposit:
			move_off_turn(delta)
			if cart_service.busy(delta): return
			finished=true
			game.start_setting_lesson()
			return
		var facing:=true
		if moving:
			if pair.receiver==game.setter: facing=move_passer(pair,delta)
			else: move_off_turn(delta)
			for teammate in waiting:
				if teammate!=pair.get("outgoing"): Ground.face(teammate,pair.receiver.position-teammate.position,delta)
			var cart=game.rotation_drill
			if pair.has("outgoing"):
				var old:Node3D=pair.outgoing
				var exit_goal:Vector3=pair.sideline
				if pair.has("exit_lane"):
					exit_goal=pair.exit_lane
					if walk_rotation(old,exit_goal,delta): pair.erase("exit_lane")
				var outgoing_done:=false
				if not pair.has("exit_lane"): outgoing_done=old==game.setter or walk_rotation(old,pair.sideline,delta)
				var incoming_done:bool=pair.receiver==game.setter or walk_rotation(pair.receiver,base,delta)
				if outgoing_done and incoming_done:
					if pair.receiver!=game.setter and not square_up(pair.receiver,pair.feeder.position,delta): continue
					if old!=game.setter: Ground.face(old,pair.receiver.position-old.position,delta)
					pair.home=pair.receiver.global_transform
					pair.erase("outgoing")
					if pair.erase("deferred_entry"): start_human_turn()
				continue
			if pair.get("reset_to_five",false):
				var ready_spot:=FIVE_HOME
				if not walk_rotation(pair.receiver,ready_spot,delta): continue
				if pair.receiver!=game.setter and not square_up(pair.receiver,pair.feeder.position,delta): continue
				base=ready_spot
				pair.home=pair.receiver.global_transform
				pair.erase("reset_to_five")
			cart_service.receiver=pair.receiver
			if cart_service.busy(delta):
				if pair.receiver!=game.setter: pair.receiver.animator.advance(delta)
				continue
			if not pair.flying and pass_target.position.distance_to(SETTER_TWO_AND_HALF)>.04:
				var home_velocity:Vector3=pass_target.position.direction_to(SETTER_TWO_AND_HALF)*2.8
				pass_target.play_travel_gait(home_velocity)
				pass_target.animator.advance(delta)
				pass_target.position=pass_target.position.move_toward(SETTER_TWO_AND_HALF,2.8*delta)
			if not pair.flying and not cart.issued:
				pair.ball.hide()
				cart.prepare_next_ball(delta)
				if not cart.take_ball():
					if pair.receiver!=game.setter: pair.receiver.animator.advance(delta)
					continue
			if pair.receiver!=game.setter: facing=move_passer(pair,delta)
			if not demonstrating and not pair.flying and not focus_cued:
				game.moving_prompt(true)
				focus_cued=true
			var position_xz:=Vector2(base.x,base.z)
			var in_range:=position_xz.distance_to(position_xz.clamp(FIVE_MIN,FIVE_MAX))<=.6
			if not demonstrating and not pair.flying and not in_range:
				feedback.text="Return to zone 5 to receive"
			elif not demonstrating and not pair.flying:
				feedback.text="%d / 5 passes to setter"%score
			if not pair.flying and (not facing or (not demonstrating and not in_range)):
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
		var active:bool=(moving or not pair.cpu_misses) if demonstrating or i!=0 else (holding or not released.is_empty()) and not needs_release
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
			# The mapped contact pose takes over only for the final approach.
			# Until then the feet keep the regular LT shuffle while chasing a toss.
			var preparing:=not moving or t>=arrival-.40
			if active and preparing and not pair.swing:
				# The human can begin preparing mid-flight. Blend from the pose
				# actually on screen when they press, even on a late pickup.
				mapper.entry_frame=frame
				mapper.entry_duration=clampf(pair.motion.contact-frame,1.,9.)
				mapper.entry_pose.clear()
				for bone in receiver.skeleton.get_bone_count(): mapper.entry_pose.append(receiver.skeleton.get_bone_pose(bone))
				mapper.entry_position=mapper.pose_origin.to_local(receiver.global_position)
				var forward:Vector3=mapper.pose_origin.global_basis.inverse()*receiver.global_basis.z
				mapper.entry_yaw=atan2(forward.x,forward.z)
				pair.swing=true
			if pair.swing and (not pair.caught or t<float(pair.contact_age)+.45): mapper.sample_receiver(pair.motion,frame,true,mapper.legs)
			elif pair.swing:
				recover_receiver(pair,delta)
			if active and not pair.caught and mapper.segment_touch(pair.motion,previous,orb.position): touched_at=t
			var human_hit:=human and not released.is_empty() and bool(released.playable) and t-touched_at<=.095
			var cpu_touch:=not human and moving and touched_at==t
			if not pair.caught and (human_hit or cpu_touch or t>=arrival+(.14 if human or moving else 0.)):
				if human: active=human_hit
				elif moving: active=cpu_touch
				pair.contact_age=t
				pair.contact_point=orb.position
				pair.caught=true
				pair.hit=active
				if active:
					var timing:=absf(t-arrival)/.21
					if human: timing=0. if released.grade=="Perfect" else absf(float(released.offset))/.21
					plan_return(pair,timing)
				if i==0:
					attempts+=1
					if moving and human: CareerSession.data.set_value(CareerSession.key(),"moving_attempts",attempts)
					if active: turn_makes+=1
					else: game.coach_react("miss")
				if i==0 and not demonstrating:
					if active:
						score+=1
						var grade:String=released.grade
						feedback.text="%d / 5 passes   ·   %s"%[score,grade]
						CareerSession.checkpoint("moving_reception" if moving else "pepper",score)
					else: feedback.text="%d / 5 passes   ·   Missed"%score
			if pair.caught:
				var u:=clampf((t-float(pair.contact_age))/sqrt(8.*float(pair.rise)/9.81),0.,1.)
				if pair.hit:
					orb.position=game.arc(pair.contact_point,pair.return_end,u,pair.rise)
					if moving:
						var dt_set:float=t-pair.contact_age-sqrt(8.*float(pair.rise)/9.81)
						var catch_spot:Vector3=pair.catch_stance
						if pass_target.position.distance_to(catch_spot)>.04:
							var velocity:=pass_target.position.direction_to(catch_spot)*2.8
							pass_target.play_travel_gait(velocity)
							pass_target.animator.advance(delta)
							pass_target.position=pass_target.position.move_toward(catch_spot,delta*2.8)
						var pin:Vector3=hands(pin_collector)
						Ground.face(pass_target,pin-pass_target.position,delta)
						if dt_set>-.35:
							game.Hands.standing_set(pass_target,pair.return_end,pin-pair.return_end,(pin-pair.return_end+Vector3.UP*7.).normalized(),dt_set,smoothstep(-.35,0.,dt_set))
						if dt_set>=0.:
							if not pair.has("pin_end"): pair.pin_end=pin
							orb.position=game.arc(pair.return_end,pair.pin_end,clampf(dt_set/1.15,0.,1.),1.65)
				elif moving:
					var fall:float=minf(pair.floor_u,(t-FEED)/pair.flight_time)
					orb.position=pair.origin.lerp(pair.platform,fall)+Vector3.UP*4.*float(pair.toss_rise)*fall*(1.-fall)
				else:
					orb.position=pair.contact_point.lerp(receiver.position+receiver.basis.z*-.42+Vector3.UP*.105,minf(1.,u*2.))
		if not moving and not pair.flying: receiver.animator.advance(delta)
		var settled:bool=pair.caught and t>=pair.contact_age+sqrt(8.*float(pair.rise)/9.81)+(1.2 if moving and pair.hit else .25)
		if settled and t>=arrival+1.93:
			if moving and game.rotation_drill.issued:
				cart_service.receive(game.rotation_drill.issued,pair.ball.position,pair.hit)
				pair.ball.hide()
				game.rotation_drill.issued=null
			choose_toss(pair)
			choose_return(pair,not human)
			if human:
				focus_cued=false
				released.clear()
				touched_at=-INF
			if demonstrating or i!=0: pair.cpu_misses=pair.outcomes.next_misses()
			if moving and human and score>=5:
				CareerSession.data.erase_section_key(CareerSession.key(),"moving_attempts")
				game.coach_react("praise")
				final_deposit=true
				return
			if moving and not human and attempts>=5:
				if turn_makes==5: game.coach_react("praise")
				var next:Node3D=waiting.pop_front()
				var sideline:=next.global_position
				pair.outgoing=receiver
				pair.sideline=sideline
				if not human: pair.exit_lane=Vector3(sideline.x-.8,sideline.y,receiver.position.z-1.)
				for modifier in receiver.skeleton.get_children():
					if modifier is SkeletonModifier3D: modifier.active=true
				receiver.play_action("idle",.16)
				if not human: waiting.append(receiver)
				pair.receiver=next
				receiver=next
				base=FIVE_HOME
				pair.home=receiver.global_transform
				steps=preload("res://scripts/directional_footwork.gd").new(receiver)
				demonstrating=true
				attempts=0
				turn_makes=0
				touched_at=-INF
			if not moving and i==0 and score>=5:
				game.coach_react("praise")
				complete()
				return
			pair.age=0.
			pair.hit=false
			pair.caught=false
			pair.swing=false
			pair.flying=false
			pair.erase("pin_end")
			pair.erase("follow_heading")
			pair.erase("release_pose")
			if moving and demonstrating and not pair.has("outgoing"): pair.reset_to_five=true
			receiver.play_action("idle",.16)
			if i==0: needs_release=holding

func complete() -> void:
	finished=true
	CareerSession.checkpoint("moving_reception_complete" if moving else "pepper_complete",5)
	feedback.text="Moving reception complete   /   5 passes to setter" if moving else "Pepper complete   /   5 passes"
	game.finish_pepper()
