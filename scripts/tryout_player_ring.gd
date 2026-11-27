extends Control

const PromptControls = preload("res://scripts/xbox_controls.gd")
var game: Control
var participants: Array = []
var extra_jumps := {}
var setting_cues := true
var floor_rings := {}
var displayed_timing := {}
var ring_mesh := ImmediateMesh.new()

func make_ring_mesh() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo=true
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	for band in [[.561,.582,Color("10171d")],[.582,.622,Color.WHITE],[.622,.644,Color("10171d")]]:
		ring_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP,material)
		ring_mesh.surface_set_color(band[2])
		for i in 65:
			var direction := Vector3(cos(TAU*i/64.),0.,sin(TAU*i/64.))
			ring_mesh.surface_set_uv(Vector2(i/64.,0.))
			ring_mesh.surface_add_vertex(direction*float(band[0]))
			ring_mesh.surface_set_uv(Vector2(i/64.,1.))
			ring_mesh.surface_add_vertex(direction*float(band[1]))
		ring_mesh.surface_end()

func position_floor_ring(actor: Node3D) -> void:
	if not floor_rings.has(actor):
		var ring := MeshInstance3D.new()
		ring.mesh=ring_mesh
		var fill := ShaderMaterial.new()
		fill.shader=preload("res://assets/gym/court_stamina.gdshader")
		ring.set_surface_override_material(1,fill)
		ring.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		actor.add_child(ring)
		ring.top_level=true
		floor_rings[actor]=ring
	var ring: MeshInstance3D=floor_rings[actor]
	var fill: ShaderMaterial=ring.get_surface_override_material(1)
	fill.set_shader_parameter("remaining",clampf(actor.stamina.fraction(),0.,1.))
	ring.global_transform=Transform3D(Basis.IDENTITY,Vector3(actor.global_position.x,.055,actor.global_position.z))
	ring.show()
	if ring.get_child_count()>0: ring.get_child(0).hide()


func _ready() -> void:
	make_ring_mesh()
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index=2

func _process(delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game!=null and "replay_inspector" in game and game.replay_inspector.active: return
	displayed_timing.clear()
	for ring in floor_rings.values():
		if is_instance_valid(ring): ring.hide()
	if game==null:
		for actor in participants:
			if is_instance_valid(actor) and actor.is_visible_in_tree(): draw_player(actor,true)
		return
	if not game.is_node_ready() or game.settings.visible or game.phase in ["intro","net_guide","complete"]: return
	if "receive_held" in game and not game.passers.is_empty():
		if game.control_digger:
			var defender: Node3D=game.dig_defender()
			draw_player(defender,true)
			if game.phase=="serve_return" and is_finite(game.defense_at):
				var release: float=game.dig_platforms[defender].pressed_at
				var offset: float=(release if is_finite(release) else game.dig_clock)-game.defense_at
				timing_arc(defender,clampf(.5+offset/.5,0.,1.),.39,.61,Vector2(.25,.75),Color("14191d"),is_finite(release))
			return
		var passer: Node3D=game.passers[1]
		draw_player(passer,true)
		if game.phase=="serve_flight" and not game.recipe.is_empty():
			var t: float=(game.released_at if is_finite(game.released_at) else game.flight_age)-game.receive_at
			timing_arc(passer,clampf(.5+t/.5,0.,1.),.33,.67,Vector2(.5-game.RECEIVE_EARLY/.5,.5+game.RECEIVE_LATE/.5),Color("14191d"),is_finite(game.released_at))
		return
	var human: Node3D=game.rotation_drill.roster[0]
	if "automatic_block" in game:
		if not game.automatic_block and game.blockers.size()>game.MANUAL_SLOT:
			draw_player(game.blockers[game.MANUAL_SLOT],true)
		return
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
	position_floor_ring(actor)
	if (is_setter or human) and not (is_setter and game!=null and "automatic_block" in game):
		if is_setter and game!=null and game.has_method("serve_meter_error") and (game.phase=="serve_toss" or (game.phase in ["serve_flight","serve_miss"] and game.flight_age<.4)):
			var contact := Vector2(game.serve_meter_position(game.SERVE_EARLY),game.serve_meter_position(game.SERVE_LATE))
			timing_arc(actor,game.serve_meter_position(game.serve_meter_error()),game.serve_meter_position(-game.SERVE_PERFECT),game.serve_meter_position(game.SERVE_PERFECT),contact,Color("14191d"),is_finite(game.release_time))
		if is_setter and "defense_at" in game and game.phase in ["serve_pass","serve_attack","serve_return","server_dig"]:
			var release: float=game.dig_platforms[actor].pressed_at
			var elapsed: float=(release if is_finite(release) else game.dig_clock)-game.defense_at
			timing_arc(actor,clampf(.5+elapsed/.5,0.,1.),.5-game.DIG_PERFECT/.5,.5+game.DIG_PERFECT/.5,Vector2(.5-game.DIG_WINDOW/.5,.5+game.DIG_WINDOW/.5),Color("14191d"),is_finite(release))
		if extra_jumps.has(actor) and not game.cpu_hitter and game.manual_shot>=0 and (game.phase in ["cart","feed","pass","set_contact","set"] or (game.phase=="spike" and game.elapsed<.45)):
			var cursor: float=game.attack_meter_position(game.attack_meter_error())
			var contact_window:=Vector2(game.attack_meter_position(game.EARLY_LIMIT),game.attack_meter_position(game.LATE_LIMIT))
			timing_arc(actor,cursor,game.attack_meter_position(-game.CLEAN_EARLY),game.attack_meter_position(game.CLEAN_LATE),contact_window,Color("14191d"),is_finite(game.release_grade))
		if game!=null and setting_cues:
			if actor!=game.setter and game.free_target>=0:
				timing_arc(actor,clampf((game.clock-game.free_press)/.43,0,1),.47,.76)
			var pressing: bool=(game.held>=0 or (not game.bump_aim.is_zero_approx() and not game.bump_released)) and game.phase in ["cart","walk","feed","pass"] and not game.pending_release
			var result: bool=game.clock<game.set_grade_until or game.pending_release
			if is_setter and (pressing or result):
				var timing_fill: float=game.set_fill() if pressing else game.graded_fill
				var band: Vector2=game.timing_band() if pressing else game.grade_band
				var contact: Vector2=game.contact_band() if pressing else game.grade_contact
				timing_arc(actor,timing_fill,band.x,band.y,contact)
	var label: String=actor.display_name.strip_edges().get_slice(" ",actor.display_name.strip_edges().count(" ")).to_upper()
	if game!=null and "automatic_block" in game and not game.automatic_block and actor==game.blockers[game.MANUAL_SLOT]:
		label="509   YOU"
		if game.block_held or game.clock<game.meter_until:
			timing_arc(actor,game.block_meter(),.38,.62,Vector2(.10,.90),Color("14191d"),not game.block_held)
	var origin := at+Vector2(-80,radius.y+19)
	draw_string_outline(ThemeDB.fallback_font,origin,label,HORIZONTAL_ALIGNMENT_CENTER,160,14,4,Color("10191f"))
	draw_string(ThemeDB.fallback_font,origin,label,HORIZONTAL_ALIGNMENT_CENTER,160,14,Color("ffce75") if is_setter else Color.WHITE)

func timing_arc(actor: Node3D,value: float,low: float,high: float,contact := Vector2(0,1),miss_color := Color("778088"),highlight_release := false) -> void:
	displayed_timing[actor]={"position":floor_rings[actor].global_position,"value":value,"perfect":Vector2(low,high),"contact":contact,"miss":miss_color,"highlight":highlight_release,"stamina":actor.stamina.fraction()}
	paint_arc(actor,value,low,high,contact,miss_color,highlight_release)

func replay_timing(sample: Dictionary) -> void:
	for ring in floor_rings.values(): ring.hide()
	for actor in sample:
		if not is_instance_valid(actor): continue
		var state: Dictionary=sample[actor]
		position_floor_ring(actor)
		var ring: MeshInstance3D=floor_rings[actor]
		ring.global_position=state.position
		ring.get_surface_override_material(1).set_shader_parameter("remaining",state.stamina)
		paint_arc(actor,state.value,state.perfect.x,state.perfect.y,state.contact,state.miss,state.highlight)

func paint_arc(actor: Node3D,value: float,low: float,high: float,contact: Vector2,miss_color: Color,highlight_release: bool) -> void:
	var ring: MeshInstance3D=floor_rings[actor]
	var band: MeshInstance3D
	if ring.get_child_count()==0:
		band=MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size=Vector2(2.0,2.0)
		band.mesh=plane
		var material := ShaderMaterial.new()
		material.shader=preload("res://assets/gym/court_timing.gdshader")
		band.material_override=material
		band.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.add_child(band)
		band.position.y=.005
	else: band=ring.get_child(0)
	band.show()
	band.rotation.y=actor.get_viewport().get_camera_3d().global_rotation.y
	var material: ShaderMaterial=band.material_override
	material.set_shader_parameter("cursor",value)
	material.set_shader_parameter("perfect",Vector2(low,high))
	material.set_shader_parameter("contact",contact)
	material.set_shader_parameter("miss",miss_color)
	material.set_shader_parameter("highlight",highlight_release)
