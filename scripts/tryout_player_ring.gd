extends Control

const PromptControls = preload("res://scripts/xbox_controls.gd")
var game: Control

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index=2

func _process(_dt: float) -> void:
	queue_redraw()

func arc_band(center: Vector2,radius: Vector2,start: float,end: float,color: Color,width: float) -> void:
	if end<=start: return
	var points := PackedVector2Array()
	for i in 49:
		var a := lerpf(start,end,i/48.)
		points.append(center+Vector2(cos(a),sin(a))*radius)
	draw_polyline(points,color,width,true)

func _draw() -> void:
	if not game or not game.is_node_ready() or game.settings.visible or game.phase in ["intro","net_guide","complete"]: return
	var human: Node3D=game.rotation_drill.roster[0]
	draw_player(human,true)
	if game.preview_enabled: draw_set_path(human)
	if game.phase in ["feed","pass"]:
		var called: int=game.called()
		var anchor: Vector3=game.targets[called].global_position+Vector3.UP*.43
		if not game.camera.is_position_behind(anchor):
			var point: Vector2=game.camera.unproject_position(anchor)
			var icon := PromptControls.glyph(game.BUTTONS[called])
			var font := ThemeDB.fallback_font
			var width := font.get_string_size(game.TARGETS[called],HORIZONTAL_ALIGNMENT_LEFT,-1,16).x+74
			draw_rect(Rect2(point-Vector2(width*.5,18),Vector2(width,32)),Color("14242eee"))
			var left := point+Vector2(-width*.5+6,5)
			draw_string(font,left,"Hold",HORIZONTAL_ALIGNMENT_LEFT,-1,16)
			if PromptControls.keyboard_prompts():
				draw_string(font,left+Vector2(33,0),"[" + OS.get_keycode_string(game.KEYS[called]) + "]",HORIZONTAL_ALIGNMENT_CENTER,27,16)
			else:
				draw_texture_rect(icon,Rect2(left+Vector2(33,-19),Vector2(27,24)),false)
			draw_string(font,left+Vector2(62,0),game.TARGETS[called],HORIZONTAL_ALIGNMENT_LEFT,-1,16)
	if game.setter!=human: draw_player(game.setter,false)

func draw_set_path(actor: Node3D) -> void:
	var active: bool=actor==game.setter
	var target: int=game.held if active else game.free_target
	if target<0 and (game.clock<game.preview_until or game.stick_latched): target=game.called()
	if target<0: return
	var a: Vector3=game.catch_point if active else (game.Contact.palm(actor,"l")+game.Contact.palm(actor,"r"))*.5
	var b: Vector3=game.PINS[target]
	var tempo: int=game.chosen_tempo()
	var height: float=game.APEX[tempo] if active else 9.81*pow(game.DURATION[tempo],2)/8.
	for i in 41:
		var pos: Vector3=game.arc(a,b,i/40.,height)
		if not game.camera.is_position_behind(pos):
			var pt: Vector2=game.camera.unproject_position(pos)
			draw_circle(pt,2.9,Color("122420aa"))
			draw_circle(pt,1.8,Color("87f4ddee"))

func draw_player(actor: Node3D,human: bool) -> void:
	var foot := Vector3(actor.position.x,.08,actor.position.z)
	if game.camera.is_position_behind(foot): return
	var at: Vector2=game.camera.unproject_position(foot)
	var radius := Vector2(clampf(at.distance_to(game.camera.unproject_position(foot+game.camera.global_basis.x*.67)),25,77),0)
	radius.y=radius.x*.35
	var color := Color("70e3dc") if human else Color("ffbb7c")
	arc_band(at,radius,0,TAU,Color("15242b"),6)
	arc_band(at,radius,PI,TAU,color,2)
	arc_band(at,radius,0,PI*game.energy[actor].value/100.,color,4)
	if actor==game.setter or human:
		draw_string(ThemeDB.fallback_font,at+Vector2(-75,radius.y+18),"Stamina / skills %d%%" % roundi(actor.stamina.value),HORIZONTAL_ALIGNMENT_CENTER,150,14)
		var squat: RefCounted=game.squat if actor==game.setter else game.free_squat
		var jump: RefCounted=game.jump if actor==game.setter else game.free_jump
		var outer := radius+Vector2(4,4)
		var charge: float=clampf(squat.seconds/squat.FULL_LOAD,0,1) if squat.charging else 0.
		if jump.active: charge=clampf(squat.seconds/squat.FULL_LOAD,0,1) if squat.seconds>0 else .67
		if charge>0: timing_arc(at,outer,0,charge,squat.GREEN_START,squat.GREEN_END)
		if actor!=game.setter and game.free_target>=0:
			timing_arc(at,outer,PI,clampf((game.clock-game.free_press)/.43,0,1),.47,.76)
		var pressing: bool=game.held>=0 and game.phase in ["cart","walk","feed","pass"]
		var result: bool=game.clock<game.set_grade_until
		if actor==game.setter and (pressing or result):
			var fill: float=game.set_fill() if pressing else game.graded_fill
			timing_arc(at,outer,PI,fill,.55,.85)
	var label: String=actor.display_name.strip_edges().get_slice(" ",actor.display_name.strip_edges().count(" ")).to_upper()
	var origin := at+Vector2(-80,radius.y+19)
	draw_string_outline(ThemeDB.fallback_font,origin,label,HORIZONTAL_ALIGNMENT_CENTER,160,14,4,Color("10191f"))
	draw_string(ThemeDB.fallback_font,origin,label,HORIZONTAL_ALIGNMENT_CENTER,160,14,Color("ffce75") if actor==game.setter else Color.WHITE)

func timing_arc(at: Vector2,radius: Vector2,start: float,value: float,low: float,high: float) -> void:
	var cuts := [0.,low,high,1.]
	var colors := [Color("f7bd46"),Color("61ed88"),Color("f45550")]
	for i in 3:
		var begin: float=cuts[i]
		var end: float=cuts[i+1]
		arc_band(at,radius,start+begin*PI,start+end*PI,colors[i].darkened(.43),7)
		arc_band(at,radius,start+begin*PI,start+clampf(value,begin,end)*PI,colors[i],7)
	var angle := start+value*PI
	var cursor := at+Vector2(cos(angle),sin(angle))*radius
	draw_circle(cursor,4.5,Color("182329"),true,-1,true)
	draw_circle(cursor,3.,Color.WHITE,true,-1,true)
