extends RefCounted

const Contact = preload("res://scripts/gym_physics.gd")
const CART_WALL := 512
const CART := Vector3(-3.05,0,-1.7)
const WAIT := [Vector3(0,.04,1.35),Vector3(-1.35,.04,4.9),Vector3(1.65,.04,4.9)]
const STATIONS := [CART,Vector3(0,0,-1.7),Vector3(3.05,0,-1.7)]
const FEED_SPOT := Vector3(.85,.04,-.40)
const HANDLE := Vector3(.10,.04,-.68)
var wheel_stride := 0.0
var coach_pushing := false
var coach_stride := 0.0
var tosses := 0
var station := 0
var routes := preload("res://scripts/tryout_paths.gd").new()
var game: Control
var roster: Array[Node3D] = []
var workers: Array[Dictionary] = []
var stock: Array[RigidBody3D] = []
var loose: Array[RigidBody3D] = []
var paused_balls := {}
var waiting_ball: RigidBody3D
var fetch_start := Vector3.ZERO
var fetch_time := 0.0
var issued: RigidBody3D
var turn := 0
var attempts := 0
var round_index := 0
const POSTS := [Vector3(5.4,0,2),Vector3(-5.4,0,2),Vector3(1.75,0,2.8)]
const HOME := [Vector3(5.3,.04,3),Vector3(-5.3,.04,3),Vector3(2.7,.04,-6.65),Vector3(5.4,.04,-2),Vector3(-5.4,.04,-2),Vector3(-2.7,.04,-6.65)]
var manual_wait := false
var bins: Array[Node3D] = []
var loads := [[],[],[]]
var human_cargo := []
var unloading := {}
var runner: Node3D
var exchange := -1
var returning := false
var cart_route := {}
var basket: Node3D
var net_hit := {}
var random := RandomNumberGenerator.new()

func configure(host: Control) -> void:
	game = host
	for net in game.targets:
		var center := Vector2(net.position.x,net.position.z)
		var half := Vector2(net.mouth_radius+0.40,0.91)
		routes.equipment_clearance.append(Rect2(center-half,half*2))
	random.randomize()
	roster.append(game.setter)
	for i in [1,2]: roster.append(game.athlete(WAIT[i],["","377f95","93543a"][i]))
	for i in [1,2]: game.register_student(roster[i],i)
	for i in [1,2]: preload("res://scripts/practice_kit.gd").apply(roster[i],false,i)
	for actor in roster: key_upright_idle(actor)
	for i in HOME.size():
		var actor: Node3D = game.athlete(HOME[i],"395b48")
		game.register_student(actor,i+3)
		preload("res://scripts/practice_kit.gd").apply(actor,false,i+3)
		key_upright_idle(actor)
		workers.append({"actor":actor,"cargo":[],"goal":null,"lifting":0.0,"start":Vector3.ZERO})
	runner=workers[5].actor
	basket = Node3D.new()
	game.world.add_child(basket)
	basket.position = CART
	var cloth: Material = game.gym.material("184e46")
	var metal: Material = game.gym.material("9faeae")
	for x in [-.54,.54]:
		for z in [-.34,.34]:
			cart_box(Vector3(x,.53,z),Vector3(.045,.68,.045),metal)
		cart_box(Vector3(x,.75,0),Vector3(.035,.35,.72),cloth)
	for z in [-.35,.35]: cart_box(Vector3(0,.75,z),Vector3(1.10,.35,.035),cloth)
	cart_box(Vector3(0,1.01,-.42),Vector3(.93,.044,.044),metal)
	for x in [-.43,.43]: cart_box(Vector3(x,.91,-.42),Vector3(.044,.20,.044),metal)
	cart_box(Vector3(0,.58,0),Vector3(1.10,.035,.72),cloth)
	for post in POSTS:
		var bin := basket.duplicate() as Node3D
		game.world.add_child(bin)
		bin.position=post
		bins.append(bin)
	routes.carts = bins+[basket]
	for cart in bins+[basket]:
		for x in [-.54,.54]:
			for z in [-.34,.34]:
				var caster := preload("res://scripts/cart_caster.gd").new()
				var floor_y := .04 if absf(cart.position.x+x)<4.5 else -.02
				caster.position=Vector3(x,floor_y+caster.RADIUS,z)
				cart.add_child(caster)
		var hull := BoxShape3D.new()
		hull.size=Vector3(1.12,.94,.74)
		var mount := Node3D.new()
		mount.name="CartHull"
		cart.add_child(mount)
		mount.position.y=.5
		Contact.solid(mount,hull,256)
	for i in 30: store_ball(new_ball())
	var net := Node3D.new()
	game.world.add_child(net)
	net.position = Vector3(0,1.97,4)
	var net_shape := BoxShape3D.new()
	net_shape.size = Vector3(9.6,1,.04)
	Contact.solid(net,net_shape,64)

var ball_count := 0

func new_ball() -> RigidBody3D:
	ball_count+=1
	var body := RigidBody3D.new()
	body.name = "PracticeBall%d" % ball_count
	body.freeze = true
	body.mass = .27
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 4
	body.body_entered.connect(func(other):
		if other is StaticBody3D and other.collision_layer==64:
			net_reaction(body.position,body.linear_velocity))
	body.collision_layer = 128
	body.collision_mask = Contact.GYM|Contact.EQUIPMENT|64|128|CART_WALL
	body.angular_damp = .55
	body.linear_damp = .42
	var mat := PhysicsMaterial.new()
	mat.bounce = .56
	mat.friction = .7
	body.physics_material_override = mat
	var collider := CollisionShape3D.new()
	collider.shape = game.contacts.ball_shape
	body.add_child(collider)
	var visual := MeshInstance3D.new()
	visual.mesh = game.ball.mesh
	visual.material_override = game.ball.material_override
	body.add_child(visual)
	game.world.add_child(body)
	return body

func cart_box(at: Vector3,size: Vector3,style: Material) -> void:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = at
	part.material_override = style
	basket.add_child(part)
	var shape := BoxShape3D.new()
	shape.size=size
	Contact.solid(part,shape,CART_WALL)

func store_ball(body: RigidBody3D) -> void:
	body.freeze = true
	body.collision_layer = 0
	body.show()
	var i := free_stock_slot()
	body.set_meta("cart_slot",i)
	body.position=cart_slot(basket,i)
	stock.append(body)

func free_stock_slot() -> int:
	var slots := {}
	for stored in stock: slots[stored.get_meta("cart_slot",0)]=true
	var i := 0
	while slots.has(i): i+=1
	return i

func cart_slot(cart: Node3D,slot: int) -> Vector3:
	return cart.to_global(Vector3((slot%5-2)*.211,.703+.212*(slot/15),((slot/5)%3-1)*.214))

func key_upright_idle(actor: Node3D) -> void:
	# The imported idle and walk clips omit spine_01. Key its neutral
	# rotation so procedural pickup and net-duck poses can blend out.
	for clip_name in ["base/Idle","base/Walk",actor.animation_slots.get("run","run")]:
		if not actor.animator.has_animation(clip_name): continue
		var clip: Animation=actor.animator.get_animation(clip_name)
		var bone := NodePath("Armature/Skeleton3D:spine_01")
		if clip.find_track(bone,Animation.TYPE_ROTATION_3D)>=0: continue
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track,bone)
		clip.rotation_track_insert_key(track,0.,actor.skeleton.get_bone_rest(actor.skeleton.find_bone("spine_01")).basis.get_rotation_quaternion())

func station_ready(dt: float) -> bool:
	var requested := mini(round_index,2)
	if requested!=station:
		var coach: Node3D=game.coach
		if not coach_pushing:
			if not walk(coach,basket.to_global(HANDLE),dt,2.25): return false
			coach_pushing=true
			coach_stride=0.
		var previous := basket.transform
		var before := coach.position
		var travel: Vector3=STATIONS[requested]-basket.position
		# Swing the handle around the cart first, push forward, then park
		# with the handle accessible from the coach's usual feeding spot.
		var parking := travel.length()<.01
		var heading := 0. if parking else atan2(travel.x,travel.z)
		basket.rotation.y=rotate_toward(basket.rotation.y,heading,dt*2.8)
		var aligned := absf(angle_difference(basket.rotation.y,heading))<.01
		if aligned and not parking:
			var step := travel.limit_length(dt*2.15)
			var next := move_actor(coach,step)
			basket.position+=(next-coach.position).slide(Vector3.UP)
		coach.position=basket.to_global(HANDLE)
		coach.rotation.y=basket.rotation.y
		coach_stride=push_pose(coach,basket,coach_stride,before.distance_to(coach.position))
		for body in stock: body.position=basket.transform*(previous.affine_inverse()*body.position)
		if parking and aligned:
			coach_pushing=false
			station=requested
			game.trace("cart_station",{"station":station,"tosses":tosses})
		return false
	return walk(game.coach,basket.position+FEED_SPOT,dt,4.2)

func push_pose(actor: Node3D,cart: Node3D,stride: float,distance: float) -> float:
	if absf(distance)>.00001:
		var clip: Animation=actor.animator.get_animation("base/Walk")
		stride=fposmod(stride+distance*clip.length/1.30,clip.length)
		actor.play_action("base/Walk",0.)
		actor.animator.seek(stride,true)
	else: actor.play_action("base/Idle")
	grip_handle(actor,cart)
	return stride

func grip_handle(actor: Node3D,cart: Node3D) -> void:
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var pose: Array = []
	for i in rig.get_bone_count(): pose.append(rig.get_bone_pose(i))
	for side in ["l","r"]:
		var x := .19 if side=="l" else -.19
		var hand := cart.to_global(Vector3(x,1.035,-.48))
		author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,rig.to_local(hand),Vector3(signf(x),-.8,0))
		for bone in ["upperarm_"+side,"lowerarm_"+side]:
			var idx := rig.find_bone(bone)
			rig.set_bone_pose_rotation(idx,pose[idx].basis.orthonormalized().get_rotation_quaternion())

func prepare_next_ball(dt: float) -> void:
	if coach_pushing or mini(round_index,2)!=station: return
	if game.demonstration or game.phase in ["intro","complete","feed","walk"]: return
	if game.phase=="pass" and game.elapsed<.16: return
	var coach: Node3D=game.coach
	if not waiting_ball:
		if stock.is_empty() or coach.position.distance_to(basket.position+FEED_SPOT)>.36: return
		waiting_ball=stock.back()
		for candidate in stock:
			var dz := candidate.position.y-waiting_ball.position.y
			if dz>.02 or (absf(dz)<.02 and candidate.position.distance_to(coach.position)<waiting_ball.position.distance_to(coach.position)):
				waiting_ball=candidate
		stock.erase(waiting_ball)
		fetch_start=waiting_ball.position
		fetch_time=0.
	fetch_time+=dt
	var rig: Skeleton3D=coach.skeleton
	var author: RefCounted=coach.get_pose_author()
	var to_cart := (basket.position-coach.position).slide(Vector3.UP)
	if fetch_time<.40 and to_cart.length_squared()>.01:
		coach.rotation.y=lerp_angle(coach.rotation.y,atan2(to_cart.x,to_cart.z),minf(1.,dt*12.))
	if fetch_time>.32 and mini(round_index,2)==station:
		var toward := (game.setter as Node3D).position-coach.position
		coach.rotation.y=lerp_angle(coach.rotation.y,atan2(toward.x,toward.z),minf(1.,dt*8.))
	var cradle: Vector3=rig.to_global(author.point(author.baseline,"pelvis")+Vector3(0,.12,.46))
	var carry := smoothstep(.28,.74,fetch_time)
	var pivot := coach.position
	var start_radius := (fetch_start-pivot).slide(Vector3.UP)
	var end_radius := (cradle-pivot).slide(Vector3.UP)
	var yaw := lerp_angle(atan2(start_radius.x,start_radius.z),atan2(end_radius.x,end_radius.z),carry)
	var radius := lerpf(start_radius.length(),end_radius.length(),carry)
	var center := pivot+Vector3(sin(yaw),0,cos(yaw))*radius
	center.y=lerpf(fetch_start.y,cradle.y,carry)+.15*sin(PI*carry)
	if fetch_time>=.74: center=cradle
	game.coach_motion.fetch_pose(coach,center,smoothstep(0,.28,fetch_time),carry)
	waiting_ball.position=center

func take_ball() -> bool:
	if issued: return true
	if not waiting_ball or fetch_time<.74: return false
	issued=waiting_ball
	waiting_ball=null
	issued.hide()
	game.ball.show()
	game.trace("cart_out",{"id":issued.name,"remaining":stock.size()})
	return true

func free_ball(velocity: Vector3) -> void:
	if not issued: return
	issued.position = game.ball.position
	issued.show()
	issued.collision_layer = 128
	issued.freeze = false
	issued.sleeping = false
	issued.linear_velocity = velocity.limit_length(15)
	loose.append(issued)
	game.trace("loose_ball",{"id":issued.name,"at":str(issued.position)})
	issued = null
	game.ball.hide()

func advance_turn() -> void:
	var previous := turn
	for candidate in [1,0,2]:
		var count := 0
		for entry in game.scorecard:
			if entry.setter == candidate: count += 1
		if count < 9:
			turn = candidate
			round_index = count / 3
			attempts = count % 3
			break
	if previous != turn:
		manual_wait = false
		if turn == 0:
			unloading.erase(roster[0])
			game.end_free_motion()
			for body in human_cargo:
				body.freeze = false
				body.collision_layer = 128
				loose.append(body)
			human_cargo.clear()
	game.setter = roster[turn]

var walking_progress := {}

func walk(actor: Node3D,goal: Vector3,dt: float,speed: float) -> bool:
	routes.ignored_cart[actor] = pushed_cart(actor)
	var dir := (goal-actor.position).slide(Vector3.UP)
	if dir.length()<.12:
		walking_progress.erase(actor)
		routes.velocities.erase(actor)
		actor.play_action("base/Idle")
		return true
	var track: Dictionary=walking_progress.get(actor,{})
	if track.is_empty() or goal.distance_to(track.goal)>.65 or game.clock-float(track.last)>.25:
		track={"goal":goal,"best":dir.length(),"since":game.clock,"last":game.clock}
		walking_progress[actor]=track
	track.last=game.clock
	if dir.length()<float(track.best)-.18:
		track.best=dir.length()
		track.since=game.clock
	elif game.clock-float(track.since)>=1.:
		var occupied: Array=[]
		for other in roster+workers.map(func(w): return w.actor)+[game.coach]:
			if other!=actor: occupied.append(other.position)
		for cart in bins+[basket]:
			if cart!=pushed_cart(actor): occupied.append(cart.position)
		routes.detour(actor,goal,occupied)
		track.wait_until = game.clock + 0.25
		routes.velocities.erase(actor)
		track.since=game.clock
		track.best=dir.length()
	var waypoint := routes.waypoint(actor,goal,dt)
	if game.clock<float(track.get("wait_until",0.)):
		actor.play_action("base/Idle",0.24)
		return false
	dir = (waypoint-actor.position).slide(Vector3.UP)
	var step := routes.stride(actor,dir,minf(speed,sqrt(8.0*actor.position.distance_to(goal))),dt)
	var next := move_actor(actor,step)
	if game.phase in ["feed","pass"] and actor!=game.setter and actor!=game.coach and not in_feed_lane(actor.position) and in_feed_lane(next):
		actor.play_action("base/Idle")
		return false
	var along := (next-actor.position).dot(dir.normalized())
	if along<step.length()*.65: routes.reroute(actor,goal)
	# If collision steering would send the player sideways, yield and
	# commit to the reroute instead of sliding left and right each frame.
	if step.length_squared()>0.000001 and (next-actor.position).normalized().dot(step.normalized())<0.65:
		routes.reroute(actor,goal)
		routes.velocities.erase(actor)
		track.wait_until = game.clock + 0.22
		actor.play_action("base/Idle",0.24)
		return false
	next.y=actor.position.y
	actor.position=next
	actor.play_action(("base/Walk" if speed<2.4 else "run") if along>step.length()*.18 else "base/Idle")
	return false

func tick(dt: float) -> void:
	for i in 3:
		if i==turn: continue
		if i==0:
			shag_player(dt)
			continue
		var waiting := roster[i]
		waiting.animator.advance(dt)
		walk(waiting,WAIT[(i-turn+3)%3],dt,5.2)
	for i in range(loose.size()-1,-1,-1):
		var body := loose[i]
		if not body.freeze and body.linear_velocity.length()<.65:
			var caught := false
			for cart in bins+[basket]:
				var local: Vector3=cart.to_local(body.position)
				if absf(local.x)>.44 or absf(local.z)>.25 or local.y<.63 or local.y>.96: continue
				for worker in workers:
					if worker.goal==body: worker.goal=null
				loose.remove_at(i)
				body.freeze=true
				body.collision_layer=0
				if cart==basket: store_ball(body)
				else: deposit(bins.find(cart),body)
				caught=true
				break
			if caught: continue
		if not body.freeze and under_stands(body.position):
			for w in workers:
				if w.goal==body:
					w.goal=null
					w.erase("destination")
			loose.remove_at(i)
			game.trace("ball_left_under_stands",{"id":body.name})
			# Keep a working supply during long sessions. Stage replacement balls
			# at a sideline cart; the crew still has to bring them to the coach.
			var available := stock.size()+loose.size()+human_cargo.size()+int(waiting_ball!=null)+int(issued!=null)
			for load in loads: available+=load.size()
			for w in workers: available+=w.cargo.size()
			if available<10:
				var index := closest_bin(body.position)
				var spare := new_ball()
				spare.collision_layer=0
				deposit(index,spare)
				game.trace("sideline_spare",{"id":spare.name,"bin":index})
	for body in loose:
		if body.freeze or body.sleeping or body.position.y<.14: continue
		var v := body.linear_velocity
		# A 21 cm ball in indoor air: quadratic drag and a bounded spin lift.
		var drag := -.006*v.length()*v
		var magnus := .0018*body.angular_velocity.cross(v)
		body.apply_central_force(drag+magnus.limit_length(.35))
	for worker in workers:
		if exchange<0 or worker.actor!=runner: collect(worker,dt)
	service_carts(dt)
	if not net_hit.is_empty():
		game.gym.get_node("DynamicNet").sample(net_hit,game.clock)
		if game.clock-net_hit.time>1.5: net_hit.clear()

func under_stands(point: Vector3) -> bool:
	for bench in game.gym.benches:
		var at: Vector3=bench.to_local(point)
		if absf(at.x)<=bench.mesh.size.x*.5+.15 and absf(at.z)<=bench.mesh.size.z*.5+.15: return true
	return false

func on_drill_floor(p: Vector3) -> bool:
	return absf(p.x)<4.78 and p.z> -5.28 and p.z<4.25

func in_feed_lane(at: Vector3) -> bool:
	var start: Vector3=game.coach.position.slide(Vector3.UP)
	var end: Vector3=game.catch_point.slide(Vector3.UP)
	if (at.slide(Vector3.UP)-start).dot(end-start)<=0: return false
	var nearest := Geometry3D.get_closest_point_to_segment(at.slide(Vector3.UP),start,end)
	return at.slide(Vector3.UP).distance_to(nearest)<.70

func floor_clear() -> bool:
	for w in workers:
		if in_feed_lane(w.actor.position): return false
	return true

func nearest(at: Vector3,worker: Dictionary,limit: float) -> RigidBody3D:
	var best: RigidBody3D
	for body in loose:
		if under_stands(body.position) or float(worker.get("skip",{}).get(body,0))>game.clock: continue
		if body.position.y>1.55 or body.linear_velocity.length()>4: continue
		var occupied := false
		for other in workers:
			if other.actor!=worker.actor and other.goal==body: occupied=true
		if occupied: continue
		var worker_index := workers.find(worker)
		if game.phase!="complete" and worker_index>=0 and worker_index<3 and body.position.distance_to(POSTS[worker_index])>2.8: continue
		var d := body.position.distance_to(at)
		if d<limit:
			limit=d
			best=body
	return best

func collect(w: Dictionary,dt: float) -> void:
	var actor: Node3D=w.actor
	actor.animator.advance(dt)
	var cargo: Array=w.cargo
	if unloading.has(actor):
		place_in_cart(actor,cargo,dt)
		return
	if game.phase in ["cart","feed"] and in_feed_lane(actor.position) and (not stock.is_empty() or waiting_ball or issued) and not w.lifting:
		var line: Vector3=(game.catch_point-game.coach.position).slide(Vector3.UP).normalized()
		var away := line.cross(Vector3.UP)
		if (actor.position-game.coach.position).dot(away)<0: away=-away
		if away.is_zero_approx(): away=Vector3.RIGHT
		walk(actor,actor.position+away*1.1,dt,4.5)
		for i in cargo.size(): cargo[i].position=Contact.palm(actor,"l" if i==0 else "r")
		return
	if stock.is_empty() and not waiting_ball and game.phase=="cart" and not human_cargo.is_empty() and not unloading.has(roster[0]) and w==workers[3] and cargo.is_empty() and not w.lifting:
		if actor.position.distance_to(roster[0].position)<1.0:
			w.goal=null
			cargo.append(human_cargo.pop_back())
			game.trace("setter_cart_handoff",{"id":cargo.back().name})
		elif not w.goal:
			var approach: Vector3=(actor.position-roster[0].position).slide(Vector3.UP).normalized()
			perimeter_walk(w,roster[0].position+approach*.64,dt)
			return
	if w.goal and not w.goal.freeze:
		var stuck: float=w.get("stuck",0.)
		if actor.position.distance_to(w.get("mark",actor.position))>.22:
			w.mark=actor.position
			stuck=0.
		else: stuck+=dt
		w.stuck=stuck
		if under_stands(w.goal.position) or stuck>=3.0:
			if not w.has("skip"): w.skip={}
			w.skip[w.goal]=game.clock+6.0
			w.goal=null
			w.stuck=0.
			w.erase("destination")
	if not w.goal and cargo.size()<2 and (cargo.is_empty() or not stock.is_empty()):
		w.mark=actor.position
		w.stuck=0.
		w.goal=nearest(actor.position,w,2.7 if not cargo.is_empty() else INF)
	if w.goal:
		var body: RigidBody3D=w.goal
		var delta := (body.position-actor.position).slide(Vector3.UP)
		if w.lifting<=0 and delta.length()>.95:
			var lead := body.linear_velocity.slide(Vector3.UP)*clampf(delta.length()/5.7,0.,.42)
			var pickup := body.position+lead.limit_length(.85)
			if under_stands(pickup): pickup=body.position
			perimeter_walk(w,pickup-delta.normalized()*.48,dt)
		else:
			actor.rotation.y=rotate_toward(actor.rotation.y,atan2(delta.x,delta.z),2.25*dt)
			actor.play_action("idle")
			var side := "l" if cargo.is_empty() else "r"
			var bend := sin(PI*clampf(float(w.lifting)/.42,0,1))
			var pose: Array = actor.get_pose_author().baseline.duplicate()
			var rig: Skeleton3D = actor.skeleton
			var author: RefCounted = actor.get_pose_author()
			var hips := rig.find_bone("pelvis")
			var feet := [author.point(pose,"foot_l"),author.point(pose,"foot_r")]
			var hip_parent: Transform3D = author.world_pose(pose,rig.get_bone_parent(hips))
			pose[hips].origin += hip_parent.basis.inverse()*Vector3(0,-.40*bend,-.04*bend)
			author.rotate_world(pose,"spine_01",Vector3.RIGHT,.58*bend)
			for i in 2:
				var leg: String = ["l","r"][i]
				author.limb(pose,"thigh_"+leg,"calf_"+leg,"foot_"+leg,feet[i],Vector3.BACK)
			author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,rig.to_local(body.position),Vector3(0,-1,-.2),bend)
			rig.set_bone_pose_position(hips,pose[hips].origin)
			for i in rig.get_bone_count(): rig.set_bone_pose_rotation(i,pose[i].basis.orthonormalized().get_rotation_quaternion())
			var hand := Contact.palm(actor,side)
			if w.lifting<=0:
				w.start=body.position
				body.freeze=true
				body.collision_layer=0
			w.lifting+=dt
			body.position=w.start.lerp(hand,smoothstep(.12,.39,w.lifting))
			if w.lifting>=.42:
				loose.erase(body)
				cargo.append(body)
				game.trace("shag_pickup",{"id":body.name,"carrying":cargo.size()})
				w.goal=null
				w.lifting=0.
	elif not cargo.is_empty():
		if stock.is_empty() and not waiting_ball and not coach_pushing and actor.position.distance_to(basket.position)<1.12:
			begin_unload(actor,-1,cargo)
			place_in_cart(actor,cargo,dt)
			return
		if stock.is_empty() and not waiting_ball and not coach_pushing and exchange<0 and workers.find(w)>=3:
			var drop := basket.position+Vector3(0,.04,-.82)
			perimeter_walk(w,drop,dt)
			for i in cargo.size(): cargo[i].position=Contact.palm(actor,"l" if i==0 else "r")
			return
		var index := workers.find(w)%3
		if index==exchange: index=closest_bin(actor.position)
		if index>=0 and (actor.position.distance_to(bins[index].position)<1.05 or perimeter_walk(w,bins[index].position+Vector3(.1,.04,-.65),dt)):
			begin_unload(actor,index,cargo)
			place_in_cart(actor,cargo,dt)
			return
	else:
		var home: Vector3=HOME[workers.find(w)]
		if actor.position.distance_to(home)<.95:
			actor.play_action("base/Idle")
			w.erase("destination")
		else: perimeter_walk(w,home,dt)
	for i in cargo.size():
		cargo[i].position=Contact.palm(actor,"l" if i==0 else "r")+Vector3.UP*.055

func net_reaction(point: Vector3,speed: Vector3) -> void:
	net_hit={"kind":"net","time":game.clock,"point":point,"side":-signf(speed.z),"stretch":minf(.38,speed.length()*.026),"release_time":game.clock+.15,"contact_duration":.15}

func pause_balls(paused: bool) -> void:
	if paused:
		for body in loose:
			if not body.freeze:
				paused_balls[body]=[body.linear_velocity,body.angular_velocity]
				body.freeze=true
	else:
		for body in paused_balls:
			body.freeze=false
			body.linear_velocity=paused_balls[body][0]
			body.angular_velocity=paused_balls[body][1]
		paused_balls.clear()

func closest_bin(at: Vector3) -> int:
	var best := -1
	for i in bins.size():
		if i!=exchange and (best<0 or at.distance_squared_to(bins[i].position)<at.distance_squared_to(bins[best].position)): best=i
	return best

func begin_unload(actor: Node3D,index: int,cargo: Array) -> void:
	var side := "r" if cargo.size()==2 else "l"
	unloading[actor]={"bin":index,"side":side,"age":0.0,"release":Vector3.ZERO,"start":Contact.palm(actor,side)}
	game.trace("cart_place_begin",{"id":cargo.back().name,"bin":index})

func place_in_cart(actor: Node3D,cargo: Array,dt: float) -> void:
	if cargo.is_empty():
		unloading.erase(actor)
		return
	var state: Dictionary=unloading[actor]
	var index: int=state.bin
	var cart := basket if index<0 else bins[index]
	var body: RigidBody3D=cargo.back()
	var side: String=state.side
	var offset := (cart.position-actor.position).slide(Vector3.UP)
	actor.rotation.y=lerp_angle(actor.rotation.y,atan2(offset.x,offset.z),minf(1.,dt*12.))
	actor.play_action("base/Idle")
	state.age+=dt
	var age: float=state.age
	var approach := smoothstep(0,.36,age)
	var recover := 1.-smoothstep(.40,.7,age)
	var lip := cart.position-offset.normalized()*.21+Vector3.UP*maxf(1.19,slot_position(index).y+.20)
	var rig: Skeleton3D=actor.skeleton
	var author: RefCounted=actor.get_pose_author()
	var pose: Array=author.baseline.duplicate()
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,.22*approach*recover)
	var target: Vector3=state.start.lerp(lip,approach)+Vector3.UP*.18*sin(PI*approach)
	author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,rig.to_local(target),Vector3(.3 if side=="l" else -.3,-1,0),recover)
	for bone in ["spine_01","upperarm_"+side,"lowerarm_"+side,"hand_"+side]:
		var i := rig.find_bone(bone)
		rig.set_bone_pose_rotation(i,pose[i].basis.orthonormalized().get_rotation_quaternion())
	if cargo.size()==2: cargo[0].position=Contact.palm(actor,"l")+Vector3.UP*.055
	if age<.36:
		body.position=Contact.palm(actor,side)+Vector3.UP*.065
		state.release=body.position
	else:
		if state.release==Vector3.ZERO: state.release=target
		var t := clampf((age-.36)/.34,0.,1.)
		body.position=Vector3(state.release).lerp(slot_position(index),t)+Vector3.UP*.56*t*(1.-t)
	if age>=.70:
		if index<0: store_ball(body)
		else: deposit(index,body)
		cargo.pop_back()
		if actor==roster[0] and CareerSession.credit_team_return():
			game.trace("team_chemistry",{"value":CareerSession.team_chemistry()})
		unloading.erase(actor)
		game.trace("cart_return",{"id":body.name,"bin":index})
		if not cargo.is_empty(): begin_unload(actor,index,cargo)

func slot_position(index: int) -> Vector3:
	if index<0: return cart_slot(basket,free_stock_slot())
	return cart_slot(bins[index],loads[index].size())

func deposit(index: int,body: RigidBody3D) -> void:
	body.position=slot_position(index)
	loads[index].append(body)

func shag_player(dt: float) -> void:
	var actor := roster[0]
	actor.animator.advance(dt)
	if unloading.has(actor):
		place_in_cart(actor,human_cargo,dt)
		return
	var moving: bool=game.move_setter(dt,actor,true)
	var acting: bool=game.free_motion(dt,actor)
	if moving or acting: manual_wait=true
	var blocking_station: bool= game.phase=="cart" and (actor.position-game.BASE).slide(Vector3.UP).length()<1.05
	if not moving and not game.free_jump.active and (blocking_station or (not acting and not manual_wait)):
		walk(actor,WAIT[(3-turn)%3],dt,4.8)
	var index := closest_bin(actor.position)
	if index>=0 and not human_cargo.is_empty() and not game.free_jump.active and game.free_target<0 and actor.position.distance_to(bins[index].position)<1.05:
		begin_unload(actor,index,human_cargo)
		place_in_cart(actor,human_cargo,dt)
		return
	if human_cargo.size()<2 and not game.free_jump.active and game.free_target<0:
		for body in loose:
			if body.freeze or body.position.distance_to(actor.position)>.95 or body.linear_velocity.length()>4: continue
			for w in workers:
				if w.goal==body: w.goal=null
			body.freeze=true
			body.collision_layer=0
			loose.erase(body)
			human_cargo.append(body)
			game.trace("player_shag",{"id":body.name})
			break
	for i in human_cargo.size(): human_cargo[i].position=Contact.palm(actor,"l" if i==0 else "r")

func service_carts(dt: float) -> void:
	if exchange<0:
		if not stock.is_empty() or waiting_ball: return
		for i in bins.size():
			var partner := workers[i+3]
			if not partner.cargo.is_empty() or partner.lifting>0 or unloading.has(partner.actor): continue
			if unloading.values().any(func(place): return place.bin in [i,-1]): continue
			if not loads[i].is_empty() and (exchange<0 or loads[i].size()>loads[exchange].size()): exchange=i
		if exchange<0: return
		var partner := workers[exchange+3]
		runner=partner.actor
		partner.goal=null
		partner.erase("destination")
		cart_route={"actor":runner}
		game.trace("empty_cart_exchange",{"station":station,"source":exchange,"balls":loads[exchange].size()})
	runner.animator.advance(dt)
	var cart := bins[exchange]
	var handle := Vector3(0,.04,-.75)
	if not cart_route.get("pushing",false):
		var grip := cart.to_global(handle)
		for other in roster+workers.map(func(w): return w.actor):
			if other!=runner and grip.distance_to(other.position)<.55:
				var local: Vector3=cart.to_local(other.position)
				grip+=cart.basis.x*(.51 if local.x<=0 else -.51)
				break
		if runner.position.distance_to(grip)<.32 or perimeter_walk(cart_route,grip,dt):
			cart_route.pushing=true
			wheel_stride=0.0
		return
	var goal: Vector3=POSTS[exchange] if returning else STATIONS[station]+Vector3(1.45 if basket.position.x<STATIONS[station].x+.72 else 0.0,0,0)
	var before := runner.position
	var hand_offset := handle
	var arrived := perimeter_walk(cart_route,goal+hand_offset,dt)
	var step := runner.position-before
	var previous := cart.transform
	if step.length_squared()>.000001:
		var heading := atan2(step.x,step.z)
		# Pull back for a short reversal, turn the trolley for longer changes of direction.
		var backwards := absf(angle_difference(cart.rotation.y,heading))>2.5 and cart.position.distance_to(goal)<1.25
		if cart.position.distance_to(goal)<1.1: cart.rotation.y=lerp_angle(cart.rotation.y,0.,minf(1.,dt*7.))
		elif not backwards: cart.rotation.y=lerp_angle(cart.rotation.y,heading,minf(1.,dt*5.))
		runner.rotation.y=cart.rotation.y
		cart.position=runner.position-cart.basis*handle
		cart.position.y=0
		wheel_stride=push_pose(runner,cart,wheel_stride,step.length()*(-1 if backwards else 1))
	else: wheel_stride=push_pose(runner,cart,wheel_stride,0.)
	for body in loads[exchange]: body.position=cart.transform*(previous.affine_inverse()*body.position)
	if not arrived: return
	if returning:
		exchange=-1
		returning=false
	else:
		var depleted := basket
		basket=cart
		basket.rotation.y=0
		bins[exchange]=depleted
		for body in stock: body.position+=basket.position-depleted.position
		for body in loads[exchange]: store_ball(body)
		loads[exchange].clear()
		cart_route={"actor":runner}
		returning=true

func gate(point: Vector3) -> Vector3:
	if absf(point.x)>3.3: return Vector3(signf(point.x)*5.85,.04,clampf(point.z,-5.65,13.65))
	return Vector3(point.x,.04,-5.65 if point.z<4 else 13.65)

# Clockwise distance along the four exterior lanes, starting at the near left corner.
func lane_coordinate(p: Vector3) -> float:
	if p.z<=-5.64: return clampf(p.x+5.85,0,11.7)
	if p.z>=13.64: return 31.0+clampf(5.85-p.x,0,11.7)
	if p.x>0: return 11.7+clampf(p.z+5.65,0,19.3)
	return 42.7+clampf(13.65-p.z,0,19.3)

func perimeter_walk(w: Dictionary,target: Vector3,dt: float) -> bool:
	var actor: Node3D=w.actor
	if not w.has("destination") or (target.distance_to(w.destination)>1.6 and game.clock >= float(w.get("route_after",0.0))):
		w.route_after = game.clock + 1.2
		w.destination=target
		var exit_point := gate(actor.position)
		var entry := gate(target)
		var start := lane_coordinate(exit_point)
		var end := lane_coordinate(entry)
		var clockwise := fposmod(end-start,62.0)
		var forward := clockwise<=31.0
		var corners := [Vector3(-5.85,.04,-5.65),Vector3(5.85,.04,-5.65),Vector3(5.85,.04,13.65),Vector3(-5.85,.04,13.65)]
		var stops := {}
		for corner: Vector3 in corners:
			var offset := fposmod((lane_coordinate(corner)-start)*(1 if forward else -1),62.0)
			if offset>.1 and offset<minf(clockwise,62.0-clockwise): stops[offset]=corner
		var keys := stops.keys()
		keys.sort()
		w.path=[exit_point]
		for key in keys: w.path.append(stops[key])
		w.path.append(entry)
	if game.phase in ["feed","pass"] and in_feed_lane(target) and w.path.is_empty():
		actor.play_action("base/Idle")
		return false
	if not w.path.is_empty():
		if actor.position.distance_to(w.path[0])<.58 or walk(actor,w.path[0],dt,2.15 if actor==runner and cart_route.get("pushing",false) else 5.7): w.path.pop_front()
		return false
	return walk(actor,target,dt,2.15 if actor==runner and cart_route.get("pushing",false) else 5.7)

func pushed_cart(actor: Node3D) -> Node3D:
	if actor==game.coach and coach_pushing: return basket
	if actor==runner and exchange>=0 and cart_route.get("pushing",false): return bins[exchange]
	return null

func move_actor(actor: Node3D,step: Vector3) -> Vector3:
	var here := actor.position
	var depth := 0.0
	if absf(here.x)<4.85:
		var approach := absf(step.z)>absf(step.x)*.5 and (4.-here.z)*step.z>0.
		depth=1.-smoothstep(.18,.78 if approach else .32,absf(here.z-4.0))
		if absf(step.x)>absf(step.z)*2. and absf(here.z-4.)<.38:
			step.z+=absf(step.x)*(.55 if here.z>=4. else -.55)
	if depth>0:
		var rig: Skeleton3D=actor.skeleton
		var author: RefCounted=actor.get_pose_author()
		var pose: Array=author.baseline.duplicate()
		var hips := rig.find_bone("pelvis")
		var parent: Transform3D=author.world_pose(pose,rig.get_bone_parent(hips))
		pose[hips].origin+=parent.basis.inverse()*Vector3.DOWN*.55*depth
		author.rotate_world(pose,"spine_01",Vector3.RIGHT,.65*depth)
		for side in ["l","r"]:
			author.limb(pose,"thigh_"+side,"calf_"+side,"foot_"+side,author.point(author.baseline,"foot_"+side),Vector3.BACK)
		rig.set_bone_pose_position(hips,pose[hips].origin)
		for i in rig.get_bone_count(): rig.set_bone_pose_rotation(i,pose[i].basis.orthonormalized().get_rotation_quaternion())
	# Steer before shoulder contact. Both walkers keep to their own right
	# during a head-on pass, including when the other walker holds position.
	var steer := Vector3.ZERO
	var ahead := step.normalized()
	for other in roster+workers.map(func(w): return w.actor)+[game.coach]:
		if other==actor or not other: continue
		if actor==runner and other==game.coach and returning: continue
		var offset := ((other as Node3D).position-here).slide(Vector3.UP)
		var along := offset.dot(ahead)
		if along<=0 or along>1.35: continue
		var across := offset-ahead*along
		if across.length()>.72: continue
		var away := -across.normalized() if across.length()>.12 else ahead.cross(Vector3.UP)
		steer+=away*(1.-across.length()/.72)*(1.-along/1.5)
	if not steer.is_zero_approx(): step=(ahead+steer*2.4).normalized()*step.length()
	var excluded: Array[RID]=[]
	var pushed := pushed_cart(actor)
	if pushed: excluded.append(pushed.get_node("CartHull").get_child(0).get_rid())
	var next: Vector3=game.contacts.travel(game.world,here,step*(1.-.45*depth),actor.height_cm*.01*(1.-.39*depth),excluded)
	for other in roster+workers.map(func(w): return w.actor)+[game.coach]:
		if other==actor or not other: continue
		if actor==runner and other==game.coach and returning: continue
		var gap := (next-(other as Node3D).position).slide(Vector3.UP)
		if gap.length()<.53 and gap.length()>0 and gap.dot(step)<0:
			var tangent := Vector3(-gap.z,0,gap.x).normalized()
			if tangent.dot(step)<0: tangent=-tangent
			return game.contacts.travel(game.world,here,tangent*step.length(),actor.height_cm*.01*(1.-.39*depth),excluded)
	return next

const HUDDLE_CENTER := Vector3(0,.04,.35)
var circle: Array = []
var debrief_started := false
var settle_time := 0.
var huddle_planted := false
var speech_joints := {}
var coach_dip := {}
var pointing_poses: Array[Dictionary]=[]
var look_angles: Array[float]=[]
var shoulder_trim := {}
var elbow_adjustments := {}
var huddle_elapsed := 0.0
var huddle_slots := {}
var huddle_marks := {}
var approach_reached := {}
var settled_positions := {}
var huddle_velocity := {}

func huddle_walk(actor: Node3D, goal: Vector3, dt: float) -> void:
	routes.ignored_cart.erase(actor)
	var dir := (goal - actor.position).slide(Vector3.UP)
	if dir.length() < 0.05: return
	var occupied := []
	var blocked := false
	for other in circle:
		if other == actor: continue
		var offset: Vector3 = other.position - actor.position
		occupied.append(other.position)
		var ahead := offset.dot(dir.normalized())
		if ahead > 0 and ahead < minf(1.6,dir.length()) and (offset - dir.normalized()*ahead).length() < 0.8: blocked = true
	for cart in bins + [basket]: occupied.append(cart.position)
	var waypoint := goal
	var capsule: CapsuleShape3D = game.contacts.capsule
	capsule.height = maxf(0.68,actor.height_cm*0.01)
	var origin := actor.position + Vector3.UP*(capsule.height*0.5+0.025)
	var obstacle: Dictionary = game.contacts.sweep(game.world,capsule,origin,dir.limit_length(2.0),Contact.GYM|Contact.EQUIPMENT|CART_WALL)
	if routes.paths.has(actor) or blocked or not obstacle.is_empty():
		if not routes.paths.has(actor): routes.detour(actor,goal,occupied)
		waypoint = routes.waypoint(actor,goal,dt)
	else: routes.paths.erase(actor)
	var toward := (waypoint - actor.position).slide(Vector3.UP)
	var speed := minf(2.35,dir.length()*2.8)
	var step := routes.stride(actor,toward,speed,dt)
	var start := actor.position
	var next := move_actor(actor,step)
	if (next-start).dot(step)>0 and (next-start).normalized().dot(step.normalized())>0.55:
		actor.position = next
	huddle_velocity[actor] = (actor.position-start)/maxf(dt,0.001)
	actor.play_action("base/Walk" if huddle_velocity[actor].length()>0.15 else "base/Idle")


func huddle(dt: float) -> void:
	if huddle_planted:
		settle_time+=dt
		coach_address(settle_time-.75)
		return
	huddle_elapsed += dt
	if circle.is_empty():
		circle=roster+workers.map(func(w): return w.actor)+[game.coach]
		circle.sort_custom(func(a,b): return huddle_angle(a)<huddle_angle(b))
		# Preserve neighboring order, choosing the offset with the least travel.
		var ordered := circle.duplicate()
		var best := INF
		for offset in circle.size():
			var cost := 0.0
			for j in circle.size():
				cost += absf(angle_difference(huddle_angle(ordered[(j+offset)%circle.size()]),TAU*j/circle.size()-PI))
			if cost < best:
				best = cost
				for j in circle.size(): circle[j] = ordered[(j+offset)%circle.size()]
		for j in circle.size():
			huddle_slots[circle[j]] = TAU*j/circle.size()-PI
	# Open a gap where the arriving player actually is. Let their neighbors
	# move to the new slots before attempting shoulder contact again.
	for actor: Node3D in circle:
		if settled_positions.has(actor): continue
		var mark: Dictionary = huddle_marks.get(actor,{"at":actor.position,"time":huddle_elapsed})
		if actor.position.distance_to(mark.at)>0.32:
			mark = {"at":actor.position,"time":huddle_elapsed}
		huddle_marks[actor] = mark
		if huddle_elapsed-mark.time < 2.5 or actor.position.distance_to(HUDDLE_CENTER)>3.2: continue
		circle.sort_custom(func(a,b): return huddle_angle(a)<huddle_angle(b))
		var base := huddle_angle(actor)-TAU*circle.find(actor)/circle.size()
		for j in circle.size():
			var member: Node3D = circle[j]
			huddle_slots[member] = base+TAU*j/circle.size()
			approach_reached[member] = true
			huddle_marks[member] = {"at":member.position,"time":huddle_elapsed+1.5}
			routes.paths.erase(member)
		settled_positions.clear()
		break
	# Read the previous displayed pose before the idle clips are advanced.
	for actor: Node3D in shoulder_trim:
		var entry: Dictionary=shoulder_trim[actor]
		var palm := Contact.palm(actor,entry.side)
		var surface: Vector3=game.coach.dressed_surface.contact(palm,Vector3.UP)
		if not surface.is_equal_approx(palm):
			entry.trim=clampf(entry.trim+(surface.y-.012-palm.y)*minf(1.,dt*5.),-.06,.06)
	var present := 0
	var facing_center := true
	for i in circle.size():
		var actor: Node3D=circle[i]
		var work := workers.find_custom(func(w): return w.actor==actor)
		if work>=0:
			var w := workers[work]
			if not w.cargo.is_empty() or w.lifting > 0 or (huddle_elapsed < 8.0 and (w.goal or nearest(actor.position,w,INF))):
				collect(w,dt)
				continue
		if actor==roster[0] and not human_cargo.is_empty():
			actor.animator.advance(dt)
			var bin := closest_bin(actor.position)
			if bin>=0 and (unloading.has(actor) or walk(actor,bins[bin].position+Vector3(0,.04,-.82),dt,3.2)):
				if not unloading.has(actor): begin_unload(actor,bin,human_cargo)
				place_in_cart(actor,human_cargo,dt)
			continue
		actor.animator.advance(dt)
		var angle: float = huddle_slots[actor]
		var radial := Vector3(sin(angle),0,cos(angle))
		var spot := HUDDLE_CENTER + radial*1.28
		var outer := HUDDLE_CENTER + radial*1.95
		if not approach_reached.has(actor):
			if actor.position.distance_to(outer) > 0.35 and actor.position.distance_to(spot) > 0.55:
				huddle_walk(actor,outer,dt)
				continue
			approach_reached[actor] = true
			routes.paths.erase(actor)
		if not settled_positions.has(actor):
			if actor.position.distance_to(spot) > 0.30:
				huddle_walk(actor,spot,dt)
				continue
			settled_positions[actor] = actor.position
		present += 1
		actor.play_action("base/Idle")
		var inward := HUDDLE_CENTER-actor.position
		actor.rotation.y=rotate_toward(actor.rotation.y,atan2(inward.x,inward.z),dt*2.)
		if absf(angle_difference(actor.rotation.y,atan2(inward.x,inward.z)))>.015: facing_center=false
		var author: RefCounted=actor.get_pose_author()
		var rig: Skeleton3D=actor.skeleton
		var pose: Array=[]
		for j in rig.get_bone_count(): pose.append(rig.get_bone_pose(j))
		var mid_z: float=(author.point(pose,"foot_l").z+author.point(pose,"foot_r").z)*.5
		var lead: float=[0.,.095,-.095][i%3]
		# Idle feet can settle below the floor. Correct the ankle through
		# the leg chain so the shoe and the sock stay joined.
		for leg in ["l","r"]:
			if not rig.has_meta("sole_"+leg): continue
			var mount: Node3D=rig.get_meta("sole_"+leg)
			var ankle := "foot_"+str(leg)
			var id := rig.find_bone(ankle)
			var ankle_pose: Transform3D=author.world_pose(pose,id)
			var shoe_frame: Transform3D=rig.global_transform*ankle_pose*mount.transform
			var lowest := INF
			for z: float in [-.13,.0,.15]:
				for x: float in [-.045,.045]:
					lowest=minf(lowest,(shoe_frame*Vector3(x,.009,z)).y)
			var shift := rig.global_basis.inverse()*(Vector3.UP*(.041-lowest))
			shift.z+=mid_z+(lead if leg=="l" else -lead)-ankle_pose.origin.z
			author.limb(pose,"thigh_"+leg,"calf_"+leg,ankle,ankle_pose.origin+shift,Vector3.BACK)
			author.set_world_basis(pose,ankle,ankle_pose.basis.orthonormalized())
			for bone in ["thigh_"+leg,"calf_"+leg,ankle]:
				var joint := rig.find_bone(bone)
				rig.set_bone_pose_rotation(joint,pose[joint].basis.orthonormalized().get_rotation_quaternion())
		for side in ["l","r"]:
			var sign_: float=1. if side=="l" else -1.
			var arm := "upperarm_"+str(side)
			var adjacent: Node3D=circle[posmod(i+(1 if side=="r" else -1),circle.size())]
			if not settled_positions.has(adjacent) or not settled_positions.has(actor): continue
			var distance := actor.position.distance_to(adjacent.position)
			var weight := 1.-smoothstep(.77,1.02,distance)
			var upper := i%2==0
			var back := -adjacent.global_basis.z.normalized()
			var lateral := adjacent.global_basis.x.normalized()
			if lateral.dot(actor.position-adjacent.position)<0.: lateral=-lateral
			var shoulder := Contact.joint(adjacent,"spine_03")
			var pelvis := Contact.joint(adjacent,"pelvis")
			# Approach from outside the circle. The palm rests on the rear
			# shoulder blade or the rear waistband, clear of the spine.
			var size: float=adjacent.height_cm/180.
			var aim := pelvis.lerp(shoulder,.28)+(back*.18+lateral*.085)*size
			if upper:
				var left := Contact.joint(adjacent,"upperarm_l")
				var right := Contact.joint(adjacent,"upperarm_r")
				var near_shoulder := left if left.distance_squared_to(actor.position)<right.distance_squared_to(actor.position) else right
				aim=near_shoulder+(Vector3.UP*.10+back*.020+lateral*.035)*size
			var shoulder_normal := Vector3.UP
			if actor!=game.coach:
				aim=adjacent.dressed_surface.contact(aim,Vector3.UP if upper else back)
				if upper: shoulder_normal=Vector3.UP.slerp(adjacent.dressed_surface.hit_normal,.68)
			if actor != game.coach:
				var reach := Contact.joint(actor,arm)
				var elbow_at := Contact.joint(actor,"lowerarm_"+str(side))
				var hand_at := Contact.joint(actor,"hand_"+str(side))
				var length := reach.distance_to(elbow_at) + elbow_at.distance_to(hand_at)
				if reach.distance_to(aim) > length*0.9 or aim.y > reach.y + 0.12: continue
			var pole := Vector3(sign_*.75,.18 if upper else -.65,-.85)

			if actor==game.coach:
				weight=.85
				aim=actor.to_global(Vector3(sign_*.32,1.15,.37))
				pole=Vector3(sign_*.7,-.65,-.15)
			var wrist := "hand_"+str(side)
			var orientation := Basis.IDENTITY
			var blend := weight if actor!=game.coach else 0.
			if blend>0.:
				var frame := rig.global_basis.orthonormalized().inverse()
				var direction := (-lateral*.35-back*.94).normalized() if upper else -lateral
				if upper:
					var elbow_world := rig.to_global(author.point(pose,"lowerarm_"+str(side)))
					var approach := (aim-elbow_world).slide(shoulder_normal)
					direction=direction.slide(shoulder_normal).normalized()
					if approach.length_squared()>.001 && approach.dot(direction)>0.:
						direction=direction.slerp(approach.normalized(),.55)
				var along := (frame*direction).normalized()
				var normal := (frame*(-shoulder_normal if upper else -back)).slide(along).normalized()
				var across := normal.cross(along)*sign_
				var base: Transform3D=author.world_pose(pose,rig.find_bone(wrist))
				var fingers: Vector3=author.point(pose,"middle_01_"+str(side))-base.origin
				var span: Vector3=author.point(pose,"index_01_"+str(side))-author.point(pose,"pinky_01_"+str(side))
				var hands=preload("res://scripts/hand_setting_pose.gd")
				orientation=hands.hand_basis(along,across)*hands.hand_basis(fingers,span).inverse()*base.basis.orthonormalized()
				author.set_world_basis(pose,wrist,orientation)
				for digit in ["thumb","index","middle","ring","pinky"]:
					for joint in ["01","02","03"]:
						var id := rig.find_bone("%s_%s_%s"%[digit,joint,side])
						if id>=0:
							rig.set_bone_pose_rotation(id,rig.get_bone_pose_rotation(id).slerp(rig.get_bone_rest(id).basis.orthonormalized().get_rotation_quaternion(),blend))
			var palm_offset: Vector3=(author.point(pose,"middle_01_"+str(side))-author.point(pose,wrist))*.8
			if blend>.01:
				var outward := Vector3.UP if upper else back
				var clearance := 0.
				# The thumb protrudes past the palm. Check it and the outer
				# knuckles against the same surface before solving the arm.
				for digit in ["thumb_03_","pinky_02_","index_02_"]:
					var relative: Vector3=author.point(pose,digit+str(side))-author.point(pose,wrist)-palm_offset
					var finger := aim+rig.global_basis*relative
					var surface: Vector3=adjacent.dressed_surface.contact(finger,outward)
					clearance=maxf(clearance,(surface-finger).dot(outward))
				aim+=outward*clearance
			author.limb(pose,arm,"lowerarm_"+str(side),wrist,rig.to_local(aim)-palm_offset,pole,weight)
			if upper and actor!=game.coach:
				var key := str(actor.get_instance_id())+str(side)
				var adjust: float=elbow_adjustments.get(key,0.)
				var elbow := rig.to_global(author.point(pose,"lowerarm_"+str(side)))
				var own_shoulder := rig.to_global(author.point(pose,arm))
				var awkward := elbow.y>own_shoulder.y+.035 or elbow.distance_to(Contact.joint(actor,"Head"))<.19
				# Hold the correction until the elbow clears the shoulder.
				if awkward: adjust=move_toward(adjust,1.,dt*3.)
				elif elbow.y<own_shoulder.y-.10: adjust=move_toward(adjust,0.,dt*.55)
				elbow_adjustments[key]=adjust
				pole=pole.lerp(Vector3(sign_*.55,-1.,-.20),adjust)
				if adjust>0.:
					author.limb(pose,arm,"lowerarm_"+str(side),wrist,rig.to_local(aim)-palm_offset,pole,weight)
			if blend>0.:
				var solved: Transform3D=author.world_pose(pose,rig.find_bone(wrist))
				author.set_world_basis(pose,wrist,solved.basis.orthonormalized().slerp(orientation,blend))
			if adjacent==game.coach and upper and blend>.95:
				# Close the remaining gap after IK has limited reach and turned
				# the wrist. Sample the jacket underneath the solved palm.
				if not shoulder_trim.has(actor): shoulder_trim[actor]={"side":side,"trim":0.}
				var wrist_goal: Vector3=rig.to_local(aim)-palm_offset
				for iteration in 4:
					var palm: Vector3=rig.to_global(author.point(pose,wrist).lerp(author.point(pose,"middle_01_"+str(side)),.8))
					var surface: Vector3=adjacent.dressed_surface.contact(palm,Vector3.UP)
					if surface.is_equal_approx(palm): break
					var correction := surface.y-.012+float(shoulder_trim[actor].trim)-palm.y
					if absf(correction)<.0015: break
					wrist_goal+=rig.global_basis.inverse()*(Vector3.UP*clampf(correction,-.08,.08))
					author.limb(pose,arm,"lowerarm_"+str(side),wrist,wrist_goal,pole,1.)
					author.set_world_basis(pose,wrist,orientation)
			for bone in [arm,"lowerarm_"+str(side),wrist]:
				var j := rig.find_bone(bone)
				rig.set_bone_pose_rotation(j,pose[j].basis.orthonormalized().get_rotation_quaternion())

	if present==circle.size() and facing_center:
		settle_time+=dt
		if settle_time>=.75:
			huddle_planted=true
			settle_time=.75
			var coach_rig: Skeleton3D=game.coach.skeleton
			for joint in ["Head","lowerarm_l","lowerarm_r"]:
				var id:=coach_rig.find_bone(joint)
				var parent:=coach_rig.get_bone_global_pose(coach_rig.get_bone_parent(id)).basis.orthonormalized()
				speech_joints[joint]=[id,coach_rig.get_bone_pose_rotation(id),parent.inverse()*Vector3.RIGHT,parent.inverse()*Vector3.UP]
			prepare_pointing_poses()
	else:
		settle_time=0.
	if present==circle.size() and not debrief_started:
		debrief_started=true
		game.say(game.coach, "Good work. Give your hitters time to approach. Bring it in.", 5.0)

func prepare_pointing_poses() -> void:
	var rig: Skeleton3D=game.coach.skeleton
	var author: RefCounted=game.coach.get_pose_author()
	var rest: Array=[]
	for id in rig.get_bone_count(): rest.append(rig.get_bone_pose(id))
	# Bend both knees against fixed soles. Countertranslate the lower spine
	# so the shoulders stay under the neighboring players' palms.
	var dip:=rest.duplicate()
	var hips:=rig.find_bone("pelvis")
	var spine:=rig.find_bone("spine_01")
	var shift:=Vector3(.025,-.052,0.)
	var hip_parent:=rig.get_bone_parent(hips)
	dip[hips].origin+=author.world_pose(rest,hip_parent).basis.inverse()*shift
	dip[spine].origin-=author.world_pose(rest,rig.get_bone_parent(spine)).basis.inverse()*shift
	for side in ["l","r"]:
		var foot: String="foot_"+side
		var ankle: Transform3D=author.world_pose(rest,rig.find_bone(foot))
		author.limb(dip,"thigh_"+side,"calf_"+side,foot,ankle.origin,Vector3.BACK)
		author.set_world_basis(dip,foot,ankle.basis.orthonormalized())
	for joint in ["pelvis","spine_01","thigh_l","calf_l","foot_l","thigh_r","calf_r","foot_r"]:
		var id:=rig.find_bone(joint)
		coach_dip[id]=[rest[id],dip[id]]
	var center:=circle.find(game.coach)
	for offset in [-3,3]:
		var neighbor: Node3D=circle[posmod(center+offset,circle.size())]
		var target:=rig.to_local(Contact.joint(neighbor,"spine_03"))
		var side: String="l" if target.x>0. else "r"
		var arm: String="upperarm_"+side
		var elbow: String="lowerarm_"+side
		var hand: String="hand_"+side
		var pose:=rest.duplicate()
		var shoulder: Vector3=author.point(pose,arm)
		var aim: Vector3=(target-shoulder).normalized()
		author.limb(pose,arm,elbow,hand,shoulder+aim*.47,Vector3(signf(target.x),-.75,0.),1.,156.)
		var joints: Array=[arm,elbow,hand]
		for digit in ["index","middle","ring","pinky"]:
			for segment in ["01","02","03"]:
				var name_: String=digit+"_"+segment+"_"+side
				var id:=rig.find_bone(name_)
				pose[id].basis=rig.get_bone_rest(id).basis
				joints.append(name_)
		var index: Vector3=author.point(pose,"index_03_"+side)-author.point(pose,"index_01_"+side)
		var span: Vector3=author.point(pose,"index_01_"+side)-author.point(pose,"pinky_01_"+side)
		var hands=preload("res://scripts/hand_setting_pose.gd")
		var wrist: Transform3D=author.world_pose(pose,rig.find_bone(hand))
		author.set_world_basis(pose,hand,hands.hand_basis(aim,Vector3.UP)*hands.hand_basis(index,span).inverse()*wrist.basis.orthonormalized())
		var heel: Vector3=author.point(pose,hand)-Vector3.UP*.018
		for digit in ["middle","ring","pinky"]:
			author.aim_joint(pose,digit+"_02_"+side,digit+"_03_"+side,heel)
		var rotations: Dictionary={}
		for name_ in joints:
			var id:=rig.find_bone(name_)
			rotations[id]=[rest[id].basis.orthonormalized().get_rotation_quaternion(),pose[id].basis.orthonormalized().get_rotation_quaternion()]
		pointing_poses.append(rotations)
		look_angles.append(clampf(atan2(target.x,target.z),-.74,.74))

func coach_address(t: float) -> void:
	# A call, a shorter follow-up and a pause. Keep shoulders available
	# for neighboring palms while emphasis travels through elbows and head.
	var beat:=fmod(t,4.8)
	var turn:=int(t/4.8)%2
	var first:=smoothstep(.14,.43,beat)*(1.-smoothstep(.68,1.20,beat))
	var second:=smoothstep(1.24,1.49,beat)*(1.-smoothstep(1.72,2.15,beat))
	var finish:=smoothstep(2.52,2.78,beat)*(1.-smoothstep(3.18,3.66,beat))
	var voice:=maxf(maxf(first,second),finish)*(.70+.30*cos(t*19.))
	var rig: Skeleton3D=game.coach.skeleton
	var face: ShaderMaterial=game.coach.get_meta("coach_face")
	face.set_shader_parameter("shout",voice)
	var emphasis:=maxf(.70*first,maxf(.35*second,finish))
	for id in coach_dip:
		var start: Transform3D=coach_dip[id][0]
		rig.set_bone_pose(id,start.interpolate_with(coach_dip[id][1],emphasis))
	for joint in speech_joints:
		var data: Array=speech_joints[joint]
		var pitch:=first*.55+finish*.28 if joint=="lowerarm_r" else second*.47+finish*.24
		var yaw:=0.
		if joint=="Head":
			pitch=.22*smoothstep(0.,.35,t)+.12*first-.05*second+.08*finish
			yaw=look_angles[turn]*(first+.66*second)+look_angles[1-turn]*finish
		rig.set_bone_pose_rotation(data[0],Quaternion(data[3],yaw)*Quaternion(data[2],-pitch)*data[1])
	for i in pointing_poses.size():
		var strength:=maxf(first,maxf(.65*second,.70*finish)) if i==turn else finish
		for id in pointing_poses[i]:
			var keys: Array=pointing_poses[i][id]
			if strength>.001:
				rig.set_bone_pose_rotation(id,keys[0].slerp(keys[1],strength))
			elif id!=speech_joints["lowerarm_l"][0] and id!=speech_joints["lowerarm_r"][0]:
				rig.set_bone_pose_rotation(id,keys[0])

func huddle_angle(actor: Node3D) -> float:
	var offset := actor.position-HUDDLE_CENTER
	return atan2(offset.x,offset.z)
