extends RefCounted

# All pairs face lengthwise, on the same side of the net as their partner.
const CENTERS := [Vector3(1.6,.04,-2.9),Vector3(-1.6,.04,1.1),Vector3(-1.6,.04,6.9),Vector3(1.6,.04,10.9)]
const FEED := .72
const ARRIVAL := 1.82
const RESET := 3.25
const CONTACT_POSE := .60
var pairs:Array[Dictionary]=[]
var game
var score:=0
var holding:=false
var needs_release:=false
var pressed_at:=INF
var feedback:Label
var finished:=false

func configure(host,readout:Label,completed:int) -> void:
	game=host
	feedback=readout
	score=clampi(completed,0,5)
	var athletes:Array=host.rotation_drill.roster.duplicate()
	for worker in host.rotation_drill.workers: athletes.append(worker.actor)
	for i in 4:
		var receiver:Node3D=athletes[2*i]
		var feeder:Node3D=athletes[2*i+1]
		var direction:=Vector3.BACK if i<2 else Vector3.FORWARD
		receiver.position=CENTERS[i]-direction*1.55
		feeder.position=CENTERS[i]+direction*1.55
		receiver.rotation.y=atan2(direction.x,direction.z)
		feeder.rotation.y=receiver.rotation.y+PI
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
		pairs.append({"receiver":receiver,"feeder":feeder,"ball":orb,"age":-i*.21,"caught":false,"platform":platform,"flying":false,"hit":false,"swing":false,"origin":hands(feeder)})
	athletes[8].position=Vector3(-5.3,.04,2.)
	feedback.text="%d / 5 passes"%score
	if score==5: complete()

func hands(actor:Node3D) -> Vector3:
	var physics=preload("res://scripts/gym_physics.gd")
	return (physics.joint(actor,"hand_l")+physics.joint(actor,"hand_r"))*.5+Vector3.UP*.075

func button(down:bool) -> void:
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
		var active:=i!=0 or (holding and not needs_release)
		if t<FEED:
			pair.origin=game.coach_motion.toss(feeder,clampf(t/FEED,0.,1.))
			orb.position=pair.origin
		else:
			if not pair.flying:
				pair.flying=true
				feeder.play_action("idle",.2)
			feeder.animator.advance(delta)
			if t<ARRIVAL:
				orb.position=game.arc(pair.origin,pair.platform,(t-FEED)/(ARRIVAL-FEED),1.05)
			if active and not pair.swing and t>=ARRIVAL-CONTACT_POSE and not pair.caught:
				receiver.play_action("forearm",.08)
				pair.swing=true
			if pair.swing and not pair.caught: receiver.animator.seek(clampf(CONTACT_POSE+t-ARRIVAL,0.,CONTACT_POSE),true)
			if t>=ARRIVAL and not pair.caught:
				pair.caught=true
				pair.hit=active
				if i==0:
					if active:
						score+=1
						var offset:=roundi((pressed_at-(ARRIVAL-CONTACT_POSE))*1000.)
						var grade:="On time" if absi(offset)<=85 else ("%d ms early"%(-offset) if offset<0 else "%d ms late"%offset)
						feedback.text="%d / 5 passes   ·   %s"%[score,grade]
						CareerSession.checkpoint("pepper",score)
					else: feedback.text="%d / 5 passes   ·   Missed"%score
			if pair.caught:
				var u:=clampf((t-ARRIVAL)/1.04,0.,1.)
				if pair.hit:
					orb.position=game.arc(pair.platform,hands(feeder),u,.98)
				else:
					orb.position=pair.platform.lerp(receiver.position+receiver.basis.z*-.42+Vector3.UP*.105,minf(1.,u*2.))
		receiver.animator.advance(delta)
		if t>=RESET:
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
