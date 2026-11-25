extends Node

const BACKDROP = preload("res://assets/menu/court_identity.gdshader")
const PARENTS := {"Play":"Home","Offline":"Play","Match setup":"Offline","Settings":"Home","Career":"Home","Load career":"Career","Create player":"Home","Training camp":"Home","Iteration Lab":"Settings"}
var return_page := "Home"
var music := AudioStreamPlayer.new()
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
	overlay.layer = 20
	add_child(overlay)
	overlay.add_child(ribbon)
	ribbon.color = Color("6df3ceaa")
	ribbon.hide()
	add_child(music)
	music.stream = preload("res://assets/menu/night_session.wav")
	music.volume_db = -14
	music_enabled = StorySession.game_options.get_value("audio","menu_music",true)
	get_tree().scene_changed.connect(scene_entered)

func refresh_menu_buttons() -> void:
	var xbox = preload("res://scripts/xbox_controls.gd")
	for binding in [["ui_accept",JOY_BUTTON_A],["ui_cancel",JOY_BUTTON_B]]:
		for previous in InputMap.action_get_events(binding[0]):
			if previous is InputEventJoypadButton: InputMap.action_erase_event(binding[0],previous)
		bind_menu_button(binding[0],xbox.physical(binding[1]))

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
		if scene.scene_file_path not in ["res://scenes/story_animations.tscn","res://scenes/setter_tryout.tscn"] and not is_instance_valid(scene.get("setting_stage")):
			set_music(true)

func set_music(in_menu: bool) -> void:
	if in_menu and music_enabled and music.stream:
		if not music.playing: music.play()
	else:
		music.stop()

func toggle_music(enabled: bool) -> void:
	music_enabled = enabled
	StorySession.game_options.set_value("audio","menu_music",enabled)
	StorySession.save_options()
	set_music(true)

func backdrop(parent: Control, hero: bool) -> void:
	parent.theme = skin
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
	parent.add_child(center)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	center.add_child(scroll)
	var fit := func():
		scroll.custom_minimum_size = Vector2(minf(510,center.size.x-20),maxf(180,center.size.y-70))
	center.resized.connect(fit)
	fit.call_deferred()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation",7)
	scroll.add_child(column)

func heading(column: VBoxContainer, route: String, title: String) -> void:
	var trail := PackedStringArray()
	var parent: String = PARENTS.get(route,"")
	while not parent.is_empty():
		trail.insert(0,parent.to_upper())
		parent = PARENTS.get(parent,"")
	var overline := Label.new()
	overline.text = "MAIN MENU" if trail.is_empty() else "   /   ".join(trail)
	overline.add_theme_font_size_override("font_size",14)
	overline.add_theme_color_override("font_color",Color("6de4d1"))
	column.add_child(overline)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size",34 if route=="Home" else 48)
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

func build_theme() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift","Segoe UI","sans-serif"])
	skin.default_font = font
	skin.default_font_size = 17
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
var catalog := FACTS + preload("res://scripts/olympic_facts.gd").FACTS
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
var fact_started_ms := 0
var dismiss_fact := false

func show_loading(destination: String) -> void:
	fact_started_ms = Time.get_ticks_msec()
	dismiss_fact = false
	loading_screen = ColorRect.new()
	loading_screen.modulate.a = 0.
	loading_screen.color = Color("112433")
	loading_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.add_child(loading_screen)
	loading_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop(loading_screen,false)
	var center := CenterContainer.new()
	loading_screen.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	center.add_child(column)
	var title := Label.new()
	title.text = destination
	title.add_theme_font_size_override("font_size",48)
	column.add_child(title)
	loading_detail = Label.new()
	loading_detail.text = "Loading…"
	loading_detail.add_theme_color_override("font_color",Color("73e1d2"))
	column.add_child(loading_detail)
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
		if event.is_action_pressed("ui_accept"): dismiss_fact = true
		get_viewport().set_input_as_handled()

func painted() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func fade_loading(alpha: float, seconds: float) -> void:
	var fade := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	fade.tween_property(loading_screen,"modulate:a",alpha,seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade.finished

func close_loading() -> void:
	while not dismiss_fact and Time.get_ticks_msec() - fact_started_ms < 2600:
		await get_tree().process_frame
	await fade_loading(0.,.38)
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
	var key := path.get_file().get_basename()
	var names := {"main":"Main menu","story":"My Career","drills":"Training camp","create":"Create player","setter_tryout":"Setter tryout","story_animations":"Court session"}
	show_loading(names.get(key,key.capitalize()))
	await fade_loading(1.,.18)
	await painted()
	var error := ResourceLoader.load_threaded_request(path,"PackedScene")
	if error == OK:
		var progress := []
		var status := ResourceLoader.load_threaded_get_status(path,progress)
		while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if progress.size(): loading_detail.text = "Loading…  %d%%" % roundi(progress[0]*100.)
			await get_tree().process_frame
			status = ResourceLoader.load_threaded_get_status(path,progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			loading_detail.text = "Preparing court…" if key in ["setter_tryout","story_animations","court"] else "Opening menu…"
			await painted()
			error = get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(path))
			if error == OK:
				await get_tree().scene_changed
				await painted()
		else: error = ERR_CANT_OPEN
	if error != OK:
		push_error("Could not open "+path+": "+error_string(error))
		loading_detail.text = "Could not open this destination"
		await get_tree().create_timer(1.5).timeout
	close_loading()
