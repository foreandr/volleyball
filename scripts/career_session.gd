extends Node

const Profile = preload("res://scripts/player_profile.gd")
var store_path := "user://my_career.cfg"
const CHAPTER := "res://scenes/setter_tryout.tscn"
const BADGES := ["Pinpoint","Tempo Switch","Four Corners"]
var data := ConfigFile.new()
var athlete_id := ""
var creating := false
var enter_origin := false
var prompt := AcceptDialog.new()
var command := LineEdit.new()
var paused_before := false

func _ready() -> void:
	data.load(store_path)
	athlete_id = data.get_value("selection","athlete","")
	process_mode = Node.PROCESS_MODE_ALWAYS
	prompt.title = "Career console"
	prompt.exclusive = true
	var fields := VBoxContainer.new()
	prompt.add_child(fields)
	var syntax := Label.new()
	syntax.text = "quest intro   /   quest tutorial   /   quest rep 1–32   /   quest complete"
	fields.add_child(syntax)
	fields.add_child(command)
	command.placeholder_text = "quest tutorial"
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
	if parts.size() < 2 or parts[0] != "quest": return
	var stage := str(parts[1])
	var rep := 0
	if stage == "rep":
		if parts.size() != 3 or not parts[2].is_valid_int() or int(parts[2]) not in range(1,33): return
		rep = int(parts[2])-1
		stage = "tutorial"
	elif stage not in ["intro","tutorial","complete"]: return
	if athlete_id.is_empty(): create_athlete(base_profile())
	creating = false
	data.set_value(key(),"tryout_scorecard",[])
	if not checkpoint(stage,32 if stage == "complete" else rep): return
	MenuPresentation.load_scene.call_deferred(CHAPTER)

func base_profile() -> Dictionary:
	var values := Profile.load_profile()
	for rating in Profile.RATINGS: values[rating] = 40
	return values

func spent(values: Dictionary) -> int:
	var total := 0
	for rating in Profile.RATINGS: total += maxi(0,int(values.get(rating,40))-40)
	return total

func create_athlete(values: Dictionary) -> bool:
	if spent(values)>100 or str(values.name).strip_edges().is_empty(): return false
	var id := Crypto.new().generate_random_bytes(12).hex_encode()
	data.set_value("athletes",id,Profile.clean(values))
	athlete_id = id
	select(id)
	return checkpoint("origin",0)

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
	data.set_value(key(),"stage",at)
	data.set_value(key(),"rep",rep)
	return persist()

func credit(rep: int) -> bool:
	var cleared: Array = data.get_value(key(),"cleared",[])
	if rep not in cleared:
		cleared.append(rep)
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
