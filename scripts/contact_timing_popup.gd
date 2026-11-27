extends CanvasLayer

var caption := Label.new()
var fade: Tween
var owner_scene: Node

func _ready() -> void:
	layer = 80
	add_child(caption)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	caption.offset_top = 94
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",26)
	caption.add_theme_constant_override("outline_size",6)
	caption.add_theme_color_override("font_outline_color",Color("152024"))
	caption.hide()

func scored(action:String,offset:float,green:bool,playable:bool,estimated:=false) -> void:
	if not is_finite(offset): return
	var ms:=roundi(offset*1000.)
	var direction:="early" if offset<0. else "late"
	var grade:="On time"
	if not playable: grade="Too "+direction
	elif ms!=0: grade=direction.capitalize()
	if green and playable and ms!=0: grade="Perfect · "+direction
	display("%s   %s   %+d ms%s"%[action,grade,ms," (estimated)" if estimated else ""],Color("82eab2") if green and playable else (Color("ffd571") if playable else Color("ff998a")))

func window(action:String,offset:float,early:float,late:float,green_early:float,green_late:float,estimated:=false) -> void:
	scored(action,offset,offset>=green_early and offset<=green_late,offset>=early and offset<=late,estimated)

func display(message:String,tint:Color) -> void:
	if fade: fade.kill()
	owner_scene=get_tree().current_scene
	caption.text=message
	caption.modulate=Color(tint,0.)
	caption.show()
	fade=create_tween()
	fade.tween_property(caption,"modulate:a",1.,.12)
	fade.tween_interval(1.)
	fade.tween_property(caption,"modulate:a",0.,.38)
	fade.tween_callback(caption.hide)

func _process(_delta:float) -> void:
	if caption.visible and owner_scene!=get_tree().current_scene: caption.hide()
