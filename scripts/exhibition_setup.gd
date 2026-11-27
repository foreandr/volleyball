extends VBoxContainer

const Profile = preload("res://scripts/player_profile.gd")
const Ball = preload("res://scripts/animation_ball_preview.gd")
const Venue = preload("res://scripts/match_venue.gd")
const Xbox = preload("res://scripts/xbox_controls.gd")
const PAGES := ["Teams", "Ball", "Arena", "Rules"]
const COLORS := [Color("287fda"),Color("d9874e"),Color("983c48"),Color("387765"),Color("ebdeb7"),Color("514781")]
const OFFENSE := ["Spike placement","Arm swing","Strength","Hand setting","Spin serve"]
const DEFENSE := ["Forearm reception","Forearm defense","Hand defense","Blocking","Reflexes"]
const POINTS := [7,11,15,21,25]
const CROWDS := [0,16,48,96]
var section := 0
var athletes: Array = []
var lineups: Array = [[],[]]
var sizes := [2,2]
var side := 0
var slot := -1
var sheet := 0
var picker := -1
var scouting_labels: Array = [null,null]
var previous_art: Texture2D
var changed_player := Vector2i(-1,-1)
var venue := 0
var attendance := 16
var points := 21
var brand := "Mikasa"
var controller := 0
var start_match: Callable
var back: Callable

func configure(launch: Callable, exit_page: Callable) -> void:
	start_match=launch
	back=exit_page
	var saved = StorySession.match_preference("exhibition",{})
	if saved is Dictionary:
		athletes=saved.get("athletes",[])
		lineups=saved.get("lineups",[[],[]])
		sizes=saved.get("sizes",[2,2])
		venue=clampi(saved.get("venue",0),0,2)
		attendance=saved.get("crowd",16)
		points=saved.get("points",21)
		controller=clampi(saved.get("controller",0),-1,1)
		StorySession.kit_colors=saved.get("colors",StorySession.kit_colors)
	brand=StorySession.match_preference("ball_brand","Mikasa")
	if not Ball.BALL_PALETTES.has(brand): brand="Mikasa"
	if athletes.is_empty():
		athletes.append(Profile.load_profile())
		if CareerSession.data.has_section("athletes"):
			for id in CareerSession.data.get_section_keys("athletes"):
				athletes.append(Profile.clean(CareerSession.data.get_value("athletes",id)))
		var used_names: Array=athletes.map(func(p): return p.name)
		while athletes.size()<48:
			var p:=Profile.generate()
			if p.name in used_names: continue
			used_names.append(p.name)
			p.jersey_number=athletes.size()+1
			athletes.append(p)
	if lineups[0].is_empty() or lineups[1].is_empty():
		lineups=[range(6),range(6,12)]
	render("Start")

func persist() -> void:
	StorySession.save_match_preference("exhibition",{"athletes":athletes,"lineups":lineups,"sizes":sizes,"venue":venue,"crowd":attendance,"points":points,"controller":controller,"colors":StorySession.kit_colors})
	StorySession.save_match_preference("ball_brand",brand)

func launch() -> void:
	StorySession.career_scrimmage=false
	persist()
	StorySession.offline_controller=controller
	StorySession.offline_size=sizes[0]
	StorySession.offline_away_size=sizes[1]
	StorySession.offline_roster.clear()
	for team in 2:
		for i in int(sizes[team]): StorySession.offline_roster.append(athletes[lineups[team][i]].duplicate(true))
	start_match.call()

func action(parent: Container, title: String, fn: Callable, id := "") -> Button:
	var b:=Button.new()
	b.text=title
	if not id.is_empty(): b.name=id
	b.custom_minimum_size.y=35
	b.pressed.connect(fn)
	parent.add_child(b)
	return b

func strip(parent: Container) -> HBoxContainer:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	parent.add_child(row)
	return row

func txt(parent: Container, caption: String, size_: int) -> Label:
	var label:=Label.new()
	label.text=caption
	label.add_theme_font_size_override("font_size",size_)
	parent.add_child(label)
	return label

func render(focus_id: String) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var tabs:=strip(self)
	for i in PAGES.size():
		var tab:=action(tabs,PAGES[i],set_page.bind(i),"Tab%d"%i)
		tab.toggle_mode=true
		tab.set_pressed_no_signal(i==section)
		tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	match section:
		0:
			if slot<0: team_board()
			else: player_board()
		1: equipment_board()
		2: venue_board()
		3: rules_board()
	var footer:=strip(self)
	var start:=action(footer,"Start match   ·   %dv%d   ·   First to %d"%[sizes[0],sizes[1],points],launch,"Start")
	start.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var random_button:=action(footer,"Random",randomize_selection,"Random")
	random_button.add_theme_constant_override("icon_max_width",30)
	if not Xbox.keyboard_prompts(): random_button.icon=Xbox.glyph(JOY_BUTTON_Y)
	action(footer,"Back",go_back)
	var focus_target:=find_child(focus_id,true,false) as Control
	if focus_target: focus_target.grab_focus()
	MenuPresentation.reveal(self)

func set_page(index: int) -> void:
	section=posmod(index,PAGES.size())
	slot=-1
	render("Tab%d"%section)

func go_back() -> void:
	if slot>=0:
		var target:="Player%d_%d"%[side,slot]
		slot=-1
		render(target)
	else: back.call()

func stepper(parent: Container, caption: String, value: String, fn: Callable, id: String) -> void:
	var row:=strip(parent)
	var key:=txt(row,caption,17)
	key.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	action(row,"‹",fn.bind(-1),id+"Prev")
	var readout:=txt(row,value,18)
	readout.custom_minimum_size.x=70
	readout.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	action(row,"›",fn.bind(1),id+"Next")

func team_board() -> void:
	var board:=strip(self)
	for idx in 2:
		var panel:=PanelContainer.new()
		panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel",MenuPresentation.box(Color("101f2af4"),StorySession.kit_colors[idx],5))
		board.add_child(panel)
		var col:=VBoxContainer.new()
		panel.add_child(col)
		MenuPresentation.section_label(col,"Home" if idx==0 else "Away")
		stepper(col,"Squad size",str(sizes[idx]),change_size.bind(idx),"Count%d"%idx)
		var cards:=strip(col)
		for i in int(sizes[idx]):
			var profile: Dictionary=athletes[lineups[idx][i]]
			var card:=athlete_card(cards,profile,idx,i,false)
			card.name="Player%d_%d"%[idx,i]
			card.focus_entered.connect(select_slot.bind(idx,i))
			card.mouse_entered.connect(select_slot.bind(idx,i))
			card.pressed.connect(open_player.bind(idx,i))
		var scouting:=txt(col,"",15)
		scouting_labels[idx]=scouting
		scouting.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		show_ratings(idx,0)
		var kit:=action(col,"Change kit",cycle_kit.bind(idx),"Kit%d"%idx)
		kit.self_modulate=StorySession.kit_colors[idx].lightened(.40)
	MenuPresentation.section_label(self,"Controller assignment")
	var sides:=strip(self)
	for choice in [0,-1,1]:
		var btn:=action(sides,{0:"Home",-1:"Middle  ·  CPU vs CPU",1:"Away"}[choice],set_side.bind(choice),"Controller%d"%(choice+1))
		btn.toggle_mode=true
		btn.set_pressed_no_signal(choice==controller)
		if choice==controller:
			btn.icon=preload("res://assets/menu/controller.svg")
			btn.add_theme_constant_override("icon_max_width",32)
		btn.gui_input.connect(func(event:InputEvent):
			if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
				var order:=[0,-1,1]
				var step:=1 if event.is_action_pressed("ui_right") else -1
				var target:int=order[clampi(order.find(choice)+step,0,2)]
				btn.accept_event()
				set_side(target))
		btn.size_flags_horizontal=Control.SIZE_EXPAND_FILL

func select_slot(idx:int, member:int) -> void:
	side=idx
	picker=member
	show_ratings(idx,member)

func show_ratings(idx:int,member:int) -> void:
	if not is_instance_valid(scouting_labels[idx]): return
	var p:Dictionary=athletes[lineups[idx][member]]
	scouting_labels[idx].text="%s    ·    %d OFF    %d DEF"%[p.name,average(p,OFFENSE),average(p,DEFENSE)]

func set_side(choice:int) -> void:
	controller=choice
	persist()
	render("Controller%d"%(choice+1))

func change_size(direction:int,idx:int) -> void:
	sizes[idx]=clampi(sizes[idx]+direction,2,6)
	picker=-1
	persist()
	render("Count%d%s"%[idx,"Next" if direction>0 else "Prev"])

func cycle_kit(idx:int) -> void:
	StorySession.kit_colors[idx]=COLORS[(COLORS.find(StorySession.kit_colors[idx])+1)%COLORS.size()]
	persist()
	render("Kit%d"%idx)

static func average(profile:Dictionary, fields:Array) -> int:
	var sum:=0.
	for field in fields: sum+=float(profile.get(field,65))
	return roundi(sum/fields.size())

func athlete_card(parent: Container, profile: Dictionary, idx:int, member:int, large:bool) -> Button:
	var b:=Button.new()
	b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	b.custom_minimum_size=Vector2(45,211 if large else 194)
	b.tooltip_text="%s   ·   Offense %d   ·   Defense %d"%[profile.name,average(profile,OFFENSE),average(profile,DEFENSE)]
	parent.add_child(b)
	var col:=VBoxContainer.new()
	b.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left=3
	col.offset_right=-3
	col.offset_top=5
	col.offset_bottom=-5
	col.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var number:=txt(col,"%d OVR"%average(profile,Profile.RATINGS),14)
	number.modulate=Color("f5cc78")
	number.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var art:=TextureRect.new()
	art.texture=SchoolHeadshots.request(profile,idx*6+member,StorySession.kit_colors[idx],true)
	art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size_flags_vertical=Control.SIZE_EXPAND_FILL
	art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	col.add_child(art)
	if not large and changed_player==Vector2i(idx,member):
		blend_art(art)
		changed_player=Vector2i(-1,-1)
	var name_label:=txt(col,str(profile.name) if large or sizes[idx]<=3 else str(profile.name).get_slice(" ",1),16)
	name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	for node in col.get_children(): node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return b

func open_player(idx:int,member:int) -> void:
	side=idx
	slot=member
	picker=member
	sheet=int(lineups[side][slot])/6
	render("Candidate%d"%lineups[side][slot])

func player_board() -> void:
	var chosen:Dictionary=athletes[lineups[side][slot]]
	MenuPresentation.section_label(self,"%s   /   Player %d"%["Home" if side==0 else "Away",slot+1])
	var inches:=roundi(chosen.height_cm/2.54)
	txt(self,"%s     %d OVR     %d OFF     %d DEF"%[chosen.name,average(chosen,Profile.RATINGS),average(chosen,OFFENSE),average(chosen,DEFENSE)],23)
	stepper(self,"Player height","%d′ %d″"%[inches/12,inches%12],change_height,"Height")
	var row:=strip(self)
	for i in range(sheet*6,mini(sheet*6+6,athletes.size())):
		var card:=athlete_card(row,athletes[i],side,slot,true)
		card.name="Candidate%d"%i
		card.toggle_mode=true
		card.set_pressed_no_signal(i==lineups[side][slot])
		card.pressed.connect(pick_player.bind(i))
	stepper(self,"Roster page","%d / %d"%[sheet+1,ceili(athletes.size()/6.)],change_sheet,"Sheet")

func change_sheet(direction:int) -> void:
	sheet=posmod(sheet+direction,ceili(athletes.size()/6.))
	render("SheetNext" if direction>0 else "SheetPrev")

func change_height(direction:int) -> void:
	var p:Dictionary=athletes[lineups[side][slot]]
	p.height_cm=clampi(roundi(p.height_cm/2.54)+direction,60,84)*2.54
	persist()
	render("HeightNext" if direction>0 else "HeightPrev")

func pick_player(id:int) -> void:
	var old:int=lineups[side][slot]
	previous_art=SchoolHeadshots.request(athletes[old],side*6+slot,StorySession.kit_colors[side],true)
	changed_player=Vector2i(side,slot)
	for team in 2:
		var other:int=lineups[team].find(id)
		if other>=0: lineups[team][other]=old
	lineups[side][slot]=id
	persist()
	go_back()

func picture_card(parent:Container, title:String, file:String, selected:bool, fn:Callable, id:String) -> void:
	var b:=action(parent,"",fn,id)
	b.toggle_mode=true
	b.set_pressed_no_signal(selected)
	b.custom_minimum_size.y=187
	b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var col:=VBoxContainer.new()
	b.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left=6
	col.offset_right=-6
	col.offset_top=6
	col.offset_bottom=-6
	col.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var pic:=TextureRect.new()
	pic.texture=load(file)
	if selected: blend_art(pic)
	pic.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_vertical=Control.SIZE_EXPAND_FILL
	pic.mouse_filter=Control.MOUSE_FILTER_IGNORE
	col.add_child(pic)
	var name_label:=txt(col,title,18)
	name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter=Control.MOUSE_FILTER_IGNORE

func blend_art(pic:TextureRect) -> void:
	if not previous_art: return
	if previous_art != pic.texture:
		var old:=TextureRect.new()
		old.texture=previous_art
		old.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		old.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		old.mouse_filter=Control.MOUSE_FILTER_IGNORE
		pic.add_child(old)
		old.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var fade:=old.create_tween()
		fade.tween_property(old,"modulate:a",0.,.24)
		fade.tween_callback(old.queue_free)
	previous_art=null

func equipment_board() -> void:
	MenuPresentation.section_label(self,"Match ball")
	var grid:=strip(self)
	for key in Ball.BALL_PALETTES:
		picture_card(grid,key,"res://assets/menu/match/ball-%s.png"%key.to_lower(),key==brand,pick_ball.bind(key),key)

func pick_ball(key:String) -> void:
	previous_art=load("res://assets/menu/match/ball-%s.png"%brand.to_lower())
	brand=key
	persist()
	render(brand)

func venue_board() -> void:
	MenuPresentation.section_label(self,"Venue")
	var grid:=strip(self)
	for i in Venue.NAMES.size():
		picture_card(grid,Venue.NAMES[i],"res://assets/menu/match/venue%d.jpg"%i,venue==i,pick_venue.bind(i),"Venue%d"%i)
	stepper(self,"Spectators",str(attendance),change_crowd,"Crowd")

func pick_venue(i:int) -> void:
	previous_art=load("res://assets/menu/match/venue%d.jpg"%venue)
	venue=i
	persist()
	render("Venue%d"%i)

func change_crowd(direction:int) -> void:
	attendance=CROWDS[posmod(CROWDS.find(attendance)+direction,CROWDS.size())]
	persist()
	render("CrowdNext" if direction>0 else "CrowdPrev")

func rules_board() -> void:
	stepper(self,"Points to win",str(points),change_points,"Points")
	txt(self,"Win by two",16)

func change_points(direction:int) -> void:
	points=POINTS[posmod(POINTS.find(points)+direction,POINTS.size())]
	persist()
	render("PointsNext" if direction>0 else "PointsPrev")

func randomize_selection() -> void:
	match section:
		0:
			if slot>=0: pick_player(randi_range(0,athletes.size()-1))
			elif picker>=0 and picker<sizes[side]:
				slot=picker
				pick_player(randi_range(0,athletes.size()-1))
			else:
				var ids:=range(athletes.size())
				ids.shuffle()
				lineups=[ids.slice(0,6),ids.slice(6,12)]
				persist()
				render("Random")
		1: pick_ball(Ball.BALL_PALETTES.keys().pick_random())
		2: pick_venue(randi_range(0,Venue.NAMES.size()-1))
		3:
			points=POINTS.pick_random()
			persist()
			render("Random")
