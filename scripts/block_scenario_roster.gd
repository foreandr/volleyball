extends RefCounted

const Profile = preload("res://scripts/player_profile.gd")
const Formation = preload("res://scripts/six_rotations.gd")

var path := "user://block_defense_roster.cfg"
var data := ConfigFile.new()
var read_error := OK

func load_starters(created:Dictionary) -> Array[Dictionary]:
	var starters:Array[Dictionary] = []
	var result := data.load(path)
	if result not in [OK, ERR_FILE_NOT_FOUND]:
		push_error("Could not read scenario roster: " + error_string(result))
		read_error=result
		data.clear()
	var added := false
	for side in 2:
		for slot in 7:
			var identity := (slot+1)%6 if slot<6 else 6
			var section := str(side)
			var key := str(identity)
			if not data.has_section_key(section,key):
				var base := created.duplicate(true) if side==0 and slot==0 and not created.is_empty() else Profile.generate()
				if not (side==0 and slot==0 and not created.is_empty()): base.handedness="Right"
				var inches := 77 if identity in [2,5] else randi_range(71,76)
				var old_inches := float(base.height_cm)/2.54
				var span_offset := clampf(float(base.get("wingspan_in",old_inches))-old_inches,-4.,4.)
				base.height_cm = inches*2.54
				base.wingspan_in = roundf(inches+span_offset)
				base.reach_in = Profile.natural_reach(inches,base.wingspan_in)
				base.weight_lb = Profile.natural_weight(inches)+(base.get("weight_lb",165)-Profile.natural_weight(old_inches))
				base.position = "Libero" if identity==6 else Formation.ROLES[identity]
				if identity==6: base.jersey_number=96
				if side==0 and identity==5: base.Blocking=100
				data.set_value(section,key,Profile.clean(base))
				added=true
			if slot<6: starters.append(profile(side,identity))
	if added and read_error==OK and data.save(path)!=OK: push_error("Could not save the initial scenario roster.")
	return starters

func profile(side:int,identity:int) -> Dictionary:
	return data.get_value(str(side),str(identity))

func save_player(side:int,identity:int,values:Dictionary) -> Error:
	if read_error!=OK: return read_error
	var previous:=profile(side,identity)
	data.set_value(str(side),str(identity),values)
	var result:=data.save(path)
	if result!=OK: data.set_value(str(side),str(identity),previous)
	return result
