extends RefCounted

var carts
var setter:Node3D
var coach:Node3D
var station:Vector3
var home_dock:Vector3
var coach_docks:Array[Vector3]=[]
var cargo:Array=[]
var loose:RigidBody3D
var route:Array[Vector3]=[]
var pushing:Node3D
var returning:=false
var stride:=0.
var stage:="ready"

func configure(rotation,athlete:Node3D,feeder:Node3D) -> void:
	carts=rotation
	setter=athlete
	coach=feeder
	station=setter.position
	home_dock=station+Vector3(-.88,0,0)
	coach_docks=[carts.basket.position,coach.to_global(Vector3(-.90,0,.13))]
	carts.bins[0].position=home_dock
	carts.bins[0].show()

func receive(ball:RigidBody3D,at:Vector3,caught:bool) -> void:
	ball.position=at
	ball.show()
	if caught:
		cargo.append(ball)
		if setter.position.distance_to(station)>.15: stage="carry"
		else:
			carts.begin_unload(setter,0,cargo)
			stage="deposit"
	else:
		loose=ball
		stage="retrieve"

func walk_to(point:Vector3,dt:float) -> bool:
	var direction:=point-setter.position
	if direction.length()<.06: return true
	setter.rotation.y=lerp_angle(setter.rotation.y,atan2(direction.x,direction.z),1.-exp(-9.*dt))
	setter.play_action("base/Walk",.15)
	setter.position=setter.position.move_toward(point,dt*2.4)
	return false

func start_push(cart:Node3D,goal:Vector3) -> void:
	pushing=cart
	route.assign([Vector3(-5.75,cart.position.y,cart.position.z),Vector3(-5.75,goal.y,goal.z),goal])
	stage="grip"

func busy(dt:float) -> bool:
	match stage:
		"ready":
			if not carts.stock.is_empty() or carts.waiting_ball or carts.issued: return false
			var dock:=coach_docks[1] if carts.basket.position.distance_to(coach_docks[0])<.3 else coach_docks[0]
			start_push(carts.bins[0],dock)
		"retrieve":
			if walk_to(Vector3(loose.position.x,station.y,loose.position.z),dt):
				cargo.append(loose)
				loose=null
				stage="carry"
		"carry":
			cargo[0].position=preload("res://scripts/gym_physics.gd").palm(setter,"l")
			if walk_to(station,dt):
				carts.begin_unload(setter,0,cargo)
				stage="deposit"
		"deposit":
			carts.place_in_cart(setter,cargo,dt)
			if cargo.is_empty(): stage="reset"
		"reset":
			if walk_to(station,dt):
				setter.rotation.y=lerp_angle(setter.rotation.y,PI,1.-exp(-dt*5.))
				setter.play_action("idle",.24)
				setter.animator.advance(dt)
				if absf(angle_difference(setter.rotation.y,PI))<.025: stage="ready"
		"grip":
			var grip:=pushing.to_global(Vector3(0,0,-.75))
			grip.y=station.y
			if walk_to(grip,dt): stage="push"
		"push":
			var goal:=route[0]
			var before:=pushing.position
			var travel:=goal-before
			pushing.rotation.y=lerp_angle(pushing.rotation.y,atan2(travel.x,travel.z),1.-exp(-5.*dt))
			pushing.position=pushing.position.move_toward(goal,dt*1.75)
			setter.position=pushing.to_global(Vector3(0,0,-.75))
			setter.position.y=station.y
			setter.rotation.y=pushing.rotation.y
			stride=carts.push_pose(setter,pushing,stride,before.distance_to(pushing.position))
			if not returning:
				for i in carts.loads[0].size(): carts.loads[0][i].position=carts.cart_slot(pushing,i)
			if pushing.position.distance_to(goal)<.01:
				route.pop_front()
				if route.is_empty():
					if returning:
						returning=false
						stage="reset"
					else:
						var empty:Node3D=carts.basket
						carts.basket=pushing
						carts.bins[0]=empty
						for ball in carts.loads[0]: carts.store_ball(ball)
						carts.loads[0].clear()
						returning=true
						start_push(empty,home_dock)
	return true
