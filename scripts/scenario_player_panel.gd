extends PanelContainer

const Profile = preload("res://scripts/player_profile.gd")
signal changed(side:int, identity:int, field:String, value:Variant)

var side := -1
var identity := -1
var heading := Label.new()
var subtitle := Label.new()
var tabs := TabContainer.new()
var controls := {}
var effective_labels := {}
var hand := OptionButton.new()
var message := Label.new()
var updating := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	offset_left=-328
	offset_right=-16
	offset_top=68
	offset_bottom=-88
	add_theme_stylebox_override("panel",MenuPresentation.box(Color("101c29f5"),Color("61cfb6"),2))
	var column:=VBoxContainer.new()
	add_child(column)
	var header:=HBoxContainer.new()
	column.add_child(header)
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_theme_font_size_override("font_size",20)
	header.add_child(heading)
	var close:=Button.new()
	close.text="Close"
	close.pressed.connect(hide)
	header.add_child(close)
	column.add_child(subtitle)
	column.add_child(tabs)
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var body:=make_tab("Body")
	add_number(body,"Height (in)","height_cm",60,84)
	add_number(body,"Vertical (in)","vertical_in",30,60)
	add_number(body,"Wingspan (in)","wingspan_in",48,96)
	for label:String in Profile.MEASUREMENTS:
		var spec:Array=Profile.MEASUREMENTS[label]
		add_number(body,label,spec[0],spec[1],spec[2],1. if spec[0]=="weight_lb" else .25)
	row_label(body,"Hitting hand")
	body.add_child(hand)
	hand.add_item("Right")
	hand.add_item("Left")
	hand.item_selected.connect(func(i:int): changed.emit(side,identity,"handedness",hand.get_item_text(i)))
	var skills:=make_tab("Skills")
	for field:String in Profile.RATINGS: add_number(skills,field,field,0,100)
	column.add_child(message)
	message.hide()
	hide()

func make_tab(caption:String) -> GridContainer:
	var scroll:=ScrollContainer.new()
	scroll.name=caption
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var grid:=GridContainer.new()
	grid.columns=2
	grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("v_separation",6)
	scroll.add_child(grid)
	return grid

func row_label(grid:GridContainer,caption:String) -> Label:
	var label:=Label.new()
	label.text=caption
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_child(label)
	return label

func add_number(grid:GridContainer,caption:String,field:String,low:float,high:float,step_size:=1.) -> void:
	var label:=row_label(grid,caption)
	label.tooltip_text=Profile.BUILD_HELP.get(field,Profile.RATING_HELP.get(field,""))
	if field in Profile.RATINGS: effective_labels[field]=label
	var spin:=SpinBox.new()
	spin.min_value=low
	spin.max_value=high
	spin.step=step_size
	spin.custom_minimum_size.x=78
	spin.get_line_edit().select_all_on_focus=true
	grid.add_child(spin)
	controls[field]=spin
	spin.value_changed.connect(func(v:float):
		if not updating: changed.emit(side,identity,field,v*2.54 if field=="height_cm" else v))

func display(team_side:int,athlete:int,number:int,profile:Dictionary) -> void:
	side=team_side
	identity=athlete
	heading.text="#%d  %s"%[number,profile.name]
	var height:=roundi(profile.height_cm/2.54)
	subtitle.text="%s  ·  %s  ·  %d′%d″"%[["Home","Away"][side],profile.position,floori(height/12.),height%12]
	updating=true
	var rules:=Profile.build_rules(profile)
	for field:String in controls:
		var spin:SpinBox=controls[field]
		if field=="vertical_in":
			spin.min_value=0 if profile.prestige.vertical_in else 30
			spin.max_value=60+2*int(profile.prestige.vertical_in)
		elif effective_labels.has(field):
			spin.max_value=100+2*int(profile.prestige.get(field,0))
			var effective:=Profile.effective_skill(profile,field,rules)
			effective_labels[field].text=field if effective==int(profile[field]) else "%s (%d in play)"%[field,effective]
		spin.set_value_no_signal(float(profile.height_cm)/2.54 if field=="height_cm" else float(profile[field]))
	hand.select(1 if profile.handedness=="Left" else 0)
	updating=false
	message.hide()
	show()
