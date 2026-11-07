extends Control
var players: Array[Node3D] = []
var panel: PanelContainer
var player_picker: OptionButton
var clip_picker: OptionButton
var slot_picker: OptionButton
var status: Label
var dialog: FileDialog
var current_clips: PackedStringArray
const SLOTS := ["idle","run","jump","land","serve","pass","set","spike","block"]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var button := Button.new()
	button.text = "Animations"
	button.position = Vector2(1110,24)
	button.custom_minimum_size = Vector2(146,40)
	button.pressed.connect(toggle)
	add_child(button)
	panel = PanelContainer.new()
	panel.position = Vector2(880,80)
	panel.custom_minimum_size = Vector2(376,320)
	add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,16)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "PLAYER ANIMATIONS"
	column.add_child(title)
	player_picker = OptionButton.new()
	for athlete in players: player_picker.add_item(athlete.name)
	player_picker.item_selected.connect(func(_index): refresh_clips())
	column.add_child(player_picker)
	slot_picker = OptionButton.new()
	for slot in SLOTS: slot_picker.add_item(slot.capitalize()+" slot")
	column.add_child(slot_picker)
	clip_picker = OptionButton.new()
	clip_picker.item_selected.connect(func(index): players[player_picker.selected].play_action(current_clips[index]))
	column.add_child(clip_picker)
	var assign := Button.new()
	assign.text = "Assign selected clip to slot"
	assign.pressed.connect(assign_selected)
	column.add_child(assign)
	var load_clip := Button.new()
	load_clip.text = "Import custom animation..."
	load_clip.pressed.connect(func(): dialog.popup_centered(Vector2i(900,600)))
	column.add_child(load_clip)
	var reset := Button.new()
	reset.text = "Preview idle"
	reset.pressed.connect(func(): players[player_picker.selected].play_action("idle"))
	column.add_child(reset)
	status = Label.new()
	status.text = "Same skeleton as FightLab.
Custom clips: Godot .tres / .res"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 340
	column.add_child(status)
	dialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.tres, *.res ; Godot animation or animation library"])
	dialog.file_selected.connect(import_clip)
	add_child(dialog)
	refresh_clips()
	panel.hide()

func toggle() -> void:
	panel.visible = not panel.visible

func refresh_clips() -> void:
	clip_picker.clear()
	current_clips = players[player_picker.selected].animator.get_animation_list()
	for clip in current_clips: clip_picker.add_item(clip)

func assign_selected() -> void:
	if clip_picker.selected < 0: return
	var athlete = players[player_picker.selected]
	var slot: String = SLOTS[slot_picker.selected]
	var clip: Animation = athlete.animator.get_animation(current_clips[clip_picker.selected])
	if athlete.install_custom(clip,slot):
		status.text = "Saved %s: %s" % [athlete.name,slot.capitalize()]
		refresh_clips()

func import_clip(path: String) -> void:
	var resource := ResourceLoader.load(path)
	if resource == null:
		status.text = "Could not load that animation."
		return
	var athlete = players[player_picker.selected]
	if athlete.install_custom(resource,SLOTS[slot_picker.selected]):
		status.text = "Custom animation saved for "+str(athlete.name)
		refresh_clips()
	else: status.text = "Choose an Animation or AnimationLibrary resource."

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		toggle()
		get_viewport().set_input_as_handled()
