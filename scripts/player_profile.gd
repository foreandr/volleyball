extends RefCounted
const PATH := "user://player.cfg"
const DEFAULTS := {"name":"Player","height_cm":195.58,"handedness":"Right"}

const RATINGS := ["Forearm reception", "Forearm setting", "Forearm defense", "Hand setting", "Hand reception", "Hand defense", "Blocking", "Speed", "Stamina", "Underhand serve", "Standing float", "Jump float", "Spin serve", "Hybrid spin to float", "Hybrid float to spin", "Sky ball"]

static func generate() -> Dictionary:
	var values := {"name":"%s %s" % [["Kai","Maya","Noor","Luca","Sam","Imani","Rin","Alex","Jules","Ari","Leah","Sol"].pick_random(), ["Reyes","Park","Diallo","Costa","Singh","Chen","Silva","Ito","Martin","Aziz","Kim","Rivera"].pick_random()], "height_cm":randf_range(152.4,213.36), "vertical_in":randi_range(30,60), "wingspan_in":randi_range(58,90), "handedness":["Right","Left"].pick_random()}
	for rating in RATINGS:
		values[rating] = randi_range(20,99)
	return clean(values)

static func load_profile() -> Dictionary:
	var config := ConfigFile.new()
	config.load(PATH)
	var values := {}
	for key in config.get_section_keys("player") if config.has_section("player") else []:
		values[key] = config.get_value("player",key)
	return clean(values)

static func clean(profile: Dictionary) -> Dictionary:
	var result := {"name":str(profile.get("name",DEFAULTS.name)).strip_edges().left(32),"height_cm":clampf(float(profile.get("height_cm",DEFAULTS.height_cm)),152.4,213.36),"handedness":"Left" if profile.get("handedness","Right") == "Left" else "Right"}
	result.vertical_in = clampf(float(profile.get("vertical_in",30)),30,60)
	result.wingspan_in = clampf(float(profile.get("wingspan_in",result.height_cm / 2.54)),48,96)
	for rating in RATINGS:
		result[rating] = clampi(int(profile.get(rating,65)),0,100)
	return result

static func save_profile(profile: Dictionary) -> Error:
	var config := ConfigFile.new()
	var values := clean(profile)
	for key in values: config.set_value("player",key,values[key])
	return config.save(PATH)
