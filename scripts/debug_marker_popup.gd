extends Label

var marker_fade: Tween

func _ready() -> void:
	add_theme_font_size_override("font_size",16)
	name = "DebugMarkerPopup"
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := StyleBoxFlat.new()
	badge.bg_color = Color("152331")
	badge.border_color = Color("59d6ec")
	badge.set_border_width_all(1)
	badge.set_corner_radius_all(7)
	add_theme_stylebox_override("normal",badge)
	z_index = 1
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_left = -150
	offset_right = 150
	offset_top = 16
	offset_bottom = 54
	hide()

func dismiss() -> void:
	if marker_fade != null: marker_fade.kill()
	hide()

func flash(caption := "Debug marker saved") -> void:
	if marker_fade != null: marker_fade.kill()
	text = caption
	modulate.a = 1.0
	show()
	marker_fade = create_tween()
	marker_fade.tween_interval(1.45)
	marker_fade.tween_property(self,"modulate:a",0.0,0.35)
	marker_fade.tween_callback(hide)
