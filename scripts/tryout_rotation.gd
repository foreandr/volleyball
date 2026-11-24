extends RefCounted

const Contact = preload("res://scripts/gym_physics.gd")
const CART := Vector3(-3.5,0,-2.6)
const WAIT := [Vector3(0,.04,1.35),Vector3(-1.35,.04,.2),Vector3(1.65,.04,.25)]
const STATIONS := [CART,Vector3(3.5,0,-2.6)]
const HANDLE := Vector3(.12,.04,-.78)
var tosses := 0
var station := 0
var routes := preload("res://scripts/tryout_paths.gd").new()
var game: Control
var roster: Array[Node3D] = []
var workers: Array[Dictionary] = []
var stock: Array[RigidBody3D] = []
var loose: Array[RigidBody3D] = []
var paused_balls := {}
var issued: RigidBody3D
var turn := 0
var attempts := 0
var round_index := 0
var basket: Node3D
var net_hit := {}
var random := RandomNumberGenerator.new()

func configure(host: Control) -> void:
	game = host
	random.randomize()
	roster.append(game.setter)
	for i in [1,2]: roster.append(game.athlete(WAIT[i],["","377f95","93543a"][i]))
	for i in [1,2]: preload("res://scripts/practice_kit.gd").apply(roster[i],false,i)
	for i in 2:
		var actor: Node3D = game.athlete(Vector3(-4+i*8,.04,5),"395b48")
		preload("res://scripts/practice_kit.gd").apply(actor,false,i+3)
		workers.append({"actor":actor,"cargo":[],"goal":null,"lifting":0.0,"start":Vector3.ZERO})
	basket = Node3D.new()
	game.world.add_child(basket)
	basket.position = CART
	var cloth: Material = game.gym.material("184e46")
	var metal: Material = game.gym.material("9faeae")
	for x in [-.54,.54]:
		for z in [-.34,.34]:
			cart_box(Vector3(x,.45,z),Vector3(.045,.84,.045),metal)
			cart_box(Vector3(x,.10,z),Vector3(.09,.13,.11),metal)
		cart_box(Vector3(x,.75,0),Vector3(.035,.35,.72),cloth)
	for z in [-.35,.35]: cart_box(Vector3(0,.75,z),Vector3(1.10,.35,.035),cloth)
	cart_box(Vector3(0,1.01,-.42),Vector3(.93,.044,.044),metal)
	for x in [-.43,.43]: cart_box(Vector3(x,.91,-.42),Vector3(.044,.20,.044),metal)
	cart_box(Vector3(0,.58,0),Vector3(1.10,.035,.72),cloth)
	for i in 12:
		var body := RigidBody3D.new()
		body.name = "PracticeBall%d" % (i+1)
		body.freeze = true
		body.mass = .27
		body.continuous_cd = true
		body.contact_monitor = true
		body.max_contacts_reported = 4
		body.body_entered.connect(func(other):
			if other is StaticBody3D and other.collision_layer==64:
				net_reaction(body.position,body.linear_velocity))
		body.collision_layer = 128
		body.collision_mask = Contact.GYM|Contact.EQUIPMENT|64|128
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
		store_ball(body)
	var net := Node3D.new()
	game.world.add_child(net)
	net.position = Vector3(0,1.97,4)
	var net_shape := BoxShape3D.new()
	net_shape.size = Vector3(9.6,1,.04)
	Contact.solid(net,net_shape,64)

func cart_box(at: Vector3,size: Vector3,style: Material) -> void:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = at
	part.material_override = style
	basket.add_child(part)

func store_ball(body: RigidBody3D) -> void:
	body.freeze = true
	body.collision_layer = 0
	body.show()
	var i := stock.size()
	body.position = basket.position+Vector3((i%4-1.5)*.226,.70+.17*(i/8),((i/4)%2-.5)*.28)
	stock.append(body)

func station_ready(dt: float) -> bool:
	var requested := (tosses/10)%2
	if requested!=station:
		var previous := basket.position
		basket.position=basket.position.move_toward(STATIONS[requested],dt*4.7)
		for body in stock: body.position+=basket.position-previous
		game.coach.position=basket.position+HANDLE
		game.coach.rotation.y=0
		game.coach.play_action("base/Walk")
		grip_handle()
		if basket.position.distance_to(STATIONS[requested])<.01:
			station=requested
			game.trace("cart_station",{"station":station,"tosses":tosses})
		return false
	return walk(game.coach,basket.position+HANDLE,dt,4.2)

func grip_handle() -> void:
	var rig: Skeleton3D = game.coach.skeleton
	var author: RefCounted = game.coach.get_pose_author()
	var pose: Array = []
	for i in rig.get_bone_count(): pose.append(rig.get_bone_pose(i))
	for side in ["l","r"]:
		var x := .19 if side=="l" else -.19
		var hand := basket.position+Vector3(x,1.035,-.48)
		author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,rig.to_local(hand),Vector3(signf(x),-.8,0))
		for bone in ["upperarm_"+side,"lowerarm_"+side]:
			var idx := rig.find_bone(bone)
			rig.set_bone_pose_rotation(idx,pose[idx].basis.orthonormalized().get_rotation_quaternion())

func take_ball() -> bool:
	if issued: return true
	if stock.is_empty(): return false
	issued = stock.pop_back()
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
	attempts += 1
	if attempts==2:
		attempts=0
		turn=(turn+1)%3
		if turn==0: round_index+=1
	game.setter=roster[turn]

func walk(actor: Node3D,goal: Vector3,dt: float,speed: float) -> bool:
	var dir := (goal-actor.position).slide(Vector3.UP)
	if dir.length()<.12:
		actor.play_action("idle")
		return true
	var waypoint := routes.waypoint(actor,goal,dt)
	dir = (waypoint-actor.position).slide(Vector3.UP)
	actor.rotation.y=lerp_angle(actor.rotation.y,atan2(dir.x,dir.z),minf(1,dt*9))
	var step := dir.limit_length(speed*dt)
	var next: Vector3 = game.contacts.travel(game.world,actor.position,step,actor.height_cm*.01)
	var along := (next-actor.position).dot(dir.normalized())
	if along<step.length()*.65: routes.reroute(actor,goal)
	next.y=actor.position.y
	actor.position=next
	actor.play_action("base/Walk" if speed<2.4 else "run")
	return false

func tick(dt: float) -> void:
	for i in 3:
		if i==turn: continue
		var waiting := roster[i]
		waiting.animator.advance(dt)
		walk(waiting,WAIT[(i-turn+3)%3],dt,5.2)
	for worker in workers: collect(worker,dt)
	if not net_hit.is_empty():
		game.gym.get_node("DynamicNet").sample(net_hit,game.clock)
		if game.clock-net_hit.time>1.5: net_hit.clear()

func nearest(at: Vector3,worker: Dictionary,limit: float) -> RigidBody3D:
	var best: RigidBody3D
	for body in loose:
		if body.position.y>1.55 or body.linear_velocity.length()>4: continue
		var occupied := false
		for other in workers:
			if other.actor!=worker.actor and other.goal==body: occupied=true
		if occupied: continue
		var d := body.position.distance_to(at)
		if d<limit:
			limit=d
			best=body
	return best

func collect(w: Dictionary,dt: float) -> void:
	var actor: Node3D=w.actor
	actor.animator.advance(dt)
	var cargo: Array=w.cargo
	if not w.goal and cargo.size()<2:
		w.goal=nearest(actor.position,w,2.7 if not cargo.is_empty() else INF)
	if w.goal:
		var body: RigidBody3D=w.goal
		var delta := (body.position-actor.position).slide(Vector3.UP)
		if delta.length()>.79:
			walk(actor,body.position-delta.normalized()*.48,dt,5.7)
		else:
			actor.rotation.y=atan2(delta.x,delta.z)
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
		if walk(actor,basket.position+Vector3(.1,.04,.72),dt,5.1):
			for body in cargo:
				store_ball(body)
				game.trace("cart_return",{"id":body.name,"remaining":stock.size()})
			cargo.clear()
	else: actor.play_action("idle")
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
