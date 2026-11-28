extends CanvasLayer

var caption := Label.new()
var speed_caption := Label.new()
var speed_fade: Tween
var speed_scene: Node
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
	add_child(speed_caption)
	speed_caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	speed_caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	speed_caption.offset_top=134
	speed_caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	speed_caption.add_theme_font_size_override("font_size",18)
	speed_caption.add_theme_constant_override("outline_size",5)
	speed_caption.add_theme_color_override("font_outline_color",Color("152024"))
	speed_caption.hide()

func launch_speed(velocity:Vector3, details:String) -> void:
	if not StorySession.game_options.get_value("presentation","launch_speed",true): return
	if speed_fade: speed_fade.kill()
	speed_scene=get_tree().current_scene
	speed_caption.text="%.1f km/h"%(velocity.length()*3.6)
	var explain:bool=StorySession.game_options.get_value("presentation","speed_details",true)
	if explain and not details.is_empty(): speed_caption.text+="\n"+details
	speed_caption.modulate.a=0.
	speed_caption.show()
	speed_fade=create_tween()
	speed_fade.tween_property(speed_caption,"modulate:a",1.,.10)
	speed_fade.tween_interval(3. if explain else 1.4)
	speed_fade.tween_property(speed_caption,"modulate:a",0.,.35)
	speed_fade.tween_callback(speed_caption.hide)

func speed_options(host:Container) -> void:
	for item in [["launch_speed","Show attack and serve speed"],["speed_details","Show speed calculation"]]:
		var toggle:=CheckButton.new()
		toggle.text=item[1]
		toggle.button_pressed=StorySession.game_options.get_value("presentation",item[0],true)
		host.add_child(toggle)
		toggle.toggled.connect(func(on:bool):
			StorySession.game_options.set_value("presentation",item[0],on)
			StorySession.save_options()
			speed_caption.hide())


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
	if speed_caption.visible and speed_scene!=get_tree().current_scene: speed_caption.hide()
	if caption.visible and owner_scene!=get_tree().current_scene: caption.hide()
