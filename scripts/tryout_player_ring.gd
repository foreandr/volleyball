extends Control
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
	if not game or not game.is_node_ready() or game.settings.visible or game.phase=="intro": return
	var human: Node3D=game.rotation_drill.roster[0]
	draw_player(human,true)
	if game.setter!=human: draw_player(game.setter,false)

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
		var squat: RefCounted=game.squat if actor==game.setter else game.free_squat
		var jump: RefCounted=game.jump if actor==game.setter else game.free_jump
		var outer := radius+Vector2(4,4)
		var charge: float=clampf(squat.seconds/squat.FULL_LOAD,0,1) if squat.charging else 0.
		if jump.active: charge=clampf(squat.seconds/squat.FULL_LOAD,0,1) if squat.seconds>0 else .67
		if charge>0: timing_arc(at,outer,0,charge,squat.GREEN_START,squat.GREEN_END)
		if actor!=game.setter and game.free_target>=0:
			timing_arc(at,outer,PI,clampf((game.clock-game.free_press)/.75,0,1),.67,.89)
		if actor==game.setter and ((game.phase=="pass") or game.clock<game.set_grade_until):
			var duration: float=game.contact_time+.26
			var window: float=game.timing_window()*.6
			var age: float=game.elapsed if game.phase=="pass" else game.contact_time+game.set_error
			timing_arc(at,outer,PI,clampf(age/duration,0,1),(game.contact_time-window)/duration,(game.contact_time+window)/duration)
	var label: String=actor.display_name.strip_edges().get_slice(" ",actor.display_name.strip_edges().count(" ")).to_upper()
	var origin := at+Vector2(-80,radius.y+19)
	draw_string_outline(ThemeDB.fallback_font,origin,label,HORIZONTAL_ALIGNMENT_CENTER,160,14,4,Color("10191f"))
	draw_string(ThemeDB.fallback_font,origin,label,HORIZONTAL_ALIGNMENT_CENTER,160,14,Color.WHITE)

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
