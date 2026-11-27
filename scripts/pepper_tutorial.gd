extends RefCounted

# All pairs face across the court, on the same side of the net as their partner.
const CENTERS := [Vector3(1.6,.04,-2.9),Vector3(-1.6,.04,1.1),Vector3(-1.6,.04,6.9),Vector3(1.6,.04,10.9)]
const FEED := .72
const ARRIVAL := 1.82
const RESET := 3.75
const Physics=preload("res://scripts/gym_physics.gd")
const Map=preload("res://scripts/mapped_reception.gd")
var released:Dictionary={}
var touched_at:=-INF
const CONTACT_POSE := .60
var pairs:Array[Dictionary]=[]
var game
var score:=0
var holding:=false
var needs_release:=false
var pressed_at:=INF
var feedback:Label
var finished:=false
var demonstrating:=false

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
	for i in 4:
		var receiver:Node3D=athletes[2*i]
		var feeder:Node3D=athletes[2*i+1]
		var direction:=Vector3.RIGHT if i%2==0 else Vector3.LEFT
		receiver.position=Vector3(0,.04,CENTERS[i].z)-direction*4.25
		feeder.position=Vector3(0,.04,CENTERS[i].z)+direction*4.25
		receiver.rotation.y=atan2(direction.x,direction.z)
		feeder.rotation.y=receiver.rotation.y+PI
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
		receiver.play_action("forearm")
		receiver.animator.seek(CONTACT_POSE,true)
		var platform:=hands(receiver)
		receiver.play_action("idle",0.)
		receiver.animator.advance(0.)
		var outcomes:=preload("res://scripts/demo_outcomes.gd").new()
		pairs.append({"rise":randf_range(2.35,3.05),"outcomes":outcomes,"cpu_misses":outcomes.next_misses(),"receiver":receiver,"feeder":feeder,"ball":orb,"age":-i*.21,"caught":false,"platform":platform,"flying":false,"hit":false,"swing":false,"origin":hands(feeder)})
	athletes[8].position=Vector3(-5.3,.04,2.)
	feedback.text="%d / 5 passes"%score
	if score==5: complete()

func start_human_turn() -> void:
	demonstrating=false
	var pair:=pairs[0]
	var demo:Node3D=pair.receiver
	var human:Node3D=game.setter
	var waiting:=human.position
	human.transform=demo.transform
	demo.position=waiting
	demo.play_action("idle")
	pair.receiver=human
	human.play_action("forearm",0.)
	human.animator.seek(CONTACT_POSE,true)
	pair.platform=hands(human)
	human.play_action("idle",.1)
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
	var speed:=maxf(1.,absf((pair.platform-pair.origin).dot(axis))/(ARRIVAL-FEED))
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

func tick(delta:float) -> void:
	if finished: return
	for i in pairs.size():
		var pair:=pairs[i]
		pair.age+=delta
		var t:float=pair.age
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
				pair.origin=game.coach_motion.toss(feeder,1.)
			if t<FEED+.16: game.coach_motion.toss(feeder,1.)
			elif t<ARRIVAL:
				feeder.play_action("base/Idle",.18)
				feeder.animator.advance(delta)
			if not pair.caught:
				var u:float=(t-FEED)/(ARRIVAL-FEED)
				orb.position=pair.origin.lerp(pair.platform,u)+Vector3.UP*4.*1.4*u*(1.-u)
			if active and not pair.swing and t>=ARRIVAL-CONTACT_POSE and not pair.caught:
				receiver.play_action("forearm",.08)
				pair.swing=true
			if pair.swing and not pair.caught: receiver.animator.seek(clampf(CONTACT_POSE+t-ARRIVAL,0.,CONTACT_POSE),true)
			if human and active and not pair.caught:
				for side in ["l","r"]:
					var wrist:=Physics.joint(receiver,"hand_"+side)
					var elbow:=Physics.joint(receiver,"lowerarm_"+side)
					var nearest:=Geometry3D.get_closest_points_between_segments(previous,orb.position,wrist,elbow)
					if nearest[0].distance_to(nearest[1])<=Physics.BALL_RADIUS+.055: touched_at=t
			var human_hit:=human and not released.is_empty() and bool(released.playable) and t-touched_at<=.095
			if not pair.caught and (human_hit or t>=ARRIVAL+(.14 if human else 0.)):
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
						CareerSession.checkpoint("pepper",score)
					else: feedback.text="%d / 5 passes   ·   Missed"%score
			if pair.caught:
				var u:=clampf((t-float(pair.contact_age))/sqrt(8.*float(pair.rise)/9.81),0.,1.)
				if pair.hit:
					var catch_at:Vector3=game.coach_motion.toss(feeder,0.)
					orb.position=game.arc(pair.contact_point,catch_at,u,pair.rise)
				else:
					orb.position=pair.contact_point.lerp(receiver.position+receiver.basis.z*-.42+Vector3.UP*.105,minf(1.,u*2.))
		receiver.animator.advance(delta)
		if t>=RESET:
			pair.rise=randf_range(2.35,3.05)
			if human:
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
			receiver.play_action("idle",.16)
			if i==0: needs_release=holding

func complete() -> void:
	finished=true
	CareerSession.checkpoint("pepper_complete",5)
	feedback.text="Pepper complete   ·   5 / 5 passes"
	game.finish_pepper()
