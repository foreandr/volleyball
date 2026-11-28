extends SceneTree

const Palm = preload("res://scripts/spike_palm_contact.gd")

func _initialize() -> void:
	run.call_deferred()

func sample_hand(z:float, direction:float, x:float=0.) -> Dictionary:
	var p:=Vector3(x,2.,z)
	return {"points":[p,p+Vector3.UP*.11,p+Vector3.DOWN*.08],
		"normal":Vector3.BACK*direction,"shoulder":p+Vector3(0.,-.6,-.25*direction)}

func run() -> void:
	var failures:=0
	for hz:int in [30,60,120]:
		for side:float in [-1.,1.]:
			var shot:=Vector3.BACK*side*27.
			var good:=false
			var brush:=false
			var dt:=1./hz
			for frame in ceili(.16*hz):
				var before:=(-.55+6.*frame*dt)*side
				var one:=sample_hand(before,side)
				var two:=sample_hand(before+6.*side*dt,side)
				var center:=Vector3.UP*2.
				var hit:=Palm.sweep(one,two,center,center,dt)
				if not good and not hit.is_empty(): good=Palm.outgoing(hit,shot).is_equal_approx(shot)
				var tip:=center+Vector3.UP*.16
				var graze:=Palm.sweep(one,two,tip,tip,dt)
				if not graze.is_empty(): brush=graze.part==Palm.FINGERTIP and Palm.outgoing(graze,shot).length()<9.1
				if not Palm.sweep(one,two,center+Vector3.RIGHT*.13,center+Vector3.RIGHT*.13,dt).is_empty(): failures+=1
			print("CONTACT CHECK ",hz," Hz side ",side," drive ",good," brush ",brush)
			if not good or not brush: failures+=1
	var held:={"normal":Vector3.BACK,"outward":Vector3.BACK,"hand_velocity":Vector3.ZERO,
		"incoming":Vector3.DOWN*4.,"reach":Vector3(.1,.7,.25),"part":Palm.PALM}
	if Palm.outgoing(held,Vector3.BACK*30.).length()>=9.: failures+=1
	held.hand_velocity=Vector3.BACK*9.
	held.reach.z=-.2
	if Palm.transfer(held,Vector3.BACK)!=0.: failures+=1
	change_scene_to_file("res://scenes/block_defense_scenario.tscn")
	await scene_changed
	var page=current_scene
	page.set_process(false)
	var g=page.game
	var touched:=0
	var captures:=0
	var hard:=0
	for rep in 8:
		seed(185+rep)
		var lane:String=["left","middle","right"][rep%3]
		g.start_attack_plan(3,1,{lane:1 if lane=="middle" else 2},true)
		for frame in 580:
			var last:int=g.flight_number
			g.tick_match(1./60.,page.ground)
			if g.flight_kind=="set" and last!=g.flight_number:
				var setter=g.players[g.last_player]
				var toward:Vector3=g.Bump.HandPose.zone_four_facing(setter.position,g.ZONE_FOUR)
				if setter.basis.z.angle_to(toward)>deg_to_rad(10.): failures+=1
				print("SET CONTACT ",lane," focus degrees ",rad_to_deg(setter.basis.z.angle_to(toward)))
			if g.flight_kind=="spike" and last!=g.flight_number:
				var actor=g.players[g.last_player]
				var driver=g.attackers[g.team(g.last_player)]
				var touch:Dictionary=driver.strike_sample
				if touch.is_empty():
					failures+=1
					break
				touched+=1
				var packet:Dictionary=g.replay.current.back()
				var speed:float=g.velocity.length()*3.6
				var id:int=g.last_player
				var part:int=touch.part
				await process_frame
				await process_frame
				g.replay.toggle(g,true,[packet,packet] as Array[Dictionary])
				var hand:=Palm.sample(actor.skeleton,driver)
				var at:Vector3=driver.to_global(hand.points[part])
				var gap:=at.distance_to(g.ball.global_position)-Palm.BALL_RADIUS-float(Palm.PAD_RADII[part])
				print("CONTACT CHECK rally ",rep," ",lane," ",actor.handedness," part ",part," speed ",snappedf(speed,.1)," km/h replay surface gap ",snappedf(gap,.001)," m"," swing velocity ",touch.hand_velocity)
				if absf(gap)<=.035: captures+=1
				if part==Palm.PALM and speed>60.: hard+=1
				g.replay.toggle(g,false)
				break
			if g.phase==g.Phase.DEAD: break
	print("CONTACT CHECK totals ",touched," contacts, ",captures," aligned replay captures, ",hard," hard drives")
	quit(1 if failures or touched<4 or captures!=touched or hard<1 else 0)
