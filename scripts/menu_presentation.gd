extends Node

const BACKDROP = preload("res://assets/menu/court_identity.gdshader")
const PARENTS := {"Play":"Home","Offline":"Play","Match setup":"Play","Settings":"Home","Career":"Home","Load career":"Career","Create player":"Home","Training camp":"Home","Iteration Lab":"Settings"}
var return_page := "Home"
var music := AudioStreamPlayer.new()
var navigation := AudioStreamPlayer.new()
var current_help: PanelContainer
var reel_view := SubViewport.new()
var reel := VideoStreamPlayer.new()
var reel_surfaces := 0
var highlights := preload("res://scripts/menu_highlights.gd").new()
var last_click := -100
var music_enabled := true
var active_tweens := {}
var skin := Theme.new()
var overlay := CanvasLayer.new()
var ribbon := Polygon2D.new()
var wipe_tween: Tween

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	refresh_menu_buttons()
	build_theme()
	reel_view.size=Vector2i(1280,720)
	reel_view.disable_3d=true
	reel_view.transparent_bg=true
	reel_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(reel_view)
	reel.expand=true
	reel.loop=false
	reel.volume_db=-80.
	reel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	reel_view.add_child(reel)
	add_child(highlights)
	highlights.configure(reel)
	reel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.theme=skin
	overlay.layer = 20
	add_child(overlay)
	overlay.add_child(ribbon)
	ribbon.color = Color("6df3ceaa")
	ribbon.hide()
	add_child(music)
	music.stream = preload("res://assets/menu/menu_theme.ogg")
	music.stream.loop = true
	add_child(navigation)
	navigation.stream=preload("res://assets/menu/navigation.wav")
	navigation.max_polyphony = 3
	set_navigation_level(StorySession.game_options.get_value("audio","menu_clicks",85))
	get_viewport().gui_focus_changed.connect(menu_click)
	get_tree().node_added.connect(watch_control)
	set_music_level(StorySession.game_options.get_value("audio","music_level",65))
	music_enabled = StorySession.game_options.get_value("audio","menu_music",true)
	get_tree().scene_changed.connect(scene_entered)

func watch_control(node: Node) -> void:
	if node is Control and not node.get_parent() is Control and node.theme==null:
		node.theme=skin
	if node is BaseButton:
		node.mouse_entered.connect(menu_click.bind(node))
		node.button_down.connect(menu_click.bind(node))

func menu_click(control: Control) -> void:
	if not control or not control.is_visible_in_tree(): return
	var now := Time.get_ticks_msec()
	if now-last_click<45: return
	last_click=now
	navigation.play()

func set_navigation_level(percent: float) -> void:
	navigation.volume_db = linear_to_db(percent/100.)

func set_music_level(percent: float) -> void:
	music.volume_db = -10.0 + linear_to_db(percent/100.)

func stat_help(control: Control,heading_control: Control,title: String,description: Variant,show_perks:=true) -> void:
	var card := PanelContainer.new()
	card.hide()
	card.z_index=100
	card.top_level=true
	card.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var style := box(Color("102330"),Color("73e1d2"),1)
	for edge in [SIDE_TOP,SIDE_BOTTOM,SIDE_LEFT,SIDE_RIGHT]: style.set_content_margin(edge,14.)
	card.add_theme_stylebox_override("panel",style)
	overlay.add_child(card)
	control.tree_exiting.connect(card.queue_free,CONNECT_ONE_SHOT)
	control.visibility_changed.connect(card.hide)
	var body := Label.new()
	body.mouse_filter=Control.MOUSE_FILTER_IGNORE
	body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x=250
	var refresh:=func():
		var copy:String=description.call() if description is Callable else str(description)
		body.text=title+"\n"+copy
		if show_perks: body.text+="\n\nPERKS    /    "+preload("res://scripts/player_profile.gd").perk_text(title)
	refresh.call()
	if control is Range: control.value_changed.connect(func(_v): refresh.call_deferred())
	card.add_child(body)
	var show_help := func():
		refresh.call()
		if is_instance_valid(current_help): current_help.hide()
		current_help=card
		card.reset_size()
		var bounds := control.get_viewport_rect().size-card.size-Vector2(8,8)
		card.global_position=(control.global_position+Vector2(control.size.x+12,-12)).clamp(Vector2(8,8),bounds)
		card.show()
	control.item_rect_changed.connect(func():
		if card.visible and current_help==card: show_help.call_deferred())
	control.focus_entered.connect(show_help)
	control.focus_exited.connect(card.hide)
	if heading_control is Label: heading_control.mouse_filter=Control.MOUSE_FILTER_PASS
	for target in [control,heading_control]:
		if target==heading_control and control==heading_control and control.mouse_entered.is_connected(show_help): continue
		target.mouse_entered.connect(show_help)
		target.mouse_exited.connect(card.hide)

func refresh_menu_buttons() -> void:
	for binding in [["ui_accept",JOY_BUTTON_A],["ui_cancel",JOY_BUTTON_B]]:
		for previous in InputMap.action_get_events(binding[0]):
			if previous is InputEventJoypadButton: InputMap.action_erase_event(binding[0],previous)
		bind_menu_button(binding[0],binding[1])

func bind_menu_button(action: StringName, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	if not InputMap.action_has_event(action,event):
		InputMap.action_add_event(action,event)

func scene_entered() -> void:
	var current := get_tree().current_scene
	if current and current.is_in_group("gameplay_pause"):
		var pause_layer := CanvasLayer.new()
		pause_layer.layer = 15
		current.add_child(pause_layer)
		preload("res://scripts/tryout_pause.gd").new().configure(current,pause_layer)
	var scene := current as Control
	if scene:
		scene.theme = skin
		reveal(scene)
		sweep()
		if scene.scene_file_path in ["res://scenes/main.tscn","res://scenes/story.tscn","res://scenes/create.tscn"]:
			set_music(true)

func set_music(in_menu: bool) -> void:
	if in_menu and music_enabled and music.stream:
		if not music.playing: music.play()
	else:
		music.stop()

func audio_options(host: Container) -> void:
	var feedback:=CheckButton.new()
	feedback.text="Coach feedback"
	feedback.button_pressed=StorySession.game_options.get_value("presentation","coach_feedback",true)
	feedback.toggled.connect(func(enabled):
		StorySession.game_options.set_value("presentation","coach_feedback",enabled)
		StorySession.save_options())
	host.add_child(feedback)
	var mute := CheckButton.new()
	mute.text="Mute game audio"
	mute.button_pressed=AudioServer.is_bus_mute(0)
	mute.toggled.connect(StorySession.set_game_muted)
	host.add_child(mute)
	var soundtrack := CheckButton.new()
	soundtrack.text="Menu soundtrack"
	soundtrack.button_pressed=music_enabled
	soundtrack.toggled.connect(func(enabled):
		music_enabled=enabled
		StorySession.game_options.set_value("audio","menu_music",enabled)
		StorySession.save_options()
		if not enabled or reel_surfaces>0: set_music(true))
	host.add_child(soundtrack)
	var test := Button.new()
	test.text="Test spike sound"
	test.pressed.connect(StorySession.play_hand_contact)
	host.add_child(test)

func attach_highlights(parent: Control) -> void:
	var film := TextureRect.new()
	film.add_to_group("menu_reel_surface")
	film.texture=reel_view.get_texture()
	film.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	film.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	film.mouse_filter=Control.MOUSE_FILTER_IGNORE
	film.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(film)
	film.visibility_changed.connect(func():
		var visible_now:=film.is_visible_in_tree()
		if visible_now==bool(film.get_meta("counted",true)): return
		film.set_meta("counted",visible_now)
		if visible_now:
			reel_surfaces+=1
			reel_view.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
			highlights.activate(true)
		else: release_highlights())
	reel_surfaces+=1
	if reel_surfaces==1:
		reel_view.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
		highlights.activate(true)
	film.tree_exiting.connect(func():
		if film.get_meta("counted",true): release_highlights(),CONNECT_ONE_SHOT)

func release_highlights() -> void:
	reel_surfaces -= 1
	if reel_surfaces == 0:
		highlights.activate(false)
		reel_view.render_target_update_mode = SubViewport.UPDATE_DISABLED

static func color_chip(color:Color) -> Texture2D:
	var sample:=Gradient.new()
	sample.colors=PackedColorArray([color,color])
	var chip:=GradientTexture2D.new()
	chip.gradient=sample
	chip.width=22
	chip.height=22
	return chip

func backdrop(parent: Control, hero: bool) -> void:
	parent.theme = skin
	if hero:
		var cover := TextureRect.new()
		cover.texture=preload("res://assets/menu/falcons_contact.jpg") if parent==loading_screen else preload("res://assets/menu/falcons_spike_windup.jpg")
		cover.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		cover.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
		cover.mouse_filter=Control.MOUSE_FILTER_IGNORE
		cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		parent.add_child(cover)
		attach_highlights(parent)
		var shade := ColorRect.new()
		shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var grade := ShaderMaterial.new()
		grade.shader=preload("res://assets/menu/court_scrim.gdshader")
		shade.material=grade
		parent.add_child(shade)
		return
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = BACKDROP
	material.set_shader_parameter("hero",hero)
	rect.material = material
	parent.add_child(rect)
	rect.resized.connect(func(): material.set_shader_parameter("viewport_size",rect.size))
	material.set_shader_parameter("viewport_size",rect.size)

func mount_menu(parent: Control, column: VBoxContainer) -> void:
	backdrop(parent,true)
	var center := CenterContainer.new()
	center.anchor_right = 0.56
	center.anchor_bottom = 1
	center.offset_left = 24
	center.offset_right = -12
	center.name="MenuColumn"
	center.offset_bottom=-40
	parent.add_child(center)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	center.add_child(scroll)
	var fit := func():
		scroll.custom_minimum_size = Vector2(minf(float(center.get_meta("max_width",510)),center.size.x-20),maxf(180,center.size.y-34))
	center.resized.connect(fit)
	fit.call_deferred()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var align := MarginContainer.new()
	align.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	align.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.add_child(align)
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation",7)
	align.add_child(column)
	var strip := PanelContainer.new()
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top=-42
	strip.mouse_filter=Control.MOUSE_FILTER_IGNORE
	strip.add_theme_stylebox_override("panel",box(Color("0a1623ed"),Color("63debd"),0))
	parent.add_child(strip)
	var prompts := HBoxContainer.new()
	prompts.add_theme_constant_override("separation",20)
	prompts.name="MenuPrompts"
	strip.add_child(prompts)
	column.set_meta("prompts",prompts)
	column.set_meta("dock",center)
	column.set_meta("scroll",scroll)

func section_label(host: Container, caption: String) -> Label:
	var label := Label.new()
	label.text=caption.to_upper()
	label.add_theme_font_size_override("font_size",14)
	label.add_theme_color_override("font_color",Color("76e4ca"))
	host.add_child(label)
	return label

func heading(column: VBoxContainer, route: String, title: String) -> void:
	var trail := PackedStringArray()
	var parent: String = PARENTS.get(route,"")
	while not parent.is_empty():
		trail.insert(0,parent.to_upper())
		parent = PARENTS.get(parent,"")
	if column.has_meta("dock"):
		var dock: Control=column.get_meta("dock")
		var wide := route in ["Match setup","Settings"]
		dock.set_meta("max_width",1180 if wide else 510)
		dock.anchor_right=.96 if wide else .56
		var scroll: ScrollContainer=column.get_meta("scroll")
		scroll.set_deferred("scroll_vertical",0)
		var prompts: HBoxContainer=column.get_meta("prompts")
		var xbox=preload("res://scripts/xbox_controls.gd")
		if xbox.keyboard_prompts():
			for item in prompts.get_children():
				prompts.remove_child(item)
				item.queue_free()
			var keys:=Label.new()
			keys.text="Enter   Select" if route=="Home" else "Enter   Select       Esc   Back"
			prompts.add_child(keys)
		else:
			var actions := [["A","Select"]]
			if route!="Home": actions.append(["B","Back"])
			xbox.prompts(prompts,actions)
	var overline := Label.new()
	overline.text = "ANDRE FOREMAN'S" if route=="Home" else "   /   ".join(trail) if not trail.is_empty() else route.to_upper()
	overline.add_theme_font_size_override("font_size",14)
	overline.add_theme_color_override("font_color",Color("6de4d1"))
	column.add_child(overline)
	var label := Label.new()
	label.text = "VOLLEYBALL" if route=="Home" else title
	label.add_theme_font_override("font",skin.get_font("font","Button"))
	label.add_theme_font_size_override("font_size",68 if route=="Home" else 42)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)
	reveal(column)
	sweep()

func sweep(reverse := false) -> void:
	var area := get_viewport().get_visible_rect().size
	var lean := area.y*0.23
	ribbon.polygon = PackedVector2Array([Vector2(lean,0),Vector2(lean+8,0),Vector2(8,area.y),Vector2(0,area.y)])
	if wipe_tween: wipe_tween.kill()
	var start := -lean-10
	var finish := area.x+10
	ribbon.position.x = finish if reverse else start
	ribbon.show()
	wipe_tween = create_tween()
	wipe_tween.tween_property(ribbon,"position:x",start if reverse else finish,0.29).set_trans(Tween.TRANS_SINE)
	wipe_tween.tween_callback(ribbon.hide)

func reveal(item: Control) -> void:
	var id := item.get_instance_id()
	if active_tweens.has(id): active_tweens[id].kill()
	item.modulate.a = 0.30
	var tween := item.create_tween()
	active_tweens[id] = tween
	tween.tween_property(item,"modulate:a",1.,0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): active_tweens.erase(id))
	if not item.has_meta("menu_cleanup"):
		item.set_meta("menu_cleanup",true)
		item.tree_exiting.connect(func(): active_tweens.erase(id))

func box(fill: Color, edge: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.border_width_left = width
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style

func wallet(host: Container,amount: int) -> Label:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel",box(Color("172c31"),Color("f3bb63"),4))
	host.add_child(plate)
	var row := HBoxContainer.new()
	plate.add_child(row)
	var coin := Label.new()
	coin.text="VP"
	coin.add_theme_font_size_override("font_size",22)
	coin.modulate=Color("ffcc78")
	row.add_child(coin)
	var caption := Label.new()
	caption.text="Volleyball Points"
	caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	var balance := Label.new()
	balance.text=str(amount)
	balance.add_theme_font_size_override("font_size",24)
	row.add_child(balance)
	return balance

func rating_bar(host: Container,slider: Range,value := 0) -> void:
	var meter := Control.new()
	meter.custom_minimum_size.y=8
	meter.mouse_filter=Control.MOUSE_FILTER_IGNORE
	host.add_child(meter)
	meter.draw.connect(func():
		var amount: float=slider.value if is_instance_valid(slider) else value
		for i in 20:
			var unit := meter.size.x/20.
			var track := Rect2(i*unit,0,maxf(1.,unit-2.),7.)
			meter.draw_rect(track,Color("29404c"))
			track.size.x*=clampf((amount-i*5.)/5.,0.,1.)
			meter.draw_rect(track,Color("66d9bf").lerp(Color("ffd185"),i/19.)))
	if slider: slider.value_changed.connect(func(_v): meter.queue_redraw())

func build_theme() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift","Segoe UI","sans-serif"])
	skin.default_font = font
	skin.default_font_size = 17
	var headline := SystemFont.new()
	headline.font_names=PackedStringArray(["Bahnschrift SemiCondensed","Bahnschrift","Segoe UI"])
	headline.font_weight=700
	skin.set_font("font","Button",headline)
	skin.set_stylebox("panel","PanelContainer",box(Color("10202cf5"),Color("43606d"),2))
	skin.set_stylebox("panel","Panel",box(Color("0d1925f5"),Color("43606d"),2))
	skin.set_stylebox("background","ProgressBar",box(Color("263742"),Color("344650"),0))
	skin.set_stylebox("fill","ProgressBar",box(Color("4cc8b0"),Color("8bead3"),0))
	for state in ["grabber_area","grabber_area_highlight"]:
		skin.set_stylebox(state,"HSlider",box(Color("4cc8b0"),Color("4cc8b0"),0))
	skin.set_stylebox("slider","HSlider",box(Color("273a46"),Color("273a46"),0))
	skin.set_color("font_focus_color","Button",Color("ffcf82"))
	skin.set_color("font_hover_color","Button",Color("ffcf82"))
	for kind in ["Button","OptionButton","CheckButton","MenuButton","ColorPickerButton"]:
		for state in ["normal","hover","pressed","disabled"]:
			var colors: Array = {"normal":["172e40","375268"],"hover":["24515a","61e4ce"],"pressed":["24655e","ffd285"],"disabled":["15212d","2b3843"]}[state]
			skin.set_stylebox(state,kind,box(Color(colors[0]),Color(colors[1]),3))
		var focus := StyleBoxFlat.new()
		focus.draw_center = false
		focus.border_color = Color("7cf4d8")
		focus.set_border_width_all(2)
		skin.set_stylebox("focus",kind,focus)
	skin.set_stylebox("panel","PopupMenu",box(Color("142c3d"),Color("59d7c4"),2))
	skin.set_stylebox("normal","LineEdit",box(Color("102331"),Color("43727a"),2))

# Historical sources: FIVB's indoor and beach volleyball histories.
const FACTS := [
	"William Morgan invented volleyball in 1895 at a YMCA in Holyoke, Massachusetts.",
	"Before it was called volleyball, the game was called Mintonette.",
	"Canada was the first country outside the United States to take up volleyball.",
	"Japan won the first Olympic women's volleyball gold on home soil in Tokyo in 1964.",
	"Karch Kiraly was the first player to win Olympic gold both indoors and on the beach.",
	"Jackie Silva and Sandra Pires won the first Olympic women's beach volleyball title in 1996.",
	"At the London Olympics, beach volleyball was played on Horse Guards Parade.",
	"At the Paris 2024 Olympics, beach volleyball players competed beside the Eiffel Tower.",
	"Early volleyball teams could field more than six players. The six-player limit arrived in 1918.",
	"The three-contact limit dates to 1922.",
	"An early volleyball had a leather cover wrapped around a rubber inner tube.",
	"The YMCA included volleyball rules in its North American athletic handbook in 1897.",
	"In 1952 the U.S. association voted to write volleyball as one word.",
	"Representatives from 14 countries founded the international volleyball federation in Paris in 1947.",
	"The first men's volleyball world championship took place in 1949.",
	"The first women's volleyball world championship followed in 1952.",
	"The libero made its world championship debut in 1998.",
	"Yellow, blue and white volleyballs appeared at the 1998 World Championships in Japan.",
	"Volleyball appeared as a demonstration in Paris in 1924, forty years before its Olympic medal debut.",
	"The first Snow Volleyball World Tour launched in 2019."
]
const FACT_ART := {FACTS[7]:"res://assets/menu/paris_beach_court.svg"}
var catalog := FACTS + preload("res://scripts/olympic_facts.gd").FACTS + preload("res://scripts/returning_olympians.gd").FACTS
var fact_order := []
var last_fact := ""
var fact_history := ConfigFile.new()
var facts_loaded := false

func next_fact() -> String:
	if not facts_loaded:
		facts_loaded=true
		if fact_history.load("user://loading_facts.cfg")==OK:
			last_fact=fact_history.get_value("facts","last","")
			if fact_history.get_value("facts","size",0)==catalog.size(): fact_order=fact_history.get_value("facts","indices",[])
	if fact_order.is_empty():
		fact_order = range(catalog.size())
		fact_order.shuffle()
		if catalog[fact_order.back()] == last_fact: fact_order.reverse()
	last_fact = catalog[fact_order.pop_back()]
	fact_history.set_value("facts","last",last_fact)
	fact_history.set_value("facts","size",catalog.size())
	fact_history.set_value("facts","indices",fact_order)
	fact_history.save("user://loading_facts.cfg")
	return last_fact

var loading_screen: ColorRect
var loading_detail: Label
var loading_progress: ProgressBar
var fact_started_ms := 0
var dismiss_fact := false

func show_loading(destination: String, court_fade:=false) -> void:
	fact_started_ms = Time.get_ticks_msec()
	dismiss_fact = false
	loading_screen = ColorRect.new()
	loading_screen.modulate.a = 0.
	loading_screen.color = Color("112433")
	loading_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.add_child(loading_screen)
	loading_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if court_fade:
		loading_screen.color=Color.BLACK
		return
	backdrop(loading_screen,true)
	var center := CenterContainer.new()
	loading_screen.add_child(center)
	center.anchor_right=.55
	center.anchor_bottom=1.
	center.offset_left=24
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	center.add_child(column)
	section_label(column,"Up next")
	var title := Label.new()
	title.text = destination
	title.add_theme_font_size_override("font_size",48)
	column.add_child(title)
	loading_detail = Label.new()
	loading_detail.text = "Loading…"
	loading_detail.add_theme_color_override("font_color",Color("73e1d2"))
	column.add_child(loading_detail)
	loading_progress=ProgressBar.new()
	loading_progress.show_percentage=false
	loading_progress.indeterminate=true
	loading_progress.custom_minimum_size.y=5
	column.add_child(loading_progress)
	var fact := Label.new()
	fact.text = next_fact()
	if FACT_ART.has(fact.text):
		var illustration := TextureRect.new()
		illustration.texture = load(FACT_ART[fact.text])
		illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		illustration.custom_minimum_size.y = clampf(center.size.y*0.24,70,190)
		column.add_child(illustration)
	fact.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fact.add_theme_font_size_override("font_size",21)
	column.add_child(fact)
	var fit := func(): fact.custom_minimum_size.x = clampf(center.size.x - 56,120,580)
	center.resized.connect(fit)
	fit.call()

var repeat_direction := 0
var repeat_at := 0

func _process(_delta: float) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	var direction := 0
	if focus and focus.is_visible_in_tree() and not is_instance_valid(loading_screen):
		for device in Input.get_connected_joypads():
			var axis := Input.get_joy_axis(device,JOY_AXIS_LEFT_Y)
			if Input.is_joy_button_pressed(device,JOY_BUTTON_DPAD_DOWN) or axis>.65: direction=1
			elif Input.is_joy_button_pressed(device,JOY_BUTTON_DPAD_UP) or axis<-.65: direction=-1
			if direction!=0: break
	var now := Time.get_ticks_msec()
	if direction!=repeat_direction:
		repeat_direction=direction
		repeat_at=now+360
	elif direction!=0 and now>=repeat_at:
		repeat_at=now+125
		var event := InputEventAction.new()
		event.action="ui_down" if direction>0 else "ui_up"
		event.pressed=true
		get_viewport().push_input(event)
		event.pressed=false
		get_viewport().push_input(event)

func _input(event: InputEvent) -> void:
	if is_instance_valid(loading_screen):
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"): dismiss_fact = true
		get_viewport().set_input_as_handled()

func painted() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func fade_loading(alpha: float, seconds: float) -> void:
	var fade := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	fade.tween_property(loading_screen,"modulate:a",alpha,seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade.finished

func close_loading(read_fact := true) -> void:
	while read_fact and not dismiss_fact and Time.get_ticks_msec() - fact_started_ms < 300:
		await get_tree().process_frame
	await fade_loading(0.,.20)
	loading_screen.hide()
	loading_screen.queue_free()
	loading_screen = null

func load_stage(destination: String, build: Callable) -> void:
	if is_instance_valid(loading_screen): return
	show_loading(destination)
	await fade_loading(1.,.18)
	await painted()
	if build.is_valid(): build.call()
	await painted()
	close_loading()

func load_scene(path: String) -> void:
	if is_instance_valid(loading_screen): return
	if not CareerSession.practice_stage.is_empty():
		var lesson_path:="res://scenes/"+str(CareerSession.LESSON_SCENES[CareerSession.practice_stage])+".tscn"
		if path!=lesson_path: path="res://scenes/story.tscn"
	var key := path.get_file().get_basename()
	var names := {"offline_match":"Match court","main":"Main menu","story":"My Career","drills":"Training camp","create":"Create player","setter_tryout":"Setter tryout","story_animations":"Court session"}
	var current:=get_tree().current_scene
	var chapters:Array=CareerSession.LESSON_SCENES.values()
	var court_fade:=current!=null and current.scene_file_path.get_file().get_basename() in chapters and (key in chapters or key=="offline_match")
	show_loading(names.get(key,key.capitalize()),court_fade)
	var error := ResourceLoader.load_threaded_request(path,"PackedScene")
	await fade_loading(1.,.18)
	await painted()
	if error == OK:
		var progress := []
		var status := ResourceLoader.load_threaded_get_status(path,progress)
		while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if progress.size() and not court_fade:
				loading_progress.indeterminate=false
				loading_progress.value=progress[0]*100.
			await get_tree().process_frame
			status = ResourceLoader.load_threaded_get_status(path,progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			if not court_fade: loading_detail.text = "Preparing court…" if key in ["setter_tryout","story_animations","court"] else "Opening menu…"
			await painted()
			error = get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(path))
			if error == OK:
				await get_tree().scene_changed
				await painted()
		else: error = ERR_CANT_OPEN
	if error != OK:
		push_error("Could not open "+path+": "+error_string(error))
		if not court_fade: loading_detail.text = "Could not open this destination"
		await get_tree().create_timer(1.5).timeout
	close_loading(not court_fade and key not in ["offline_match","career_setting_lesson","career_hitting_lesson"])
