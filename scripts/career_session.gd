extends Node

const Profile = preload("res://scripts/player_profile.gd")
var store_path := "user://my_career.cfg"
const CHAPTER := "res://scenes/setter_tryout.tscn"
const BADGES := ["Pinpoint","Tempo Switch","Four Corners"]
var data := ConfigFile.new()
var athlete_id := ""
const STARTING_VP := 100
var outfitting := false
var creating := false
var enter_origin := false
var defense_finished := false
var prompt := AcceptDialog.new()
var command := LineEdit.new()
var paused_before := false
var show_commands := false

func _ready() -> void:
	data.load(store_path)
	if data.has_section("athletes"):
		var changed := false
		for id in data.get_section_keys("athletes"):
			var saved: Dictionary = data.get_value("athletes",id)
			var clean := Profile.clean(saved)
			for field in ["age","hometown","handedness","name"]:
				if not saved.has(field):
					saved[field] = clean[field]
					changed = true
			data.set_value("athletes",id,saved)
			SchoolHeadshots.request(saved)
		if changed: persist()
	athlete_id = data.get_value("selection","athlete","")
	process_mode = Node.PROCESS_MODE_ALWAYS
	prompt.title = "Career console"
	prompt.exclusive = true
	var fields := VBoxContainer.new()
	prompt.add_child(fields)
	var commands := GridContainer.new()
	commands.columns = 2
	commands.add_theme_constant_override("h_separation",24)
	fields.add_child(commands)
	for entry in [
		["vison","Show each person's current command"],
		["visoff","Hide command bubbles"],
		["replay","Inspect recent indoor practice or return to live play"],
		["quest intro","Start the tryout introduction"],
		["quest tutorial","Start the setting tutorial"],
		["quest rep 1-32","Jump to a tutorial rep (for example, quest rep 5)"],
		["quest complete","Jump to tryout completion"]
	]:
		for value in entry:
			var label := Label.new()
			label.text = value
			commands.add_child(label)
	fields.add_child(command)
	command.placeholder_text = "Enter a command"
	command.custom_minimum_size.x = 480
	prompt.register_text_enter(command)
	prompt.confirmed.connect(run_command)
	prompt.visibility_changed.connect(func():
		if not prompt.visible: get_tree().paused = paused_before)
	add_child(prompt)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_QUOTELEFT:
		get_viewport().set_input_as_handled()
		paused_before = get_tree().paused
		get_tree().paused = true
		command.clear()
		prompt.popup_centered()
		command.grab_focus()

func run_command() -> void:
	var parts := command.text.strip_edges().to_lower().split(" ",false)
	match "".join(parts):
		"replay":
			var scene := get_tree().current_scene
			if scene and scene.has_method("toggle_practice_replay"): scene.call_deferred("toggle_practice_replay")
			return
		"vison","vizon":
			show_commands = true
			return
		"visoff","vizoff":
			show_commands = false
			return
	if parts.size() < 2 or parts[0] != "quest": return
	var stage := str(parts[1])
	var rep := 0
	if stage == "rep":
		if parts.size() != 3 or not parts[2].is_valid_int() or int(parts[2]) not in range(1,33): return
		rep = int(parts[2])-1
		stage = "tutorial"
	elif stage not in ["intro","tutorial","complete"]: return
	if athlete_id.is_empty():
		var draft := base_profile()
		draft.name="Tryout athlete"
		if not create_athlete(draft): return
	creating = false
	data.set_value(key(),"tryout_scorecard",[])
	if not checkpoint(stage,32 if stage == "complete" else rep): return
	MenuPresentation.load_scene.call_deferred(CHAPTER)

func base_profile() -> Dictionary:
	var values := Profile.clean({"height_cm":74*2.54})
	values.age=17
	values.hometown="London"
	values.country="CA"
	values.name=""
	values.position="Unassigned"
	values.jersey_number=7
	for rating in Profile.RATINGS: values[rating] = 40
	return values

const PRICES := {"Charisma":1,"Spike placement":3,"Arm swing":3,"Athleticism":3,"Strength":3,"Stamina":3,"Endurance":3,"Speed":6,"vertical_in":5}

func price(key:String,value:float) -> int:
	var levels:=maxf(0.,(value-30.)*4. if key=="vertical_in" else value-40.)
	return int(PRICES.get(key,2))*(1+floori(levels/15.))

func spent(values:Dictionary) -> int:
	var total:=0
	for key in ["vertical_in"]+Profile.RATINGS:
		var base:=30. if key=="vertical_in" else 40.
		var unit:=.25 if key=="vertical_in" else 1.
		for i in maxi(0,roundi((float(values.get(key,base))-base)/unit)):
			total+=price(key,base+i*unit)
	return total

func balance() -> int:
	return data.get_value("points",athlete_id,0)

func gear_price(_key:String,_item:String,_owned:Array) -> int:
	return 0

func inventory() -> Array:
	return data.get_value("gear",athlete_id,[]).duplicate()

func gear_cost(values: Dictionary,owned: Array) -> int:
	var price := 0
	for field in Profile.KIT_CHOICES: price+=gear_price(field,values[field],owned)
	return price

func save_gear(values: Dictionary,owned: Array) -> void:
	for field in Profile.KIT_CHOICES:
		var item: String=field+"/"+str(values[field])
		if item not in owned: owned.append(item)
	data.set_value("gear",athlete_id,owned)

func equip(values: Dictionary) -> bool:
	var owned := inventory()
	var price := gear_cost(values,owned)
	if price>balance(): return false
	var before := data.encode_to_text()
	data.set_value("points",athlete_id,balance()-price)
	data.set_value("athletes",athlete_id,Profile.clean(values))
	save_gear(values,owned)
	if persist(): return true
	data.clear()
	data.parse(before)
	return false

func create_athlete(values: Dictionary) -> bool:
	values=Profile.clean(values)
	values.age=clampi(values.age,16,18)
	var remaining := STARTING_VP-spent(values)-gear_cost(values,[])
	if remaining<0 or str(values.name).strip_edges().is_empty(): return false
	var before := data.encode_to_text()
	var previous := athlete_id
	athlete_id=Crypto.new().generate_random_bytes(12).hex_encode()
	data.set_value("athletes",athlete_id,values)
	data.set_value("selection","athlete",athlete_id)
	data.set_value("points",athlete_id,remaining)
	save_gear(values,[])
	if checkpoint("origin",0):
		SchoolHeadshots.request(values)
		return true
	data.clear()
	data.parse(before)
	athlete_id=previous
	return false

func delete_athlete(id: String) -> bool:
	if not data.has_section_key("athletes",id): return false
	var snapshot := data.encode_to_text()
	var previous := athlete_id
	for section in ["athletes","badges","points","team_chemistry","gear","fans","signed"]:
		if data.has_section_key(section,id): data.erase_section_key(section,id)
	var chapter := "indoor_setter_6v6_"+id
	if data.has_section(chapter): data.erase_section(chapter)
	if athlete_id==id:
		athlete_id=""
		data.set_value("selection","athlete","")
	if persist(): return true
	data.clear()
	data.parse(snapshot)
	athlete_id=previous
	return false

func select(id: String) -> void:
	athlete_id = id
	data.set_value("selection","athlete",id)
	persist()

func persist() -> bool:
	var temp := store_path+".tmp"
	if data.save(temp) == OK and DirAccess.rename_absolute(temp,store_path) == OK: return true
	OS.alert("Could not save My Career progress.")
	return false

func profile() -> Dictionary:
	return data.get_value("athletes",athlete_id,{})

func key() -> String:
	return "indoor_setter_6v6_"+athlete_id

func stage() -> String:
	return data.get_value(key(),"stage","origin")

func progress() -> int:
	return data.get_value(key(),"rep",0)

func checkpoint(at: String, rep: int) -> bool:
	var completed:Array=data.get_value(key(),"completed_opening_drills",[])
	var cleared_drill:={"hitting_lesson":"setting_lesson","hitting_lesson_complete":"hitting_lesson","setting_lesson":"moving_reception","setting_lesson_complete":"setting_lesson","pepper":"footwork","pepper_complete":"pepper","moving_reception":"pepper","moving_reception_complete":"moving_reception"}
	if at in cleared_drill and cleared_drill[at] not in completed:
		completed.append(cleared_drill[at])
		data.set_value(key(),"completed_opening_drills",completed)
	data.set_value(key(),"stage",at)
	data.set_value(key(),"rep",rep)
	return persist()

func credit(rep: int) -> bool:
	var cleared: Array = data.get_value(key(),"cleared",[])
	if rep not in cleared:
		cleared.append(rep)
		data.set_value("fans",athlete_id,fans()+1+roundi(float(profile().get("Charisma",40))*.06))
		if (rep+1)%8 == 0:
			data.set_value("points",athlete_id,data.get_value("points",athlete_id,0)+3)
	data.set_value(key(),"cleared",cleared)
	var badges: Array = data.get_value("badges",athlete_id,[])
	for i in 3:
		var earned := true
		for required in [[0,1],[2,3,4,5],range(32)][i]:
			if required not in cleared: earned = false
		if earned and BADGES[i] not in badges: badges.append(BADGES[i])
	data.set_value("badges",athlete_id,badges)
	return checkpoint("tutorial",rep+1)


func team_chemistry() -> int:
	return data.get_value("team_chemistry",athlete_id,0)

func credit_team_return() -> bool:
	if athlete_id.is_empty(): return false
	var previous := team_chemistry()
	data.set_value("team_chemistry",athlete_id,previous+1)
	if persist(): return true
	data.set_value("team_chemistry",athlete_id,previous)
	return false

func fans() -> int:
	return data.get_value("fans",athlete_id,0)

func offer_value() -> int:
	return 10+fans()/3

func accept_offer() -> bool:
	if stage()!="after_tryout" or data.get_value("signed",athlete_id,false): return false
	var previous := balance()
	data.set_value("points",athlete_id,previous+offer_value())
	data.set_value("signed",athlete_id,true)
	if persist(): return true
	data.set_value("points",athlete_id,previous)
	data.set_value("signed",athlete_id,false)
	return false

func record_defense(did_dig: bool) -> bool:
	if athlete_id.is_empty(): return false
	var before := data.encode_to_text()
	var reps := int(data.get_value(key(),"defense_reps",0))+1
	var score := int(data.get_value(key(),"defense_score",0))+int(did_dig)
	if reps==5:
		var best := int(data.get_value(key(),"defense_best",0))
		data.set_value(key(),"defense_last",score)
		data.set_value(key(),"defense_best",maxi(score,best))
		data.set_value("points",athlete_id,balance()+maxi(0,score-best))
	data.set_value(key(),"defense_reps",reps%5)
	data.set_value(key(),"defense_score",0 if reps==5 else score)
	if persist():
		defense_finished=reps==5
		return true
	data.clear()
	data.parse(before)
	return false

const EVENTS := {"Grass doubles":[2,1],"Grass triples":[3,1],"Grass fours":[4,1],"Beach doubles":[2,3],"Indoor sixes":[6,0]}
const LEAGUES := ["Local","Regional","Elite"]
var tournament:=""

func circuit_record() -> Dictionary:
	return data.get_value("circuits",athlete_id,{}).duplicate(true)

func match_reward(won:bool,rallies:int,seconds:float,grade:float) -> int:
	if athlete_id.is_empty(): return 0
	var minutes:=minf(seconds/60.,rallies*.65)
	var award:=maxi(1,roundi(minutes*(12.+6.*grade+(3. if won else 0.))))
	var before:=data.encode_to_text()
	if EVENTS.has(tournament):
		var record:=circuit_record()
		var wins:=int(record.get(tournament,0))
		award=roundi(award*(1.+.1*mini(2,wins/3)))
		if won: record[tournament]=wins+1
		data.set_value("circuits",athlete_id,record)
	data.set_value("points",athlete_id,balance()+award)
	var athlete:=Profile.clean(profile())
	var rules:=Profile.build_rules(athlete)
	var mastered:=0
	for skill in Profile.ordered_ratings():
		var cap:=60 if skill=="vertical_in" else Profile.training_limit(rules.get(skill,Vector2i(100,0)))
		if athlete[skill]>=cap or athlete.prestige[skill]>0: mastered+=1
	var xp:float=data.get_value("perk_xp",athlete_id,0.)
	data.set_value("perk_xp",athlete_id,xp+minutes*mastered/(Profile.RATINGS.size()+1.))
	if persist(): return award
	data.clear()
	data.parse(before)
	return 0

func train_mastery(key_name:String,reset:bool) -> bool:
	var p:=Profile.clean(profile())
	var rank:=int(p.prestige[key_name])
	var ceiling:float=(60 if key_name=="vertical_in" else Profile.training_limit(Profile.build_rules(p).get(key_name,Vector2i(100,0))))+2*rank
	var tier:=int(p.perk_tiers[key_name])
	var xp:=float(data.get_value("perk_xp",athlete_id,0.))
	var cost:=4+2*tier
	var before:=data.encode_to_text()
	if reset:
		if rank>=5 or p[key_name]<ceiling: return false
		p.prestige[key_name]=rank+1
		p[key_name]=0
	else:
		if tier>=4 or p[key_name]<ceiling or xp<cost: return false
		data.set_value("perk_xp",athlete_id,xp-cost)
		p.perk_tiers[key_name]=tier+1
	data.set_value("athletes",athlete_id,p)
	if persist(): return true
	data.clear()
	data.parse(before)
	return false
