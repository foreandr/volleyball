extends RefCounted
const NAMES := ["Both Arms","Left Arm","Right Arm","Both Forearms","Both Hands","Left Hand","Right Hand","Torso","Head","Both Legs","Left Leg","Right Leg","Whole Body","Individual Joint"]
const ROOTS := {"Both Arms":["upperarm_l","upperarm_r"],"Left Arm":["upperarm_l"],"Right Arm":["upperarm_r"],"Both Forearms":["lowerarm_l","lowerarm_r"],"Both Hands":["hand_l","hand_r"],"Left Hand":["hand_l"],"Right Hand":["hand_r"],"Torso":["spine_02"],"Head":["Head"],"Both Legs":["thigh_l","thigh_r"],"Left Leg":["thigh_l"],"Right Leg":["thigh_r"],"Whole Body":["pelvis"]}

static func roots(rig: Skeleton3D, group: String, selected: int) -> Array[int]:
	var result: Array[int] = []
	if group == "Individual Joint":
		if selected >= 0: result.append(selected)
		return result
	for name_ in ROOTS.get(group,[]):
		var index := rig.find_bone(name_)
		if index >= 0: result.append(index)
	return result

static func members(rig: Skeleton3D, group: String, selected: int) -> Array[int]:
	if group == "Individual Joint": return roots(rig,group,selected)
	var result: Array[int] = []
	for bone in rig.get_bone_count():
		var name_ := str(rig.get_bone_name(bone))
		var match_ := group == "Whole Body"
		var arm := name_.begins_with("upperarm_") or name_.begins_with("lowerarm_") or name_.begins_with("hand_") or finger(name_)
		var hand := name_.begins_with("hand_") or finger(name_)
		var leg := name_.begins_with("thigh_") or name_.begins_with("calf_") or name_.begins_with("foot_") or name_.begins_with("ball_")
		match group:
			"Both Arms","Left Arm","Right Arm": match_ = arm
			"Both Forearms": match_ = name_.begins_with("lowerarm_") or hand
			"Both Hands","Left Hand","Right Hand": match_ = hand
			"Both Legs","Left Leg","Right Leg": match_ = leg
			"Torso": match_ = name_ == "pelvis" or name_.begins_with("spine_") or name_.begins_with("clavicle_")
			"Head": match_ = name_ == "Head" or name_.begins_with("neck_")
		if group.begins_with("Left "): match_ = match_ and name_.ends_with("_l")
		if group.begins_with("Right "): match_ = match_ and name_.ends_with("_r")
		if match_: result.append(bone)
	return result

static func finger(name_: String) -> bool:
	return name_.begins_with("thumb_") or name_.begins_with("index_") or name_.begins_with("middle_") or name_.begins_with("ring_") or name_.begins_with("pinky_")
