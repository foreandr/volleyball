extends RefCounted

const FACE := [JOY_BUTTON_A,JOY_BUTTON_X,JOY_BUTTON_Y,JOY_BUTTON_B]
const AUX := [JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER,JOY_BUTTON_RIGHT_STICK,JOY_BUTTON_START,JOY_BUTTON_LEFT_STICK]
const NAMES := {JOY_BUTTON_A:"A",JOY_BUTTON_B:"B",JOY_BUTTON_X:"X",JOY_BUTTON_Y:"Y",JOY_BUTTON_LEFT_SHOULDER:"LB",JOY_BUTTON_RIGHT_SHOULDER:"RB",JOY_BUTTON_RIGHT_STICK:"RS",JOY_BUTTON_START:"Menu",JOY_BUTTON_LEFT_STICK:"LS"}
const CONTROLS := ["Serve / jump / pipe","Forearm receive / left set","Hand receive / middle set","Back / right set","Next toss","Match sprint","Jump set","Pause","Show / hide set arc"]

static func keyboard_prompts() -> bool:
	return StorySession.game_options.get_value("controls","keyboard_prompts",false)

static func hint(action: String, keyboard: String) -> String:
	return keyboard if keyboard_prompts() else action

static func auxiliary_bindings() -> Array:
	var mapping: Array=StorySession.game_options.get_value("xbox","aux",AUX).duplicate()
	if mapping.size()==4: mapping.append(JOY_BUTTON_LEFT_STICK)
	return mapping

static func physical(logical: int) -> int:
	var slot := FACE.find(logical)
	if slot>=0: return StorySession.pad_bindings[slot]
	return auxiliary_bindings()[AUX.find(logical)]

static func trigger(left: bool) -> JoyAxis:
	var swapped := bool(StorySession.game_options.get_value("xbox","swap_triggers",false))
	return JOY_AXIS_TRIGGER_LEFT if left!=swapped else JOY_AXIS_TRIGGER_RIGHT

static var view_icon: Texture2D

static func glyph(control: Variant) -> Texture2D:
	if control is String and control=="View":
		if not view_icon:
			var icon := Image.new()
			icon.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="42" height="32" viewBox="0 0 42 32"><rect x="3" y="3" width="36" height="26" rx="12" fill="#303b44" stroke="#dfe9eb"/><path d="M14 17h-3V9h12v3" fill="none" stroke="white" stroke-width="2"/><rect x="17" y="14" width="12" height="9" fill="none" stroke="white" stroke-width="2"/></svg>')
			view_icon=ImageTexture.create_from_image(icon)
		return view_icon
	var key: String
	if control is int: key = NAMES[physical(control)]
	elif control in ["LT","RT"]: key = "LT" if trigger(control=="LT")==JOY_AXIS_TRIGGER_LEFT else "RT"
	else: key = control
	return load("res://assets/input/xbox/%s.png" % key)

static func prompts(parent: Container,entries: Array) -> void:
	for node in parent.get_children():
		parent.remove_child(node)
		node.queue_free()
	for entry in entries:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation",1)
		parent.add_child(pair)
		var icon := TextureRect.new()
		icon.texture = glyph(entry[0])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(37,28)
		pair.add_child(icon)
		var label := Label.new()
		label.text = entry[1]
		label.add_theme_font_size_override("font_size",15)
		pair.add_child(label)

static func settings(parent: Container,refresh: Callable) -> void:
	var keyboard := CheckButton.new()
	keyboard.text = "Show keyboard prompts"
	keyboard.button_pressed = keyboard_prompts()
	keyboard.toggled.connect(func(enabled):
		StorySession.game_options.set_value("controls","keyboard_prompts",enabled)
		StorySession.save_options())
	parent.add_child(keyboard)
	for i in CONTROLS.size():
		# Keep the legacy auxiliary slot in saved maps for remapping other controls.
		if i==FACE.size()+AUX.find(JOY_BUTTON_RIGHT_STICK): continue
		var choices: Array = FACE if i<4 else AUX
		var slot := i if i<4 else i-4
		var option := OptionButton.new()
		option.name = "Binding%d" % i
		option.add_theme_constant_override("icon_max_width",36)
		option.get_popup().add_theme_constant_override("icon_max_width",36)
		for button in choices:
			option.add_icon_item(load("res://assets/input/xbox/%s.png" % NAMES[button]),CONTROLS[i],button)
		option.select(choices.find(physical(choices[slot])))
		parent.add_child(option)
		option.item_selected.connect(func(index: int):
			var mapping: Array = StorySession.pad_bindings if i<4 else auxiliary_bindings()
			var other := mapping.find(choices[index])
			mapping[other] = mapping[slot]
			mapping[slot] = choices[index]
			if i>=4: StorySession.game_options.set_value("xbox","aux",mapping)
			StorySession.save_options()
			MenuPresentation.refresh_menu_buttons()
			refresh.call()
			var current := parent.get_node_or_null("Binding%d" % i) as Control
			if current: current.grab_focus())
	var triggers := CheckButton.new()
	triggers.text = "Swap focus and sprint triggers"
	triggers.button_pressed = StorySession.game_options.get_value("xbox","swap_triggers",false)
	triggers.toggled.connect(func(on):
		StorySession.game_options.set_value("xbox","swap_triggers",on)
		StorySession.save_options())
	parent.add_child(triggers)
