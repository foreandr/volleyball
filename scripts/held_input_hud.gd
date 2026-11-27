extends CanvasLayer

const Xbox = preload("res://scripts/xbox_controls.gd")
var row := HBoxContainer.new()
var last := -2
var reviewing := false

func _ready() -> void:
	layer=91
	process_mode=Node.PROCESS_MODE_ALWAYS
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.grow_horizontal=Control.GROW_DIRECTION_BEGIN
	row.offset_right=-18
	row.offset_top=16
	row.mouse_filter=Control.MOUSE_FILTER_IGNORE

func read_buttons() -> int:
	var pads := Input.get_connected_joypads()
	var pad: int=get_parent().pad() if get_parent().has_method("pad") else (-1 if pads.is_empty() else pads[0])
	if pad<0: return 0
	var mask := 0
	for i in 15:
		if Input.is_joy_button_pressed(pad,i): mask |= 1<<i
	if Input.get_joy_axis(pad,JOY_AXIS_TRIGGER_LEFT)>.25: mask |= 1<<15
	if Input.get_joy_axis(pad,JOY_AXIS_TRIGGER_RIGHT)>.25: mask |= 1<<16
	return mask

func _process(_delta: float) -> void:
	if not reviewing: display(read_buttons())

func display(mask: int) -> void:
	if last==mask: return
	last=mask
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	var caption := Label.new()
	caption.text="Held" if mask>0 else ("Held: none" if mask==0 else "Input unavailable")
	caption.add_theme_constant_override("outline_size",4)
	row.add_child(caption)
	var names := ["A","B","X","Y","View","Guide","Menu","LS","RS","LB","RB","D-pad Up/Down","D-pad Up/Down","D-pad Left/Right","D-pad Left/Right","LT","RT"]
	for i in names.size():
		if mask<0 or (mask & (1<<i))==0: continue
		if i==5:
			var guide := Label.new()
			guide.text="Xbox"
			row.add_child(guide)
			continue
		var icon := TextureRect.new()
		icon.texture=Xbox.GLYPHS.get(names[i]) if Xbox.GLYPHS.has(names[i]) else Xbox.glyph(names[i])
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size=Vector2(35,27)
		row.add_child(icon)
		if i>=11 and i<=14:
			var direction := Label.new()
			direction.text=["Up","Down","Left","Right"][i-11]
			row.add_child(direction)
