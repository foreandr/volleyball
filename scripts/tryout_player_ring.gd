extends Control

const PromptControls = preload("res://scripts/xbox_controls.gd")
var game: Control
var participants: Array = []
var extra_jumps := {}
var setting_cues := true
var display_clock := 0.0
var jump_readouts := {}

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index=2

func _process(delta: float) -> void:
	display_clock+=delta
	queue_redraw()

func arc_band(center: Vector2,radius: Vector2,start: float,end: float,color: Color,width: float) -> void:
	if end<=start: return
	var points := PackedVector2Array()
	for i in 49:
		var a := lerpf(start,end,i/48.)
		points.append(center+Vector2(cos(a),sin(a))*radius)
	draw_polyline(points,color,width,true)

func _draw() -> void:
	if game==null:
		for actor in participants:
			if is_instance_valid(actor) and actor.is_visible_in_tree(): draw_player(actor,true)
		return
	if not game.is_node_ready() or game.settings.visible or game.phase in ["intro","net_guide","complete"]: return
	var human: Node3D=game.rotation_drill.roster[0]
	for actor in extra_jumps: draw_player(actor,true)
	draw_player(human,true)
	if game.setter!=human: draw_player(game.setter,false)
	if not setting_cues:
		if not extra_jumps.is_empty() and not game.cpu_hitter and game.phase=="set" and game.aim_center.is_finite() and game.manual_shot>=0:
			var center := Vector3(game.aim_center.x,.06,game.aim_center.y)
			var points := PackedVector2Array()
			for i in 49:
				var angle := TAU*i/48.
				var ground := center+Vector3(cos(angle),0.,sin(angle))*float(game.aim_radius())
				if game.camera.is_position_behind(ground): return
				points.append(game.camera.unproject_position(ground))
			draw_polyline(points,Color("10171dc0"),4.,true)
			var tint: Color=game.predicted_shot_color(game.predicted_attack_origin(),Vector3(center.x,game.Contact.BALL_RADIUS,center.z))
			draw_polyline(points,tint,2.5,true)
			draw_circle(game.camera.unproject_position(center),3.,tint)
		return
	if game.phase=="pass": draw_incoming_toss()
	if not game.bump_aim.is_zero_approx() and game.phase in ["feed","pass"]:
		var aim: Vector3=game.bump_destination()
		if not game.camera.is_position_behind(aim):
			var dot: Vector2=game.camera.unproject_position(aim)
			draw_circle(dot,6.,Color("182329"))
			draw_circle(dot,4.,Color.WHITE)
	elif game.preview_enabled: draw_set_path(human)
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


func draw_incoming_toss() -> void:
	var time: float=game.forehead_arrival
	var vy: float=(game.forehead_target.y-game.source.y)/time+4.905*time
	var floor_y := .15
	var landing_time := (vy+sqrt(vy*vy+19.62*maxf(0.,game.source.y-floor_y)))/9.81
	var landing: Vector3=game.toss_at(landing_time)
	landing.y=.055
	var camera: Camera3D=game.camera
	if camera.is_position_behind(landing): return
	var point := camera.unproject_position(landing)
	draw_circle(point,4.5,Color.WHITE,true,-1,true)
	draw_circle(point,3.,Color("15191e"),true,-1,true)

func draw_set_path(actor: Node3D) -> void:
	var active: bool=actor==game.setter
	var target: int=game.held if active else game.free_target
	if target<0 and game.clock<game.preview_until: target=game.called()
	if target<0: return
	var a: Vector3=game.catch_point if active else (game.Contact.palm(actor,"l")+game.Contact.palm(actor,"r"))*.5
	var b: Vector3=game.PINS[target]
	var tempo: int=game.chosen_tempo()
	if game.solo_setting and active:
		b=game.set_destination(a,b,tempo)
	if game.clock<game.preview_until and not game.camera.is_position_behind(b):
		draw_string(ThemeDB.fallback_font,game.camera.unproject_position(b)+Vector2(8,-14),game.TEMPOS[tempo],HORIZONTAL_ALIGNMENT_LEFT,-1,16)
	var height: float=game.APEX[tempo] if active else 9.81*pow(game.DURATION[tempo],2)/8.
	for i in 41:
		var pos: Vector3=game.arc(a,b,i/40.,height)
		if not game.camera.is_position_behind(pos):
			var pt: Vector2=game.camera.unproject_position(pos)
			draw_circle(pt,2.9,Color("122420aa"))
			draw_circle(pt,1.8,Color("87f4ddee"))

func draw_player(actor: Node3D,human: bool) -> void:
	var camera: Camera3D=actor.get_viewport().get_camera_3d()
	if not camera: return
	var foot := Vector3(actor.global_position.x,.08,actor.global_position.z)
	if camera.is_position_behind(foot): return
	var at:=camera.unproject_position(foot)
	var is_setter: bool=game!=null and actor==game.setter
	var radius := Vector2(clampf(at.distance_to(camera.unproject_position(foot+camera.global_basis.x*.67)),25,77),0)
	radius.y=radius.x*.35
	var ink := Color("10171d")
	arc_band(at,radius,0,TAU,ink,6)
	arc_band(at,radius,0,TAU,Color.WHITE,2)
	if is_setter or human:
		var energy: RefCounted=actor.stamina
		var origin := at+Vector2(-52,radius.y+25)
		draw_rect(Rect2(origin-Vector2.ONE,Vector2(106,9)),Color.WHITE)
		draw_rect(Rect2(origin,Vector2(104,7)),ink)
		var available := float(energy.fraction())*104.
		draw_rect(Rect2(origin,Vector2(available,7)),Color.WHITE)
		var spent := minf(104.-available,energy.action_cost/energy.capacity()*104.)
		if spent>0.: draw_rect(Rect2(origin+Vector2(available,0),Vector2(spent,7)),Color("51cbe9"))
		var caption := "Stamina %d/%d" % [roundi(energy.value),roundi(energy.capacity())]
		if energy.value<0.:
			draw_rect(Rect2(origin,Vector2(104.*absf(energy.value)/maxf(1.,energy.willpower),7)),Color("d7a6ff"))
			caption="Reserve used %d/%d" % [ceili(-energy.value),roundi(energy.willpower)]
		if energy.action!="": caption+="   %s -%d" % [energy.action,ceili(energy.action_cost)]
		var text_pos := origin+Vector2(-48,22)
		draw_string_outline(ThemeDB.fallback_font,text_pos,caption,HORIZONTAL_ALIGNMENT_CENTER,200,13,4,ink)
		draw_string(ThemeDB.fallback_font,text_pos,caption,HORIZONTAL_ALIGNMENT_CENTER,200,13)
		var outer := radius+Vector2(4,4)
		var readout: Vector2=jump_readouts.get(actor,Vector2(0.,-100.))
		var fill := -1.0
		if game!=null:
			var jump: RefCounted=extra_jumps.get(actor,game.jump if is_setter else game.free_jump)
			var squat: RefCounted=game.squat if is_setter else game.free_squat
			if not extra_jumps.has(actor) and squat.charging: fill=squat.seconds/squat.FULL_LOAD
			elif jump.active: fill=jump.elapsed/maxf(.001,jump.load_duration())
		else:
			var lift := actor.global_position.y-.04
			if lift>.03: fill=lift/maxf(.1,float(actor.attributes.get("Vertical",30.))*.0254)
		var now: float=game.clock if game!=null else display_clock
		if fill>=0.:
			readout=Vector2(clampf(fill,0.,1.),now)
			jump_readouts[actor]=readout
		var opacity := 1.-smoothstep(.85,1.15,now-readout.y)
		if opacity>0.:
			var base := at+Vector2(radius.x+10,2)
			draw_rect(Rect2(base-Vector2(2,34),Vector2(14,36)),Color(Color.WHITE,opacity))
			draw_rect(Rect2(base-Vector2(0,32),Vector2(10,32)),Color(ink,opacity))
			draw_rect(Rect2(base-Vector2(0,32*readout.x),Vector2(10,32*readout.x)),Color(Color("51cbe9"),opacity))
		if extra_jumps.has(actor) and not game.cpu_hitter and game.manual_shot>=0 and (game.phase in ["cart","feed","pass","set_contact","set"] or (game.phase=="spike" and game.elapsed<.45)):
			var cursor: float=game.attack_meter_position(game.attack_meter_error())
			var contact_window:=Vector2(game.attack_meter_position(game.EARLY_LIMIT),game.attack_meter_position(game.LATE_LIMIT))
			timing_arc(at,outer,PI,cursor,game.attack_meter_position(-game.CLEAN_WINDOW),game.attack_meter_position(game.CLEAN_WINDOW),contact_window,Color("14191d"))
		if game!=null and setting_cues:
			if actor!=game.setter and game.free_target>=0:
				timing_arc(at,outer,PI,clampf((game.clock-game.free_press)/.43,0,1),.47,.76)
			var pressing: bool=(game.held>=0 or (not game.bump_aim.is_zero_approx() and not game.bump_released)) and game.phase in ["cart","walk","feed","pass"] and not game.pending_release
			var result: bool=game.clock<game.set_grade_until or game.pending_release
			if is_setter and (pressing or result):
				var timing_fill: float=game.set_fill() if pressing else game.graded_fill
				var band: Vector2=game.timing_band() if pressing else game.grade_band
				var contact: Vector2=game.contact_band() if pressing else game.grade_contact
				timing_arc(at,outer,PI,timing_fill,band.x,band.y,contact)
	var label: String=actor.display_name.strip_edges().get_slice(" ",actor.display_name.strip_edges().count(" ")).to_upper()
	var origin := at+Vector2(-80,radius.y+19)
	draw_string_outline(ThemeDB.fallback_font,origin,label,HORIZONTAL_ALIGNMENT_CENTER,160,14,4,Color("10191f"))
	draw_string(ThemeDB.fallback_font,origin,label,HORIZONTAL_ALIGNMENT_CENTER,160,14,Color("ffce75") if is_setter else Color.WHITE)

func timing_arc(at: Vector2,radius: Vector2,start: float,value: float,low: float,high: float,contact := Vector2(0,1), miss_color := Color("778088")) -> void:
	var cuts := [0.,contact.x,clampf(low,contact.x,contact.y),clampf(high,contact.x,contact.y),contact.y,1.]
	var colors := [miss_color,Color("f7bd46"),Color("61ed88"),Color("f45550"),miss_color]
	for i in colors.size():
		var begin: float=cuts[i]
		var end: float=cuts[i+1]
		arc_band(at,radius,start+begin*PI,start+end*PI,colors[i].darkened(.12),7)
		arc_band(at,radius,start+begin*PI,start+clampf(value,begin,end)*PI,colors[i],7)
	var angle := start+value*PI
	var cursor := at+Vector2(cos(angle),sin(angle))*radius
	draw_circle(cursor,4.5,Color("182329"),true,-1,true)
	draw_circle(cursor,3.,Color.WHITE,true,-1,true)
