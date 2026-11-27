extends RefCounted
const PATH := "user://player.cfg"
const DEFAULTS := {"name":"Player","height_cm":195.58,"handedness":"Right"}

const KIT_CHOICES := {"Eyebrows":["Natural","Fine","Full"],"Facial hair":["Clean-shaven","Stubble","Moustache","Goatee","Short beard"],"Jersey length":["Standard","Short","Long"],"Jersey fit":["Untucked","Tucked"],"Ankle support":["None","Tape","Brace"],"Knee support":["None","Tape","Brace"],
	"Shoe cut":["Team","Low","Mid","High"],"Shoe design":["Team","Stripe","Twin stripe","Wave","Split"],
	"Shoe color":["Team","White","Black","Navy","Red","Gold","Teal"],"Sock height":["Team","Ankle","Below calf","Calf","Knee"],
	"Sock color":["Team","White","Black","Navy","Red","Gold","Teal"],"Leg sleeves":["Team","None","Three-quarter","Full"],
	"Underlayer":["Team","None","T-shirt","Long compression shirt"],"Headwear":["None","Headband","Cap"],
	"Sunglasses":["None","Sport"],"Finger tape":["Team","None","Left","Right","Both"],
	"Shorts design":["Team","Solid","Side panels","Double stripe","Diagonal trim"]}

const MEASUREMENTS := {
	"Weight (lb)":["weight_lb",90,300,165], "Standing reach (in)":["reach_in",65,120,96],
	"Hand length (in)":["hand_in",5,12,8], "Foot length (in)":["foot_in",7,15,10],
	"Head circumference (in)":["head_in",18,26,22]
}

const RATING_HELP := {
	"Charisma":"A teammate is more likely to honor your call for a set. Earn more fans at tryouts and attract better offers.",
	"Forearm reception":"Control a serve with your platform and keep the first pass near the setter.",
	"Forearm setting":"Deliver a bump set to an attacker when the ball is too low for your hands.",
	"Forearm defense":"Lift attacked balls off your platform and give a teammate time to play the second contact.",
	"Hand setting":"Place overhead sets and compensate for your movement during a jump set.",
	"Hand reception":"Control a high serve with an overhead pass.",
	"Hand defense":"Keep a high attack playable with an overhead dig.",
	"Blocking":"Challenge an attack above the tape and direct a touch back into court.",
	"Spike placement":"Aim a swing into an open lane or attack the edges of a block.",
	"Arm swing":"Generate hand speed through contact to add pace to an attack.",
	"Athleticism":"Explosive movement for approaches, takeoffs and changes of direction.",
	"Reflexes":"Shorten the delay before reacting to the ball.",
	"Strength":"Drive a harder attack and push a set farther across the court.",
	"Speed":"Cover ground to get behind a pass or close a gap at the net.",
	"Stamina":"Increase the energy available for repeated sprints, jumps and dives.",
	"Endurance":"Recover spent stamina faster between efforts.",
	"Willpower":"Keep working on reserve when your normal stamina is exhausted.",
	"Underhand serve":"Control the placement of a serve struck below the waist.",
	"Standing float":"Deliver a low-spin serve from a planted stance.",
	"Jump float":"Contact the float serve higher while controlling its placement.",
	"Spin serve":"Drive a jump serve with topspin to bring it down into the court.",
	"Hybrid spin to float":"Turn a spinning toss into a float contact.",
	"Hybrid float to spin":"Turn a float toss into a driven topspin contact.",
	"Sky ball":"Control the direction and depth of a very high serve."
}

const RATINGS := ["Charisma", "Forearm reception", "Forearm setting", "Forearm defense", "Hand setting", "Hand reception", "Hand defense", "Blocking", "Spike placement", "Arm swing", "Athleticism", "Reflexes", "Strength", "Speed", "Stamina", "Endurance", "Willpower", "Underhand serve", "Standing float", "Jump float", "Spin serve", "Hybrid spin to float", "Hybrid float to spin", "Sky ball"]

static func generate() -> Dictionary:
	var values := {"name":"%s %s" % [["Kai","Maya","Noor","Luca","Sam","Imani","Rin","Alex","Jules","Ari","Leah","Sol"].pick_random(), ["Reyes","Park","Diallo","Costa","Singh","Chen","Silva","Ito","Martin","Aziz","Kim","Rivera"].pick_random()], "height_cm":randf_range(152.4,213.36), "vertical_in":randi_range(30,60), "wingspan_in":randi_range(58,90), "handedness":["Right","Left"].pick_random()}
	values.age = randi_range(14,18)
	values.hometown = ["Hamilton","Burlington","Toronto","Oshawa","Kingston"].pick_random()
	for rating in RATINGS:
		values[rating] = randi_range(20,99)
	for key in KIT_CHOICES: values[key]=KIT_CHOICES[key].pick_random()
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
	result.age = clampi(int(profile.get("age",16)),14,18)
	result.hometown = str(profile.get("hometown","Riverside")).strip_edges().left(64)
	if result.hometown.is_empty(): result.hometown = "Riverside"
	for key in KIT_CHOICES:
		var choice=profile.get(key,KIT_CHOICES[key][0])
		result[key]=choice if choice in KIT_CHOICES[key] else KIT_CHOICES[key][0]
	for field in MEASUREMENTS.values():
		result[field[0]]=clampf(float(profile.get(field[0],field[3])),field[1],field[2])
	if profile.has("jersey_number"): result.jersey_number=clampi(int(profile.jersey_number),0,99)
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

static func perk_text(rating: String) -> String:
	match rating:
		"Strength": return "Long Reach at 70. Adds half a metre to your set range."
		"Reflexes": return "First Read at 70. React 15 ms sooner."
		_: return "In development"
