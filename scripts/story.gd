extends Control
var screen := ""
var column: VBoxContainer

func _ready() -> void:
	column = VBoxContainer.new()
	MenuPresentation.mount_menu(self,column)
	if CareerSession.defense_finished:
		CareerSession.defense_finished=false
		defense_score()
	elif not StorySession.career_lesson.is_empty():
		StorySession.career_lesson=""
		controls_tutorial()
	elif CareerSession.enter_origin:
		CareerSession.enter_origin = false
		origin()
	else: show_home()

func clear_menu(title: String) -> void:
	screen = title
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	MenuPresentation.heading(column,"Career" if title == "MY CAREER" else "Load career",title)

func add_button(text: String, action: Callable) -> Button:
	var result := Button.new()
	result.name = text.replace(" ","")
	result.text = text
	result.alignment=HORIZONTAL_ALIGNMENT_LEFT
	result.add_theme_font_size_override("font_size",20)
	result.custom_minimum_size.y = 52
	result.pressed.connect(action)
	column.add_child(result)
	return result

func show_home() -> void:
	clear_menu("MY CAREER")
	if not CareerSession.athlete_id.is_empty():
		var saved := CareerSession.profile()
		var plate := PanelContainer.new()
		column.add_child(plate)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",14)
		plate.add_child(row)
		var portrait := TextureRect.new()
		portrait.texture=SchoolHeadshots.request(saved)
		portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.custom_minimum_size=Vector2(84,84)
		row.add_child(portrait)
		var facts := VBoxContainer.new()
		facts.alignment=BoxContainer.ALIGNMENT_CENTER
		row.add_child(facts)
		MenuPresentation.section_label(facts,str(saved.hometown)+"  /  Age "+str(saved.age))
		var nameplate := Label.new()
		nameplate.text=str(saved.name)
		nameplate.add_theme_font_size_override("font_size",25)
		facts.add_child(nameplate)
		add_button("Continue career",resume).grab_focus()
		add_button("Controls tutorial",controls_tutorial)
		add_button("Play scrimmage",scrimmage)
		add_button("Defense evaluation",defense_tryout)
		add_button("Player development",development)
		add_button("Wardrobe",func():
			CareerSession.outfitting=true
			MenuPresentation.load_scene("res://scenes/create.tscn"))
	var create := add_button("Create athlete",func():
		CareerSession.creating = true
		MenuPresentation.load_scene("res://scenes/create.tscn"))
	if CareerSession.athlete_id.is_empty(): create.grab_focus()
	if CareerSession.data.has_section("athletes"): add_button("Load athlete",choose_athlete)
	if not StorySession.saved_stories().is_empty(): add_button("Legacy careers",show_load)
	add_button("Back",open_menu)

func controls_tutorial() -> void:
	clear_menu("CONTROLS TUTORIAL")
	var lessons:Dictionary={"Serving":"serving_camp","Serve receive":"receive_cpu_serves","Setting":"setting_camp","Attacking":"attacking_camp","Blocking":"blocking_camp","Digging":"digging_camp"}
	for title in lessons:
		var entry:=add_button(title,func():
			StorySession.career_lesson=lessons[title]
			MenuPresentation.load_scene("res://scenes/"+StorySession.career_lesson+".tscn"))
		if title=="Setting": entry.grab_focus()
	add_button("Guided scrimmage",scrimmage.bind(true))
	add_button("My Career",show_home)

func scrimmage(guided:=false) -> void:
	StorySession.guided_scrimmage=guided
	StorySession.career_scrimmage=true
	StorySession.offline_controller=0
	StorySession.offline_size=3
	StorySession.offline_away_size=3
	StorySession.offline_roster.assign([CareerSession.profile()])
	for i in 5: StorySession.offline_roster.append(CareerSession.Profile.generate())
	MenuPresentation.load_scene("res://scenes/offline_match.tscn")

func development(selected := "") -> void:
	clear_menu("PLAYER DEVELOPMENT")
	var id := CareerSession.athlete_id
	var points := int(CareerSession.data.get_value("points",id,0))
	var info := Label.new()
	var badges: Array = CareerSession.data.get_value("badges",id,[])
	MenuPresentation.wallet(column,points)
	info.text="%d fans    /    Team chemistry %d" % [CareerSession.fans(),CareerSession.team_chemistry()]
	if not badges.is_empty(): info.text+="    /    "+", ".join(badges)
	column.add_child(info)
	var active: Button
	for rating in ["vertical_in"]+CareerSession.Profile.RATINGS:
		var athlete := CareerSession.Profile.clean(CareerSession.profile())
		var value := float(athlete[rating])
		var cost:=CareerSession.price(rating,value)
		var rule:Vector2i=CareerSession.Profile.build_rules(athlete).get(rating,Vector2i(100,0))
		var vertical:bool=rating=="vertical_in"
		var title:String="Vertical jump" if vertical else str(rating)
		var upgrade := add_button("%s   %s%s    %d VP" % [title,value if vertical else CareerSession.Profile.effective_skill(athlete,rating,{rating:rule})," in" if vertical else " / "+str(rule.x),cost],func():
			if value>=(60 if vertical else CareerSession.Profile.training_limit(rule)) or points<cost: return
			athlete[rating] = value+(.25 if vertical else 1.)
			CareerSession.data.set_value("athletes",id,athlete)
			CareerSession.data.set_value("points",id,points-cost)
			CareerSession.persist()
			development(rating))
		MenuPresentation.rating_bar(column,null,value)
		if rating==selected or active==null: active=upgrade
		MenuPresentation.stat_help(upgrade,upgrade,title,"Jump height on serves, attacks and blocks." if vertical else CareerSession.Profile.RATING_HELP[rating])
	add_button("Back",show_home)
	if active: active.grab_focus()

func choose_athlete() -> void:
	clear_menu("ATHLETES")
	for id in CareerSession.data.get_section_keys("athletes") if CareerSession.data.has_section("athletes") else []:
		var athlete: Dictionary=CareerSession.data.get_value("athletes",id)
		var entry := add_button("%s    /    %s" % [athlete.name,athlete.hometown],func():
			CareerSession.select(id)
			resume())
		entry.tooltip_text="Age %d   /   %s" % [athlete.age,CareerSession.data.get_value("indoor_setter_6v6_"+id,"stage","origin")]
		add_button("Delete "+str(athlete.name),confirm_delete.bind(id,athlete.name))
	add_button("Back",show_home)
	for child in column.get_children():
		if child is Button:
			child.grab_focus()
			break

func confirm_delete(id: String,athlete_name: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title="Delete athlete"
	dialog.dialog_text="Delete %s and their career progress?" % athlete_name
	dialog.ok_button_text="Delete"
	add_child(dialog)
	dialog.confirmed.connect(func():
		if CareerSession.delete_athlete(id): show_home()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
	dialog.get_cancel_button().grab_focus()

func resume() -> void:
	match CareerSession.stage():
		"origin": origin()
		"position": position_menu()
		"after_tryout": after_tryout()
		_: MenuPresentation.load_scene(CareerSession.CHAPTER)

func after_tryout() -> void:
	if CareerSession.data.get_value(CareerSession.key(),"tryout_place",-1)==2:
		MenuPresentation.load_scene(CareerSession.CHAPTER)
		return
	clear_menu("AFTER TRYOUTS")
	if not CareerSession.data.get_value("signed",CareerSession.athlete_id,false):
		add_button("Accept club exhibition offer    %d VP" % CareerSession.offer_value(),func():
			if CareerSession.accept_offer(): after_tryout())
	var place := clampi(CareerSession.data.get_value(CareerSession.key(),"tryout_place",2),0,2)
	var coach := Label.new()
	coach.text=["Coach Ellis: You earned the starting spot. See you at practice.","Coach Ellis: You're our backup setter. Stay ready.","Coach Ellis: You didn't make this roster. You can try out again."][place]
	column.add_child(coach)
	add_button("Player development",development).grab_focus()
	add_button("Repeat tryout",func():
		CareerSession.data.set_value(CareerSession.key(),"tryout_scorecard",[])
		if CareerSession.checkpoint("tutorial",0): MenuPresentation.load_scene(CareerSession.CHAPTER))
	add_button("My Career",show_home)

func defense_tryout() -> void:
	MenuPresentation.load_scene("res://scenes/defense_tryout.tscn")

func defense_score() -> void:
	clear_menu("DEFENSE EVALUATION")
	var score := int(CareerSession.data.get_value(CareerSession.key(),"defense_last",0))
	var result := Label.new()
	result.text="%d / 5 attacks dug" % score
	result.add_theme_font_size_override("font_size",28)
	column.add_child(result)
	var coach := Label.new()
	coach.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	coach.text="Coach Ellis: That's a playable first touch. Take that into the next scrimmage." if score>=3 else "Coach Ellis: Get behind the swing and hold your platform through contact."
	column.add_child(coach)
	add_button("My Career",show_home).grab_focus()
	add_button("Run it again",defense_tryout)

func origin() -> void:
	clear_menu("TRYOUT WEEK")
	var opening := Label.new()
	opening.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	opening.text="Monday, 6:40 a.m. Your name is on the Falcons tryout sheet. The starting setter graduated in June. Coach Ellis rolls a cart to the net and points to the basket at the pin. “Show me a ball your hitter can use.”"
	column.add_child(opening)
	add_button("Controls tutorial",controls_tutorial)
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
