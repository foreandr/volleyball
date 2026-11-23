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
	bind_menu_button("ui_accept",JOY_BUTTON_A)
	bind_menu_button("ui_cancel",JOY_BUTTON_B)
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

func bind_menu_button(action: StringName, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	if not InputMap.action_has_event(action,event):
		InputMap.action_add_event(action,event)

func scene_entered() -> void:
	var scene := get_tree().current_scene as Control
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
	label.add_theme_font_size_override("font_size",48)
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
