extends RefCounted
const PATH := "user://player.cfg"
const DEFAULTS := {"name":"Player","height_cm":195.58,"handedness":"Right"}

static func load_profile() -> Dictionary:
	var config := ConfigFile.new()
	config.load(PATH)
	return clean({"name":config.get_value("player","name",DEFAULTS.name),"height_cm":config.get_value("player","height_cm",DEFAULTS.height_cm),"handedness":config.get_value("player","handedness",DEFAULTS.handedness)})

static func clean(profile: Dictionary) -> Dictionary:
	return {"name":str(profile.get("name",DEFAULTS.name)).strip_edges().left(32),"height_cm":clampf(float(profile.get("height_cm",DEFAULTS.height_cm)),120.0,240.0),"handedness":"Left" if profile.get("handedness","Right") == "Left" else "Right"}

static func save_profile(profile: Dictionary) -> Error:
	var config := ConfigFile.new()
	var values := clean(profile)
	for key in values: config.set_value("player",key,values[key])
	return config.save(PATH)
