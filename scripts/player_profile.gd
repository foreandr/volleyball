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

const HAIRSTYLES := ["Natural","Crop","Side swept","High top","Curtains","Faux hawk","Top knot","Long crop","Waves"]
const HAIR_COLORS := {"Natural":Color("503d31"),"Black":Color("211c1d"),"Dark brown":Color("4f3328"),"Chestnut":Color("754c38"),"Auburn":Color("994c37"),"Blond":Color("c19a64"),"Platinum":Color("e1d6bd")}
const MEASUREMENTS := {
	"Weight (lb)":["weight_lb",90,300,165], "Standing reach (in)":["reach_in",65,120,96],
	"Hand length (in)":["hand_in",5,12,8], "Foot length (in)":["foot_in",7,15,10],
	"Head circumference (in)":["head_in",20,23,22]
}

const BUILD_HELP := {
	"height_cm":"Body height increases contact height. Taller athletes have a lower maximum speed.",
	"wingspan_in":"Fingertip to fingertip with both arms spread. A longer span covers more court but lowers maximum athleticism.",
	"weight_lb":"More mass adds strength for hitting and setting, with a lower maximum running speed.",
	"reach_in":"Floor to fingertips with one arm overhead and feet flat. Higher reach helps high contacts and blocking, with a small arm-speed trade-off.",
	"hand_in":"Larger hands improve overhead control. Smaller hands allow a faster maximum arm swing.",
	"foot_in":"Larger feet help stabilize the block. Smaller feet allow faster reaction ratings.",
	"head_in":"Changes the size of the head."
}

static func natural_weight(inches:float) -> int:
	return roundi(165.+(inches-74.)*3.5)

static func natural_reach(inches:float,span:float) -> int:
	return roundi(inches+22.+(span-inches)*.5)

# x is the effective ceiling, y is the build adjustment to the trained rating.
static func build_rules(p:Dictionary) -> Dictionary:
	var height:=float(p.height_cm)/2.54
	var mass:=clampf((float(p.weight_lb)-natural_weight(height))/70.,-1.,1.)
	var span:=clampf((float(p.wingspan_in)-height)/10.,-1.,1.)
	var reach:=clampf((float(p.reach_in)-natural_reach(height,p.wingspan_in))/10.,-1.,1.)
	var hand:=clampf((float(p.hand_in)-8.)/3.,-1.,1.)
	var foot:=clampf((float(p.foot_in)-10.)/4.,-1.,1.)
	return {"Speed":Vector2i(clampi(roundi(97.-(height-74.)*.75-9.*mass),72,100),roundi(-4.*mass)),
		"Strength":Vector2i(clampi(roundi(96.+5.*mass),84,100),roundi(8.*mass)),
		"Athleticism":Vector2i(clampi(roundi(97.-8.*span),84,100),0),
		"Arm swing":Vector2i(clampi(roundi(97.-4.*hand-3.*reach),86,100),0),
		"Hand reception":Vector2i(100,roundi(4.*hand)),"Hand setting":Vector2i(100,roundi(4.*hand)),
		"Blocking":Vector2i(100,roundi(4.*reach+3.*foot)),
		"Reflexes":Vector2i(clampi(roundi(97.-4.*foot),88,100),0)}

static func effective_skill(p:Dictionary,rating:String,rules:Dictionary) -> int:
	var rule:Vector2i=rules.get(rating,Vector2i(100,0))
	return clampi(int(p.get(rating,65))+rule.y,0,rule.x)

static func training_limit(rule:Vector2i) -> int:
	return mini(100,rule.x-rule.y)

static func build_note(field:String,p:Dictionary) -> String:
	if field=="head_in": return BUILD_HELP[field]
	var rules:=build_rules(p)
	var changes:Dictionary={"height_cm":["Speed"],"weight_lb":["Speed","Strength"],"wingspan_in":["Athleticism"],"reach_in":["Blocking","Arm swing"],"hand_in":["Hand reception","Hand setting","Arm swing"],"foot_in":["Blocking","Reflexes"]}
	var lines:=PackedStringArray()
	for skill in changes[field]:
		var rule:Vector2i=rules[skill]
		lines.append("%s  %d / %d"%[skill,effective_skill(p,skill,rules),rule.x])
	return BUILD_HELP[field]+"\n\n"+ "\n".join(lines)

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

const POSITIONS := ["Setter","P1","P2","M1","M2","Libero","Opposite"]

static func natural_position(profile:Dictionary) -> String:
	var position:=str(profile.get("position",""))
	if position in POSITIONS: return position
	var number:=int(profile.get("jersey_number",str(profile.get("name","")).hash()))
	var weights:=[profile.get("Hand setting",65),profile.get("Forearm reception",65),profile.get("Blocking",65),profile.get("Forearm defense",65),profile.get("Arm swing",65)]
	return ["Setter","P1" if number%2==0 else "P2","M1" if number%2==0 else "M2","Libero","Opposite"][weights.find(weights.max())]

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
	result["Hair"]=profile.get("Hair","Natural") if profile.get("Hair","Natural") in HAIRSTYLES else "Natural"
	result["Hair color"]=profile.get("Hair color","Natural") if HAIR_COLORS.has(profile.get("Hair color","Natural")) else "Natural"
	if not profile.has("weight_lb"): result.weight_lb=natural_weight(result.height_cm/2.54)
	if not profile.has("reach_in"): result.reach_in=natural_reach(result.height_cm/2.54,profile.get("wingspan_in",result.height_cm/2.54))
	result.position=natural_position(profile)
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
