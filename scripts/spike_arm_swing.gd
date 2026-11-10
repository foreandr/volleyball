extends RefCounted

# Name, wrist at full draw, elbow pole, wrist arc, follow-through, extension delay.
const VARIANTS := [
	["High bow", Vector3(0.04,0.34,-0.15), Vector3(-0.85,0.52,-0.74), Vector3(-0.06,0.13,-0.05), Vector3(0.28,-0.28,0.43), 1.25],
	["High bow, compact", Vector3(0.09,0.26,-0.12), Vector3(-0.95,0.57,-0.51), Vector3(0.04,0.16,-0.10), Vector3(0.24,-0.26,0.40), 1.65],
	["High bow, wide elbow", Vector3(-0.04,0.31,-0.17), Vector3(-1.20,0.46,-0.52), Vector3(-0.18,0.12,0.02), Vector3(0.40,-0.31,0.37), 1.45],
	["High bow, elbow leads", Vector3(0.09,0.30,-0.20), Vector3(-0.52,0.71,-0.74), Vector3(0.07,0.14,-0.14), Vector3(0.30,-0.38,0.32), 1.85],
	["High bow, cross-body finish", Vector3(0.07,0.33,-0.14), Vector3(-0.85,0.58,-0.60), Vector3(-0.02,0.15,-0.04), Vector3(0.53,-0.27,0.27), 1.35],
	["Low bow", Vector3(0.15,0.05,-0.12), Vector3(-1.0,0.16,-0.84), Vector3(-0.05,0.09,-0.10), Vector3(0.24,-0.35,0.42), 1.35],
	["Low bow, deep draw", Vector3(0.02,0.19,-0.29), Vector3(-0.80,0.19,-1.00), Vector3(-0.09,0.10,-0.16), Vector3(0.27,-0.33,0.45), 1.55],
	["Low bow, tucked elbow", Vector3(0.12,0.17,-0.17), Vector3(-0.64,0.22,-0.83), Vector3(0.06,0.12,-0.13), Vector3(0.34,-0.39,0.34), 1.70],
	["Low bow, outside path", Vector3(-0.13,0.20,-0.20), Vector3(-1.10,0.16,-0.65), Vector3(-0.16,0.10,-0.04), Vector3(0.12,-0.38,0.50), 1.30],
	["Low bow, quick release", Vector3(0.05,0.22,-0.16), Vector3(-0.86,0.28,-0.78), Vector3(-0.02,0.08,-0.08), Vector3(0.30,-0.34,0.40), 1.08],
	["Snap", Vector3(0.07,0.09,-0.15), Vector3(-0.98,0.10,-0.58), Vector3(0.04,0.07,-0.14), Vector3(0.30,-0.44,0.37), 1.72],
	["Snap, short draw", Vector3(0.10,0.10,-0.07), Vector3(-1.0,0.12,-0.53), Vector3(0.02,0.08,-0.10), Vector3(0.21,-0.43,0.42), 1.92],
	["Snap, high elbow", Vector3(0.08,0.11,-0.13), Vector3(-0.82,0.60,-0.70), Vector3(0.02,0.04,-0.17), Vector3(0.35,-0.42,0.35), 1.72],
	["Snap, tight finish", Vector3(0.14,0.14,-0.09), Vector3(-0.76,0.30,-0.68), Vector3(0.02,0.12,-0.14), Vector3(0.31,-0.37,0.20), 1.88],
	["Snap, outside release", Vector3(-0.08,0.10,-0.12), Vector3(-1.14,0.12,-0.58), Vector3(-0.14,0.08,-0.12), Vector3(0.13,-0.46,0.36), 1.54],
	["Circular", Vector3(-0.06,-0.02,-0.23), Vector3(-0.87,0.05,-0.66), Vector3(-0.19,-0.10,-0.12), Vector3(0.27,-0.46,0.41), 1.30],
	["Circular, compact loop", Vector3(0.02,0.04,-0.17), Vector3(-0.79,0.12,-0.76), Vector3(-0.11,-0.06,-0.12), Vector3(0.28,-0.43,0.29), 1.49],
	["Circular, wide loop", Vector3(-0.16,-0.05,-0.25), Vector3(-1.16,0.02,-0.64), Vector3(-0.24,-0.09,-0.07), Vector3(0.33,-0.44,0.48), 1.24],
	["Circular, low loop", Vector3(-0.04,-0.14,-0.26), Vector3(-0.90,-0.16,-0.76), Vector3(-0.14,-0.17,-0.14), Vector3(0.26,-0.50,0.38), 1.31],
	["Circular, late whip", Vector3(0.03,0.02,-0.22), Vector3(-0.79,0.16,-0.87), Vector3(-0.12,-0.10,-0.18), Vector3(0.44,-0.39,0.33), 1.78],
]

static func apply(pose: Array, author: RefCounted, index: int, ball: Vector3, weight: float, extension: float, follow: float, charge: float) -> void:
	var variant: Array = VARIANTS[index]
	var shoulder: Vector3 = author.point(pose,"upperarm_r")
	var draw: Vector3 = variant[1]
	var pole: Vector3 = variant[2]
	var arc: Vector3 = variant[3]
	var through: Vector3 = variant[4]
	var delay: float = variant[5]
	if index >= 15:
		# Lead into the loop during the charge instead of locking the wrist in a high draw.
		draw += arc*lerpf(-0.42,0.34,charge)
	var wrist_target := ball-(ball-shoulder).normalized()*0.06
	var reach := pow(extension,delay)
	var arc_offset := arc*sin(PI*extension)
	var target := (shoulder+draw).lerp(wrist_target,reach)+arc_offset
	var finish := smoothstep(0.20,1.0,follow)
	target = target.lerp(shoulder+through,finish)
	var elbow_pole := pole.lerp(Vector3(-0.75,0.38,-0.28),smoothstep(0.62,1.0,extension))
	var elbow_limit := lerpf(112.0,172.0,smoothstep(0.29,0.98,extension))
	elbow_limit = lerpf(elbow_limit,145.0,finish)
	author.limb(pose,"upperarm_r","lowerarm_r","hand_r",target,elbow_pole,weight,elbow_limit)

	if index == 5:
		tuck_low_bow_hand(pose,author,weight*(1.0-smoothstep(0.03,0.55,extension)))

static func tuck_low_bow_hand(pose: Array, author: RefCounted, weight: float) -> void:
	if weight <= 0.0: return
	var rig: Skeleton3D = author.rig
	var elbow: Vector3 = author.point(pose,"lowerarm_r")
	var wrist: Vector3 = author.point(pose,"hand_r")
	var chest: Vector3 = author.point(pose,"spine_03")
	var draw_target := chest+Vector3(-0.11,-0.12,0.12)
	var forearm := (wrist-elbow).normalized()
	var inward := (draw_target-elbow).normalized()
	var forearm_basis: Basis = author.world_pose(pose,rig.find_bone("lowerarm_r")).basis
	var forearm_turn := Quaternion.IDENTITY.slerp(Quaternion(forearm,inward),weight)
	author.set_world_basis(pose,"lowerarm_r",Basis(forearm_turn)*forearm_basis)
	wrist = author.point(pose,"hand_r")
	var fingers: Vector3 = (author.point(pose,"middle_01_r")-wrist).normalized()
	var target := (chest-wrist+Vector3.DOWN*0.18).normalized()
	var basis: Basis = author.world_pose(pose,rig.find_bone("hand_r")).basis
	var turn := Quaternion(fingers,target)
	var amount := minf(1.0,deg_to_rad(65.0)/maxf(turn.get_angle(),0.001))*weight
	author.set_world_basis(pose,"hand_r",Basis(Quaternion.IDENTITY.slerp(turn,amount))*basis)
