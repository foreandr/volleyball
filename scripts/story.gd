extends Control
var screen := ""
var column: VBoxContainer

func _ready() -> void:
	column = VBoxContainer.new()
	MenuPresentation.mount_menu(self,column)
	if CareerSession.enter_origin:
		CareerSession.enter_origin = false
		origin()
	elif CareerSession.stage()=="after_tryout": after_tryout()
	else: show_home()

func clear_menu(title: String) -> void:
	screen = title
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	MenuPresentation.heading(column,"Career" if title == "CAREER" else "Load career",title)

func add_button(text: String, action: Callable) -> Button:
	var result := Button.new()
	result.name = text.replace(" ","")
	result.text = text
	result.custom_minimum_size.y = 52
	result.pressed.connect(action)
	column.add_child(result)
	return result

func show_home() -> void:
	clear_menu("MY CAREER")
	if not CareerSession.athlete_id.is_empty():
		add_button("Continue  /  "+str(CareerSession.profile().name),resume).grab_focus()
		add_button("Player development",development)
	var create := add_button("Create athlete",func():
		CareerSession.creating = true
		MenuPresentation.load_scene("res://scenes/create.tscn"))
	if CareerSession.athlete_id.is_empty(): create.grab_focus()
	if CareerSession.data.has_section("athletes"): add_button("Select athlete",choose_athlete)
	if not StorySession.saved_stories().is_empty(): add_button("Legacy careers",show_load)
	add_button("Back",open_menu)

func development() -> void:
	clear_menu("PLAYER DEVELOPMENT")
	var id := CareerSession.athlete_id
	var points := int(CareerSession.data.get_value("points",id,0))
	var info := Label.new()
	var badges: Array = CareerSession.data.get_value("badges",id,[])
	info.text = "%d upgrade points   ·   %s" % [points,"No badges yet" if badges.is_empty() else ", ".join(badges)]
	info.text+="    /    Team Chemistry %d"%CareerSession.team_chemistry()
	column.add_child(info)
	for rating in CareerSession.Profile.RATINGS:
		var athlete := CareerSession.profile()
		var value := int(athlete[rating])
		var upgrade := add_button("%s   %d" % [rating,value],func():
			athlete[rating] = value+1
			CareerSession.data.set_value("athletes",id,athlete)
			CareerSession.data.set_value("points",id,points-1)
			CareerSession.persist()
			development())
		upgrade.disabled = points<=0 or value>=100
	var back := add_button("Back",show_home)
	back.grab_focus()
	for child in column.get_children():
		if child is Button and not child.disabled:
			child.grab_focus()
			break

func choose_athlete() -> void:
	clear_menu("ATHLETES")
	for id in CareerSession.data.get_section_keys("athletes"):
		add_button(CareerSession.data.get_value("athletes",id).name,func():
			CareerSession.select(id)
			resume())
	add_button("Back",show_home)
	for child in column.get_children():
		if child is Button:
			child.grab_focus()
			break

func resume() -> void:
	match CareerSession.stage():
		"origin": origin()
		"position": position_menu()
		"after_tryout": after_tryout()
		_: MenuPresentation.load_scene(CareerSession.CHAPTER)

func after_tryout() -> void:
	clear_menu("AFTER TRYOUTS")
	var place := clampi(CareerSession.data.get_value(CareerSession.key(),"tryout_place",2),0,2)
	var coach := Label.new()
	coach.text=["Coach Ellis: You earned the starting spot. See you at practice.","Coach Ellis: You're our backup setter. Stay ready.","Coach Ellis: You didn't make this roster. You can try out again."][place]
	column.add_child(coach)
	add_button("Player development",development).grab_focus()
	add_button("Repeat tryout",func():
		CareerSession.data.set_value(CareerSession.key(),"tryout_scorecard",[])
		if CareerSession.checkpoint("tutorial",0): MenuPresentation.load_scene(CareerSession.CHAPTER))
	add_button("My Career",show_home)

func origin() -> void:
	clear_menu("CHOOSE YOUR ORIGIN")
	add_button("Indoor",func():
		if CareerSession.checkpoint("position",0): position_menu()).grab_focus()
	add_button("Beach",func(): pass).disabled = true
	add_button("Back",show_home)

func position_menu() -> void:
	clear_menu("INDOOR  /  POSITION")
	add_button("Setter",func():
		if CareerSession.checkpoint("intro",0): resume()).grab_focus()
	for role in ["P1","P2","Right side","M1","M2","Libero"]:
		add_button(role,func(): pass).disabled = true
	add_button("Back",origin)

func show_load() -> void:
	clear_menu("LOAD CAREER")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440,330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var saves := VBoxContainer.new()
	saves.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saves.add_theme_constant_override("separation",10)
	scroll.add_child(saves)
	for record in StorySession.saved_stories():
		var entry := Button.new()
		entry.text = record.profile.name
		entry.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		entry.tooltip_text = entry.text
		entry.name = "Slot_"+record.id
		entry.custom_minimum_size.y = 52
		entry.pressed.connect(func():
			if not StorySession.load_story(record.id): show_load())
		saves.add_child(entry)
	add_button("Back",show_home)
	if saves.get_child_count() > 0: saves.get_child(0).grab_focus()

func open_menu() -> void:
	MenuPresentation.load_scene("res://scenes/main.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if screen == "MY CAREER": open_menu()
		elif screen == "INDOOR  /  POSITION": origin()
		else: show_home()
