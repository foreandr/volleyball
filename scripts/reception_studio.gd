extends Node3D

const Regions = preload("res://scripts/reception_regions.gd")
const HEAD_CELL := Vector3i(1,2,1)
var cell := HEAD_CELL
var quadrant := 0
var hover_number := Label3D.new()
const MAP_MIN := Vector3i.ZERO
const MAP_MAX := Vector3i(2,2,2)
const WIDTHS := ["Right","Center","Left"]
const HEIGHTS := ["Low","Mid","High"]
const CELL_SIZE := Vector3(1.10,2.20/3.,1.10)
const MAP_ORIGIN := Vector3(-1.5,0,-1.5)*CELL_SIZE
const Gym = preload("res://scripts/tryout_gym.gd")
var feed := preload("res://scripts/standing_float_serve.gd").new()
var server = preload("res://scripts/volleyball_player.gd").new()
var zone := MeshInstance3D.new()
var hover := MeshInstance3D.new()
var receiving := 0
var actors: Array[Node3D]=[]
var place := CheckButton.new()
var defenders: Array[Node3D]=[]
var dragging := -1
var drag_offset := Vector3.ZERO
var pass_marker := MeshInstance3D.new()
var dragging_target := false
var camera_offset := Vector3.ZERO
var other_grids: Array[MeshInstance3D]=[]
var pass_arc := HSlider.new()
const HandPass = preload("res://scripts/hand_setting_pose.gd")
var feed_offset := Vector3.ZERO
const HAND_RADIUS := .28
var hand_volume := MeshInstance3D.new()
var hand_toggle := CheckButton.new()
var contact_point := Vector3.ZERO
var contact_key := []
var feed_fraction := 1.
var set_intercept := Vector3.ZERO
var ball_trail := MeshInstance3D.new()
var trail_mesh := ImmediateMesh.new()
var trail_ink := StandardMaterial3D.new()
var approach_plant := preload("res://scripts/setter_jump.gd").new()
var shuffle_by_actor := {}
var reset_end_frame := 0.
var pass_end_frame := 0.
var reachable := false
var lattice := MeshInstance3D.new()
var highlight := MeshInstance3D.new()
var miss_label := Label.new()
var miss_logged := false
var region_label := Label.new()
var depth_label := Label.new()
const Catalog := "res://assets/reception_studio.json"
const Dive = preload("res://scripts/forward_reception_dive.gd")
const Save = preload("res://scripts/player_reception_save.gd")
var player = preload("res://scripts/volleyball_player.gd").new()
var pivot := Node3D.new()
var camera := Camera3D.new()
var ready_pose: Array[Transform3D]=[]
var clasp: Array[Transform3D]=[]
var clips: Array=[]
var index := 1
var frame := 0.
var playing := true
var yaw := 2.76
var elevation := .28
var distance := 6.8
var label := Label.new()
var play_button := Button.new()
var seek := HSlider.new()
var mirror := CheckButton.new()
var elapsed := 0.
var source := ""
var pick_boxes: Array[Dictionary]=[]
var unfinished := CheckButton.new()
var sidebar := PanelContainer.new()
const FOREARM = preload("res://assets/animations/straight_pass_02.res")
var leg_grid := GridContainer.new()
var leg_label := Label.new()
var hand_leg_preview := false
var legs := 1
var forearm_frames := {}
const ForearmDrive = preload("res://scripts/reception_pass_drive.gd")
var incoming_speed := HSlider.new()
var speed_label := Label.new()

var upper_bones: Array[int]=[]

func _ready() -> void:
	add_child(pivot)
	pivot.add_child(player)
	player.animator.pause()
	for child in player.get_children():
		if child.get_script()==preload("res://scripts/player_direction_arrows.gd"): child.hide()
	for modifier in player.skeleton.get_children():
		if modifier is SkeletonModifier3D: modifier.active=false
	preload("res://scripts/practice_kit.gd").apply(player,false,2)
	ready_pose.assign(player.get_pose_author().baseline)
	var rig: Skeleton3D=player.skeleton
	var spine := rig.find_bone("spine_01")
	for bone in rig.get_bone_count():
		if bone==spine or rig.get_bone_parent(bone) in upper_bones:
			upper_bones.append(bone)
	var clip=preload("res://assets/animations/straight_pass_02.res")
	clasp=Save.sample_clip(player.skeleton,clip,clip.get_meta("contact_time"))
	add_child(Gym.new())
	Gym.light_gym(self)
	add_child(server)
	preload("res://scripts/practice_kit.gd").apply(server,false,5)
	add_child(feed)
	feed.configure(server,Vector3(0,.04,13.4),PI)
	feed.aim_ring.hide()
	feed.path_preview.hide()
	var square := PlaneMesh.new()
	square.size=Vector2(2,2)
	var paint := StandardMaterial3D.new()
	paint.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.albedo_color=Color(.25,.75,1.,.28)
	square.material=paint
	zone.mesh=square
	add_child(zone)
	zone.position=StorySession.game_options.get_value("reception_studio","zone",Vector3(0,.052,-2))
	pivot.position=StorySession.game_options.get_value("reception_studio","stance",zone.position)
	defenders.append(pivot)
	actors.append(player)
	for i in [1,2]:
		var receiver = preload("res://scripts/volleyball_player.gd").new()
		var anchor := Node3D.new()
		add_child(anchor)
		anchor.add_child(receiver)
		preload("res://scripts/practice_kit.gd").apply(receiver,false,2+i)
		anchor.position=StorySession.game_options.get_value("reception_studio","defender_%d"%i,Vector3(-2.9 if i==1 else 2.9,.052,-1))
		defenders.append(anchor)
		actors.append(receiver)
		receiver.animator.pause()
		for modifier in receiver.skeleton.get_children():
			if modifier is SkeletonModifier3D: modifier.active=false
		for bone in ready_pose.size(): receiver.skeleton.set_bone_pose(bone,receiver.get_pose_author().baseline[bone])
	var ring := TorusMesh.new()
	ring.inner_radius=.22
	ring.outer_radius=.29
	pass_marker.mesh=ring
	pass_marker.position=StorySession.game_options.get_value("reception_studio","pass_target",Vector3(1.7,.08,2.8))
	add_child(pass_marker)
	add_child(camera)
	camera.current=true
	position_camera()
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	layer.add_child(panel)
	style_panel(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal=Control.GROW_DIRECTION_BOTH
	panel.grow_vertical=Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom=-18
	var column := VBoxContainer.new()
	panel.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	button(row,"Previous",change_clip.bind(-1))
	row.add_child(label)
	button(row,"Next",change_clip.bind(1))
	mirror.text="Mirror"
	row.add_child(mirror)
	mirror.toggled.connect(func(on):
		defenders[receiving].scale.x=-1. if on else 1.
		draw_pose())
	button(row,"−1 frame",step.bind(-1))
	row.add_child(play_button)
	play_button.pressed.connect(toggle_play)
	button(row,"+1 frame",step.bind(1))
	button(row,"Back",func(): StorySession.drill_menu_category="Digging"; MenuPresentation.load_scene("res://scenes/drills.tscn"))
	layer.add_child(sidebar)
	sidebar.anchor_bottom=1.
	sidebar.offset_left=14
	sidebar.offset_top=58
	sidebar.offset_bottom=-106
	sidebar.offset_right=294
	style_panel(sidebar)
	var tiers := VBoxContainer.new()
	var controls_scroll := ScrollContainer.new()
	sidebar.add_child(controls_scroll)
	controls_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	controls_scroll.add_child(tiers)
	tiers.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tiers.add_theme_constant_override("separation",8)
	var torso_label := Label.new()
	torso_label.text="Reception studio"
	section_title(torso_label)
	tiers.add_child(torso_label)
	tiers.add_child(speed_label)
	tiers.add_child(incoming_speed)
	incoming_speed.max_value=140.
	incoming_speed.step=1.
	incoming_speed.value=StorySession.game_options.get_value("reception_studio","incoming_kmh",100.)
	incoming_speed.value_changed.connect(func(value):
		StorySession.game_options.set_value("reception_studio","incoming_kmh",value)
		StorySession.save_options()
		draw_pose())
	tiers.add_child(HSeparator.new())
	build_map(tiers)
	tiers.add_child(HSeparator.new())
	section_title(leg_label)
	tiers.add_child(leg_label)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	tiers.add_child(scroll)
	leg_grid.columns=5
	scroll.add_child(leg_grid)
	column.add_child(seek)
	seek.min_value=-85
	seek.step=1
	seek.value_changed.connect(func(value): playing=false; frame=value; draw_pose())
	refresh()
	update_leg_buttons()
	draw_pose()
	preview_cell()

func style_panel(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color=Color("132a39")
	style.border_color=Color("345661")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,12.)
	panel.add_theme_stylebox_override("panel",style)

func section_title(title: Label) -> void:
	title.add_theme_color_override("font_color",Color("76d5c9"))
	title.add_theme_font_size_override("font_size",20)

func button(row: Control,title: String,action: Callable) -> void:
	var b := Button.new()
	b.text=title
	row.add_child(b)
	b.pressed.connect(action)

func refresh() -> void:
	var content := FileAccess.get_file_as_string(Catalog)
	if source==content: return
	var entries=JSON.parse_string(content)
	if entries is Array and not entries.is_empty():
		clips=entries
		source=content
		for child in leg_grid.get_children():
			leg_grid.remove_child(child)
			child.queue_free()
		var group := ButtonGroup.new()
		for clip_index in range(-1,clips.size()):
			if clip_index>=0 and not Regions.movement(clips[clip_index]): continue
			var choice := Button.new()
			choice.text="Ready" if clip_index<0 else "%02d" % clips[clip_index].id
			choice.toggle_mode=true
			choice.button_group=group
			choice.custom_minimum_size=Vector2(43,34)
			choice.set_meta("clip",clip_index)
			choice.pressed.connect(select_legs.bind(clip_index))
			leg_grid.add_child(choice)
		index=mini(index,clips.size()-1)
		seek.max_value=clips[index].frames
		update_leg_buttons()

func change_clip(by: int) -> void:
	if hand_leg_preview or clips[index].kind=="overhead" or cell_action()==0:
		var next := legs
		for i in clips.size():
			next=posmod(next+by,clips.size())
			if Regions.movement(clips[next]):
				select_legs(next)
				break
		return
	index=posmod(index+by,clips.size())
	legs=index
	frame=seek.min_value
	update_leg_buttons()
	seek.max_value=clips[index].frames
	draw_pose()

func step(by: int) -> void:
	playing=false
	frame=clampf(roundf(frame)+by,seek.min_value,clips[index].frames)
	draw_pose()

func toggle_play() -> void:
	playing=not playing
	draw_pose()

func _process(delta: float) -> void:
	var pan := Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S))).normalized()
	if pan!=Vector2.ZERO:
		var forward := -camera.basis.z.slide(Vector3.UP).normalized()
		camera_offset+=(camera.basis.x*pan.x+forward*pan.y)*delta*4.
		position_camera()
	elapsed+=delta
	if elapsed>.5:
		elapsed=0.
		refresh()
	if playing:
		frame+=delta*60.
		if frame>=maxf(clips[index].frames,maxf(pass_end_frame,reset_end_frame))+1.:
			frame=seek.min_value
			pick_feed_point()
		draw_pose()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		var ray := camera.project_ray_origin(event.position)
		var direction := camera.project_ray_normal(event.position)
		var click: bool=event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed
		var floor_point=Plane(Vector3.UP,.052).intersects_ray(ray,direction)
		if click and not event.ctrl_pressed and floor_point!=null and floor_point.distance_to(pass_marker.position)<.42:
			dragging_target=true
			return
		if click and not event.ctrl_pressed and not place.button_pressed and floor_point!=null:
			var nearest := INF
			for i in defenders.size():
				var base := defenders[i].position
				var torso := base+Vector3.UP*.90
				var along := direction.dot(torso-ray)
				var gap := (ray+direction*along-torso).length()
				if along>0 and gap<.82 and gap<nearest:
					nearest=gap
					dragging=i
					drag_offset=base-floor_point
			if dragging>=0: return
		if place.button_pressed:
			hover.hide()
			var floor_hit=Plane(Vector3.UP,.052).intersects_ray(ray,direction)
			if click and floor_hit!=null:
				var inside: bool=absf(floor_hit.x-zone.position.x)<=1. and absf(floor_hit.z-zone.position.z)<=1.
				if not inside:
					zone.position=Vector3(clampf(floor_hit.x,-3.5,3.5),.052,clampf(floor_hit.z,-4.,3.))
				pivot.position= floor_hit if inside else zone.position
				lattice.position=pivot.position
				StorySession.game_options.set_value("reception_studio","zone",zone.position)
				StorySession.game_options.set_value("reception_studio","stance",pivot.position)
				StorySession.save_options()
				position_camera()
				draw_pose()
				return
		else:
			hover.hide()
			var nearest := INF
			var chosen := -1
			var address := cell
			var part := 0
			for i in defenders.size():
				var grid := grid_for(i)
				var local_ray := grid.to_local(ray)
				var end := grid.to_local(ray+direction*camera.far)
				for box in pick_boxes:
					if event.shift_pressed and box.address.z!=cell.z: continue
					var span := zone_interval(local_ray,end,box.bounds)
					if span.y<=span.x or span.x>=nearest: continue
					address=box.address
					part=box.part
					chosen=i
					nearest=span.x
			if chosen>=0:
				hover.global_position=grid_for(chosen).position+region_center(address,part)
				hover.scale=region_size(address,part)/CELL_SIZE
				hover_number.text=region_number(address,part)
				hover.show()
				if click and event.ctrl_pressed:
					activate_receiver(chosen)
					cell=address
					quadrant=part
					preview_cell()
					return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		yaw+=event.relative.x*.008
		elevation=clampf(elevation+event.relative.y*.005,-.1,1.1)
		position_camera()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		distance=clampf(distance+(-.25 if event.button_index==MOUSE_BUTTON_WHEEL_UP else .25),1.8,7.)
		position_camera()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT: step(-1)
			KEY_RIGHT: step(1)
			KEY_SPACE: toggle_play()
			KEY_M: mirror.button_pressed=not mirror.button_pressed

func grid_for(i: int) -> MeshInstance3D:
	return lattice if i==0 else other_grids[i-1]

func activate_receiver(i: int) -> void:
	if receiving==i: return
	sample_layer(-1,clips[index],0.)
	defenders[receiving].scale.x=1.
	receiving=i
	player=actors[i]
	ready_pose.assign(player.get_pose_author().baseline)
	clasp=Save.sample_clip(player.skeleton,FOREARM,FOREARM.get_meta("contact_time"))
	forearm_frames.clear()
	contact_key.clear()
	defenders[i].scale.x=-1. if mirror.button_pressed else 1.
	highlight.reparent(grid_for(i),false)

func _input(event: InputEvent) -> void:
	if dragging_target:
		if event is InputEventMouseMotion:
			var point=Plane(Vector3.UP,.08).intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
			if point!=null:
				pass_marker.position=Vector3(clampf(point.x,-4.5,4.5),.08,clampf(point.z,-5.,4.))
				draw_pose()
		elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
			dragging_target=false
			StorySession.game_options.set_value("reception_studio","pass_target",pass_marker.position)
			StorySession.save_options()
		get_viewport().set_input_as_handled()
		return
	if dragging<0: return
	if event is InputEventMouseMotion:
		var hit=Plane(Vector3.UP,.052).intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
		if hit!=null:
			var at: Vector3=hit+drag_offset
			defenders[dragging].position=Vector3(clampf(at.x,-4.5,4.5),.052,clampf(at.z,-5.,3.9))
			if dragging>0: other_grids[dragging-1].position=defenders[dragging].position
			if dragging==0:
				lattice.position=pivot.position
				zone.position=Vector3(clampf(at.x,-3.5,3.5),.052,clampf(at.z,-4.,3.))
				draw_pose()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		if dragging==0:
			StorySession.game_options.set_value("reception_studio","stance",pivot.position)
			StorySession.game_options.set_value("reception_studio","zone",zone.position)
		else:
			StorySession.game_options.set_value("reception_studio","defender_%d"%dragging,defenders[dragging].position)
		StorySession.save_options()
		dragging=-1
	get_viewport().set_input_as_handled()

func position_camera() -> void:
	var target := pivot.position+camera_offset+Vector3(0,.92,.15)
	camera.position=target+Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))*distance
	camera.look_at(target)

func draw_pose() -> void:
	var c: Dictionary=clips[index]
	if hand_leg_preview:
		c=c.duplicate()
		c.step_legs=0 if legs<0 else int(clips[legs].id)
		c.audition=true
	var f := clampf(roundf(frame),0.,c.frames)
	seek.set_value_no_signal(frame)
	label.text=" %02d / %02d     Frame %d / %d " % [c.id,clips.size(),mini(roundi(frame),int(c.frames)),c.frames]
	play_button.text="Pause" if playing else "Play"
	var aim := highlight.global_position+feed_offset
	var launch: Vector3=feed.preview_origin
	var full_duration := clampf(launch.distance_to(aim)/maxf(1.,incoming_speed.value/3.6),.48,1.25)
	feed_fraction=1.
	var rig: Skeleton3D=player.skeleton
	var head: Vector3=rig.to_global(player.get_pose_author().point(ready_pose,"Head"))-player.global_position+defenders[receiving].position
	var jumping: bool=c.kind=="overhead" and not c.has("step_legs") and (c.get("jump_set",false) or aim.y>head.y+.22)
	if jumping and cell_action()>0:
		var advance := clampf(head.z+.23-aim.z,0.,1.95)
		feed_fraction-=advance/maxf(1.,launch.z-aim.z)
	var target := launch.lerp(aim,feed_fraction)+Vector3.UP*6.*feed_fraction*(1.-feed_fraction)
	set_intercept=target
	var duration := full_duration*feed_fraction
	var lead_frames := (full_duration-duration)*60.
	var touch_frame: float=c.contact-lead_frames
	var signature := [index,legs,mirror.button_pressed,incoming_speed.value,source,cell,feed_offset,cell_action(),defenders[receiving].position]
	if signature!=contact_key:
		contact_key=signature
		sample_receiver(c,c.contact)
		var center := Vector3.ZERO
		for side in ["l","r"]:
			var wrist := rig.get_bone_global_pose(rig.find_bone("hand_"+side)).origin
			var elbow := rig.get_bone_global_pose(rig.find_bone("lowerarm_"+side)).origin
			center+=rig.to_global(wrist.lerp(elbow,.32))*.5
		contact_point=center+Vector3(0,.075,.075)
		if c.kind=="overhead": contact_point=HandPass.contact_center(player)
		reachable=(cell_action()>0 or hand_leg_preview) and contact_point.distance_to(target)<=(HAND_RADIUS if c.kind=="overhead" else .22)
	var missed: bool= frame>=touch_frame and (cell_action()>0 or hand_leg_preview) and not reachable
	miss_label.visible=missed
	if missed:
		var gap := contact_point.distance_to(target)
		miss_label.text="Miss · %d cm gap"%roundi(gap*100.)
		if playing and not miss_logged:
			print("studio_miss ",Time.get_datetime_string_from_system()," defender=",receiving+1," cell=",cell," region=",region_number(cell,quadrant)," assigned=",cell_action()," playing=",c.id," target=",target," contact=",contact_point," gap_m=",gap)
			miss_logged=true
	reset_end_frame=0.
	if c.kind=="overhead":
		sample_receiver(c,maxf(0.,frame+lead_frames))
	else:
		sample_receiver(c,clampf(frame+lead_frames,0.,c.frames) if lead_frames>0. else f)
	hand_volume.visible=hand_toggle.button_pressed and c.kind=="overhead" and (cell_action()>0 or hand_leg_preview)
	if hand_volume.visible: hand_volume.global_position=HandPass.contact_center(player)
	pass_end_frame=0.
	var seconds := (frame-touch_frame)/60.
	var serve_time := clampf(feed.contact_time()+seconds+duration,0.,feed.contact_time()+.42)
	feed.pose(serve_time)
	feed.ball.show()
	if ball_trail.visible: trail_mesh.clear_surfaces()
	if seconds < -duration: return
	var lift := sqrt(2.*9.81*pass_arc.value)
	var landing := (lift+sqrt(lift*lift+2.*9.81*maxf(0.,target.y-.145)))/9.81
	if reachable and seconds>0.:
		pass_end_frame=touch_frame+ceilf(landing*60.)+1.
	var point := flight_point(seconds,launch,target,duration,lift,landing)
	feed.ball.position=point
	feed.ball.visible=point.y>=.145
	if ball_trail.visible and seconds > -duration:
		draw_ball_trail(seconds,launch,target,duration,lift,landing)

func flight_point(t: float,launch: Vector3,target: Vector3,duration: float,lift: float,landing: float) -> Vector3:
	if reachable and t>0.:
		var point := target.lerp(Vector3(pass_marker.position.x,target.y,pass_marker.position.z),t/landing)
		point.y+=lift*t-4.905*t*t
		return point
	var u := (t+duration)/duration
	return launch.lerp(target,u)+Vector3.UP*6.*feed_fraction*feed_fraction*u*(1.-u)

func draw_ball_trail(seconds: float,launch: Vector3,target: Vector3,duration: float,lift: float,landing: float) -> void:
	var previous := launch
	var t := -duration
	var origin := grid_for(receiving).global_position+MAP_ORIGIN
	var bounds := AABB(origin,Vector3(MAP_MAX-MAP_MIN+Vector3i.ONE)*CELL_SIZE)
	var end_time := minf(seconds,0.) if reachable else seconds
	var started := false
	while t<end_time:
		var next_time := minf(end_time,t+1./60.)
		if t<0. and next_time>0.: next_time=0.
		var point := flight_point(next_time,launch,target,duration,lift,landing)
		var landed := point.y<.145
		if landed:
			point=previous.lerp(point,clampf((previous.y-.145)/maxf(.00001,previous.y-point.y),0.,1.))
		var interval := zone_interval(previous,point,bounds)
		if interval.y>interval.x:
			if not started:
				trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,trail_ink)
				started=true
			var entry := previous.lerp(point,interval.x)
			var exit_point := previous.lerp(point,interval.y)
			var width := (exit_point-entry).cross(camera.global_position-entry).normalized()*.018
			for vertex in [entry-width,entry+width,exit_point+width,entry-width,exit_point+width,exit_point-width]:
				trail_mesh.surface_add_vertex(vertex)
		if landed: break
		t=next_time
		previous=point
	if started: trail_mesh.surface_end()

func zone_interval(start: Vector3,finish: Vector3,bounds: AABB) -> Vector2:
	var interval := Vector2(0.,1.)
	var travel := finish-start
	for axis in 3:
		if is_zero_approx(travel[axis]):
			if start[axis]<bounds.position[axis] or start[axis]>bounds.end[axis]: return Vector2.ZERO
			continue
		var a := (bounds.position[axis]-start[axis])/travel[axis]
		var b := (bounds.end[axis]-start[axis])/travel[axis]
		interval.x=maxf(interval.x,minf(a,b))
		interval.y=minf(interval.y,maxf(a,b))
		if interval.x>=interval.y: return Vector2.ZERO
	return interval

func sample_receiver(c: Dictionary,f: float) -> void:
	if cell_action()==0 and not hand_leg_preview:
		sample_layer(-1,c,f)
		return
	if c.kind=="overhead":
		sample_layer(-1,c,f)
		var goal := set_intercept
		var offset := pass_marker.position-goal
		var lift := sqrt(2.*9.81*pass_arc.value)
		var flight := (lift+sqrt(lift*lift+2.*9.81*maxf(0.,goal.y-.145)))/9.81
		var push := (offset.slide(Vector3.UP)/flight+Vector3.UP*lift).normalized()
		var follow := (f-float(c.contact))/60.
		var load_weight := smoothstep(-HandPass.CPU_PREP_LEAD,0.,follow)
		var rig: Skeleton3D=player.skeleton
		var forehead := rig.to_global(rig.get_bone_global_pose(rig.find_bone("Head")).origin).y+.12
		var jump_set: bool=not c.has("step_legs") and (c.get("jump_set",false) or goal.y>forehead+.10)
		if jump_set:
			jump_to_set(goal,follow,c.get("approach_step",false))
			lean_for_hand_pass(goal,load_weight*(1.-smoothstep(.035,.28,follow)),deg_to_rad(5.))
		else:
			if c.get("audition",false):
				if legs>=0: audition_hand_legs(goal,follow)
			elif c.get("step_legs",0)==2:
				grounded_wide_set(goal,forehead,follow,c.get("ground_plant",false))
			else:
				pose_hand_pass_legs(goal,forehead,follow,int(c.get("step_legs",0)))
			var reach_weight := load_weight*(1.-smoothstep(.035,.28,follow))
			lean_for_hand_pass(goal,reach_weight)
		if follow<0.:
			HandPass.standing_set(player,goal,offset,push,follow,load_weight,Vector3.ZERO,jump_set)
		else:
			var delay := HandPass.RELEASE_TIME
			var extension := HandPass.release_extension(follow,delay)
			HandPass.apply(player,goal,HandPass.follow_weight(follow),push*.23*extension,
				HandPass.release_cushion(follow,delay),smoothstep(delay,delay+.10,follow),
				false,Vector3.ZERO,extension,offset,smoothstep(0.,delay,follow),true,
				smoothstep(0.,delay+HandPass.FRONT_WRIST_FOLLOW_TIME,follow),null,Vector3.ZERO,jump_set)
		return
	if not Regions.movement(c):
		sample_layer(index,c,f)
		return
	sample_layer(legs,c,f)
	var contact := float(FOREARM.get_meta("contact_time"))
	var time := remap(f,0.,c.contact,0.,contact) if f<=c.contact else remap(f,c.contact,c.get("source_end",c.frames),contact,FOREARM.length)
	var key := roundi(time*60.)
	if not forearm_frames.has(key):
		forearm_frames[key]=Save.sample_clip(player.skeleton,FOREARM,minf(key/60.,FOREARM.length))
	var settle: float=c.frames-3. if c.has("source_end") else c.frames
	var weight := smoothstep(0.,5.,f)*(1.-smoothstep(settle-6.,settle,f))
	for bone in upper_bones:
		player.skeleton.set_bone_pose(bone,ready_pose[bone].interpolate_with(forearm_frames[key][bone],weight))

	var bend := ForearmDrive.forearm_bend_degrees(incoming_speed.value/3.6)
	speed_label.text="Incoming %d km/h   ·   %.0f°" % [incoming_speed.value,bend]
	ForearmDrive.recoil_platform(player.skeleton,(f-float(c.contact))/60.,bend)

func lean_for_hand_pass(goal: Vector3, weight: float, limit := deg_to_rad(34.)) -> void:
	if weight<=0.: return
	var rig: Skeleton3D=player.skeleton
	var author=player.get_pose_author()
	var pose: Array[Transform3D]=[]
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var head: Vector3=author.point(pose,"Head")
	var reach := (rig.to_local(goal)-head-Vector3(0,.12,.20)).slide(Vector3.UP)
	if reach.length_squared()<.0001: return
	var axis := Vector3.UP.cross(reach).normalized()
	var lean := minf(limit,reach.length()*1.12)*weight
	for spine in ["spine_01","spine_02","spine_03"]:
		author.rotate_world(pose,spine,axis,lean/3.)
		var id := rig.find_bone(spine)
		rig.set_bone_pose(id,pose[id])

func jump_to_set(goal: Vector3, follow: float, approach_step := false) -> void:
	var rig: Skeleton3D=player.skeleton
	var head := rig.to_global(rig.get_bone_global_pose(rig.find_bone("Head")).origin)
	var pocket: Vector3=head+player.global_basis.z.normalized()*.23+Vector3.UP*.16
	var gap := goal-pocket
	var apex := clampf(gap.y+.10,.19,.76)
	# Allow enough flight time to cover the horizontal gap as well as the rise.
	var contact_rise := clampf(gap.y,.035,apex)
	var descent := sqrt(2.*(apex-contact_rise)/9.81)
	var lead := maxf(sqrt(2.*apex/9.81)+descent,minf(.52,gap.slide(Vector3.UP).length()/4.8))
	var upward_speed := contact_rise/lead+4.905*lead
	var half_air := upward_speed/9.81
	apex=upward_speed*upward_speed/(2.*9.81)
	var t := follow+lead
	var travel: Vector3=player.global_basis.inverse()*gap.slide(Vector3.UP)
	# Limit backward launch velocity so even the landing stays near takeoff.
	if travel.z<0.: travel.z=clampf(travel.z+.05,-.20*lead/(2.*half_air),0.)
	var fraction := clampf(t,0.,2.*half_air)/lead
	var landing := 2.*half_air-lead
	var recover := smoothstep(landing+.10,landing+.57,follow)
	var ground_step := (travel*.60).limit_length(.62) if approach_step else Vector3.ZERO
	var step_progress := smoothstep(-approach_plant.APPROACH_LOAD_TIME,0.,t)
	var offset := ground_step*step_progress+(travel-ground_step).limit_length(5.5*lead)*fraction
	player.position=offset
	player.position.y=maxf(0.,apex-4.905*(t-half_air)*(t-half_air))
	var load := smoothstep(-.32,-.085,t)*(1.-smoothstep(-.085,.07,t))
	var compression := clampf(contact_rise-gap.y,0.,.38)*smoothstep(-.16,0.,t)*(1.-recover)
	var cushion := smoothstep(landing,landing+.06,follow)*(1.-smoothstep(landing+.06,landing+.20,follow))
	bend_for_hand_pass(compression+.17*load+.10*cushion)
	if approach_step and t>=-approach_plant.APPROACH_LOAD_TIME and t<0.:
		sample_approach_plant(ground_step,t)
	# Hold the landing before the studio shuffles back for its next feed.
	var elapsed := follow-landing-.40
	var distance := offset.length()
	if elapsed<=0. or distance<.001: return
	var duration := maxf(.38,distance/1.15)
	var progress := clampf(elapsed/duration,0.,1.)
	player.position=offset*(1.-smoothstep(0.,1.,progress))
	reset_end_frame=frame+(duration-elapsed)*60.
	if progress>=1.: return
	sample_shuffle(-offset.normalized(),progress*maxi(1,roundi(duration*1.65)),smoothstep(0.,.16,progress)*(1.-smoothstep(.80,1.,progress)))

func sample_approach_plant(stride: Vector3, takeoff_time: float) -> void:
	var rig: Skeleton3D=player.skeleton
	var author=player.get_pose_author()
	var pose := ready_pose.duplicate()
	var pelvis := rig.find_bone("pelvis")
	pose[pelvis]=rig.get_bone_pose(pelvis)
	# Sample the attack's right plant and closing left step in takeoff-space.
	approach_plant.approach_plant=true
	approach_plant.incoming_plant_speed=1.
	approach_plant.elapsed=takeoff_time+approach_plant.APPROACH_LOAD_TIME
	for side in ["r","l"]:
		approach_plant.plant_legs[side]=Transform3D.IDENTITY
	approach_plant.right_plant=stride
	approach_plant.left_plant=stride
	for side in ["r","l"]:
		var foot: Transform3D=author.feet[side]
		var displacement: Vector3=approach_plant.attack_plant_foot(side)-player.position
		var target: Vector3=foot.origin+rig.global_basis.inverse()*(player.global_basis*displacement)
		var pole := Vector3(.15 if side=="l" else -.15,.08,1.)
		author.limb(pose,"thigh_"+side,"calf_"+side,"foot_"+side,target,pole,1.,162.,true)
		author.set_world_basis(pose,"foot_"+side,foot.basis)
		for joint in ["thigh_","calf_","foot_"]:
			var bone := rig.find_bone(joint+side)
			rig.set_bone_pose(bone,pose[bone])

func sample_shuffle(direction: Vector3, phase: float, weight: float) -> void:
	if not shuffle_by_actor.has(player):
		shuffle_by_actor[player]=preload("res://scripts/directional_footwork.gd").new(player)
	var steps=shuffle_by_actor[player]
	# Sample from replay time so stepping backwards reproduces the same feet.
	steps.phase=phase
	steps.travel=direction
	steps.weight=weight
	steps.step(steps.travel,0.,1.,true,true)

func grounded_wide_set(goal: Vector3, forehead: float, follow: float, plant: bool) -> void:
	var stride := Vector3.ZERO
	var settle := -.30
	if plant:
		var travel: Vector3=player.to_local(goal).slide(Vector3.UP)-Vector3.BACK*.23
		stride=(travel*.72).limit_length(.92)
		var phase := follow-settle
		player.position=stride*smoothstep(-approach_plant.APPROACH_LOAD_TIME,0.,phase)
		if phase<0.:
			if phase>=-approach_plant.APPROACH_LOAD_TIME:
				bend_for_hand_pass(.12*sin(PI*smoothstep(-approach_plant.APPROACH_LOAD_TIME,0.,phase)))
				sample_approach_plant(stride,phase)
			return
	var weight := smoothstep(settle if plant else -.55,-.02,follow)*(1.-smoothstep(.09,.38,follow))
	if weight>0.:
		var delta_to_ball: Vector3=player.to_local(goal).slide(Vector3.UP)-Vector3.BACK*.23
		var recipe: Dictionary=clips[1].duplicate()
		var scale_m: float=player.skeleton.global_basis.x.length()
		var reach := delta_to_ball.limit_length(1.1)
		recipe.side=reach.x/scale_m
		recipe.forward=reach.z*1.8/scale_m
		recipe.drop=clampf(forehead-goal.y,0.,float(recipe.drop)*scale_m)/scale_m
		var pose := ready_pose.duplicate()
		Regions.legs(player,pose,recipe,weight)
		for joint in ["pelvis","thigh_l","calf_l","foot_l","thigh_r","calf_r","foot_r"]:
			var bone: int=player.skeleton.find_bone(joint)
			player.skeleton.set_bone_pose(bone,pose[bone])
	if plant and follow>.4:
		var duration := maxf(.38,stride.length()/1.15)
		var progress := clampf((follow-.4)/duration,0.,1.)
		player.position=stride*(1.-smoothstep(0.,1.,progress))
		if progress<1.:
			sample_shuffle(-stride.normalized(),progress*maxi(1,roundi(duration*1.65)),sin(PI*progress))

func pose_hand_pass_legs(goal: Vector3, standing_height: float, follow: float, step_legs: int) -> void:
	var drop := standing_height-goal.y
	if step_legs==0 and drop < -.10:
		var height := clampf(-drop-.06,.04,.38)
		var half_flight := sqrt(2.*height/9.81)
		var rise := maxf(0.,height-4.905*follow*follow)
		var drift: Vector3=player.to_local(goal).slide(Vector3.UP)-Vector3(0,0,.20)
		player.position+=drift.limit_length(.32)*(rise/height)
		player.position.y=rise
		var before := smoothstep(-half_flight-.19,-half_flight-.09,follow)*(1.-smoothstep(-half_flight-.09,-half_flight,follow))
		var after := smoothstep(half_flight,half_flight+.08,follow)*(1.-smoothstep(half_flight+.08,half_flight+.22,follow))
		bend_for_hand_pass(.10*(before+after))
		return
	var weight := smoothstep(-.36,-.025,follow)*(1.-smoothstep(.035,.32,follow))
	if weight<=0.: return
	var lateral: float=player.to_local(goal).x
	var recipe_id := 6 if drop>.26 else 4
	if drop>.12 and absf(lateral)>.20: recipe_id=7
	if step_legs>0: recipe_id=step_legs
	var recipe: Dictionary=clips[recipe_id-1].duplicate()
	var scale_m: float=player.skeleton.global_basis.x.length()
	recipe.side=minf(absf(lateral)*.55,.15)/scale_m if recipe_id==7 else 0.
	var depth_offset: float=player.to_local(goal).z-.20
	recipe.forward=clampf(depth_offset,-.65,.50)/scale_m
	recipe.drop=minf(float(recipe.drop)+.15,maxf(0.,drop)/scale_m)
	if step_legs>0:
		recipe.side=clampf(absf(lateral)*.8,.015,.38)/scale_m
		recipe.forward=clampf(depth_offset*2.,.12,1.35)/scale_m
	var pose := ready_pose.duplicate()
	Regions.legs(player,pose,recipe,weight,lateral<0.)
	for joint in ["pelvis","thigh_l","calf_l","foot_l","thigh_r","calf_r","foot_r"]:
		var bone: int=player.skeleton.find_bone(joint)
		player.skeleton.set_bone_pose(bone,pose[bone])

func audition_hand_legs(goal: Vector3, follow: float) -> void:
	var clip: Dictionary=clips[legs]
	var target: Vector3=player.to_local(goal).slide(Vector3.UP)
	var direction := target.normalized()
	var stride := Vector2(clip.side,clip.forward).length()
	var recipe := clip.duplicate()
	recipe.side=direction.x*stride
	recipe.forward=direction.z*stride
	var weight := smoothstep(-float(clip.contact)/60.,0.,follow)*(1.-smoothstep(.10,float(clip.frames-clip.contact)/60.,follow))
	var pose := ready_pose.duplicate()
	Regions.legs(player,pose,recipe,weight)
	player.position.y=float(clip.get("jump",0.))*weight
	for joint in ["pelvis","thigh_l","calf_l","foot_l","thigh_r","calf_r","foot_r"]:
		var bone: int=player.skeleton.find_bone(joint)
		player.skeleton.set_bone_pose(bone,pose[bone])

func bend_for_hand_pass(depth: float) -> void:
	if depth<=.00001: return
	var rig: Skeleton3D=player.skeleton
	var author=player.get_pose_author()
	var pose := ready_pose.duplicate()
	var pelvis := rig.find_bone("pelvis")
	var parent: Transform3D=author.world_pose(pose,rig.get_bone_parent(pelvis))
	pose[pelvis].origin+=parent.basis.inverse()*rig.global_basis.inverse()*(Vector3.DOWN*depth)
	rig.set_bone_pose(pelvis,pose[pelvis])
	for side in ["l","r"]:
		var hip: String = "thigh_"+side
		var knee: String = "calf_"+side
		var ankle: String = "foot_"+side
		var foot: Transform3D=author.world_pose(ready_pose,rig.find_bone(ankle))
		var axis: Vector3=(foot.origin-author.point(ready_pose,hip)).normalized()
		var pole: Vector3=(author.point(ready_pose,knee)-author.point(ready_pose,hip)).slide(axis).normalized()
		author.limb(pose,hip,knee,ankle,foot.origin,pole)
		var ankle_id := rig.find_bone(ankle)
		var shin: Transform3D=author.world_pose(pose,rig.get_bone_parent(ankle_id))
		pose[ankle_id]=shin.affine_inverse()*foot
		for joint in [hip,knee,ankle]:
			var bone := rig.find_bone(joint)
			rig.set_bone_pose(bone,pose[bone])

func select_legs(which: int) -> void:
	if hand_leg_preview or clips[index].kind=="overhead" or cell_action()==0:
		if clips[index].kind!="overhead":
			for i in clips.size():
				if clips[i].kind=="overhead":
					index=i
					break
		hand_leg_preview=true
		legs=which
		frame=seek.min_value
		playing=true
		seek.max_value=clips[index].frames
		contact_key.clear()
		update_leg_buttons()
		draw_pose()
		return
	legs=which
	if which>=0:
		var phase := frame/float(clips[index].frames)
		index=which
		frame=phase*float(clips[index].frames)
		seek.max_value=clips[index].frames
	update_leg_buttons()
	draw_pose()

func update_leg_buttons() -> void:
	leg_label.text="Legs   "+("Ready" if legs<0 else "#%02d" % clips[legs].id)
	for choice in leg_grid.get_children():
		choice.set_pressed_no_signal(choice.get_meta("clip")==legs)

func sample_layer(which: int, timeline: Dictionary, f: float) -> void:
	if which<0:
		player.position=Vector3.ZERO
		player.rotation.y=0.
		for bone in ready_pose.size(): player.skeleton.set_bone_pose(bone,ready_pose[bone])
		return
	var c: Dictionary=clips[which]
	if which!=index:
		if f<=timeline.contact: f=f*c.contact/timeline.contact
		else: f=remap(f,timeline.contact,timeline.frames,c.contact,c.frames)
	var source_end: float=minf(c.get("source_end",c.frames),c.frames)
	var weight := smoothstep(5.,c.contact,f)*(1.-smoothstep(c.contact+6.,source_end-8.,f))
	if weight<=0.:
		player.position=Vector3.ZERO
		player.rotation.y=0.
		for bone in ready_pose.size(): player.skeleton.set_bone_pose(bone,ready_pose[bone])
		return
	var author=player.get_pose_author()
	var rig: Skeleton3D=player.skeleton
	player.position=Vector3.ZERO
	player.rotation.y=0.
	if c.kind in ["dive","wide_dive","pancake"] and weight>.0001:
		var dir := Vector3(c.side,0,c.forward).normalized()
		var t: float = Dive.WINDUP*clampf((f-5.)/(c.contact-5.),0.,1.)+maxf(0.,f-c.contact)/(c.frames-c.contact-8.)*(Dive.DURATION-Dive.WINDUP)
		player.pose_reception_dive(ready_pose,clasp,Vector3.ZERO,dir,t,dir*(c.forward+.55)+Vector3.UP*.30,Dive.WINDUP+.05,c.kind=="pancake",c.forward+.25,true,"r" if c.kind=="wide_dive" else "")
		var recovery := smoothstep(c.frames-32.,c.frames-8.,f)
		player.position*=1.-recovery
		player.rotation.y*=1.-recovery
		for bone in ready_pose.size():
			rig.set_bone_pose(bone,rig.get_bone_pose(bone).interpolate_with(ready_pose[bone],maxf(recovery,1.-smoothstep(5.,15.,f))))
		return
	var pose: Array=ready_pose.duplicate()
	Regions.legs(player,pose,c,weight)
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,deg_to_rad(c.lean)*weight*.65)
	author.rotate_world(pose,"spine_03",Vector3.RIGHT,deg_to_rad(c.lean)*weight*.35)
	author.rotate_world(pose,"spine_02",Vector3.BACK,-c.side*.36*weight)
	var chest: Vector3=author.point(pose,"spine_03")
	player.position.y=float(c.get("jump",0.))*weight
	for bone in pose.size(): rig.set_bone_pose(bone,pose[bone])

func build_map(tiers: VBoxContainer) -> void:
	trail_ink.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_ink.cull_mode=BaseMaterial3D.CULL_DISABLED
	trail_ink.albedo_color=Color("#ff2626")
	ball_trail.mesh=trail_mesh
	ball_trail.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball_trail)
	var title := Label.new()
	title.text="Contact map"
	section_title(title)
	tiers.add_child(title)
	unfinished.text="Unassigned only"
	unfinished.button_pressed=StorySession.game_options.get_value("reception_studio","unassigned_only",false)
	tiers.add_child(unfinished)
	unfinished.toggled.connect(func(on):
		StorySession.game_options.set_value("reception_studio","unassigned_only",on)
		StorySession.save_options()
		rebuild_colors()
		update_region())
	var toggle_trail := CheckButton.new()
	toggle_trail.text="Ball trail"
	toggle_trail.button_pressed=StorySession.game_options.get_value("reception_studio","ball_trail",true)
	ball_trail.visible=toggle_trail.button_pressed
	tiers.add_child(toggle_trail)
	toggle_trail.toggled.connect(func(on):
		ball_trail.visible=on
		StorySession.game_options.set_value("reception_studio","ball_trail",on)
		StorySession.save_options()
		draw_pose())
	var sphere := SphereMesh.new()
	sphere.radius=HAND_RADIUS
	sphere.height=2.*HAND_RADIUS
	var ink := StandardMaterial3D.new()
	ink.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	ink.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color=Color(.1,1.,.65,.25)
	sphere.material=ink
	hand_volume.mesh=sphere
	hand_volume.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hand_volume)
	hand_toggle.text="Hand hitbox"
	hand_toggle.button_pressed=StorySession.game_options.get_value("reception_studio","hand_hitbox",false)
	tiers.add_child(hand_toggle)
	hand_toggle.toggled.connect(func(on):
		StorySession.game_options.set_value("reception_studio","hand_hitbox",on)
		StorySession.save_options()
		draw_pose())
	place.text="Place ready zone"
	tiers.add_child(place)
	var caption := Label.new()
	pass_arc.min_value=.25
	pass_arc.max_value=4.
	pass_arc.step=.05
	pass_arc.value=StorySession.game_options.get_value("reception_studio","pass_arc",1.5)
	caption.text="Pass rise  %.2f m"%pass_arc.value
	tiers.add_child(caption)
	tiers.add_child(pass_arc)
	pass_arc.value_changed.connect(func(value):
		caption.text="Pass rise  %.2f m"%value
		StorySession.game_options.set_value("reception_studio","pass_arc",value)
		StorySession.save_options()
		draw_pose())
	var editor := VBoxContainer.new()
	tiers.add_child(editor)
	var depth := HBoxContainer.new()
	editor.add_child(depth)
	button(depth,"‹",change_depth.bind(-1))
	depth.add_child(depth_label)
	button(depth,"›",change_depth.bind(1))
	editor.add_child(region_label)
	miss_label.modulate=Color("#ff897c")
	editor.add_child(miss_label)
	button(editor,"Assign current action",assign_region)
	rebuild_colors()
	add_child(lattice)
	for i in range(1,defenders.size()):
		var grid := MeshInstance3D.new()
		add_child(grid)
		grid.mesh=lattice.mesh
		grid.position=defenders[i].position
		other_grids.append(grid)
	var box := BoxMesh.new()
	box.size=CELL_SIZE
	var tint := StandardMaterial3D.new()
	tint.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.albedo_color=Color(1.,.72,.1,.26)
	box.material=tint
	highlight.mesh=box
	lattice.add_child(highlight)
	hover.mesh=box
	var hover_style := tint.duplicate() as StandardMaterial3D
	hover_style.albedo_color=Color(.12,.85,1.,.38)
	hover.material_override=hover_style
	lattice.add_child(hover)
	hover.add_child(hover_number)
	hover_number.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	hover_number.font_size=32
	hover_number.no_depth_test=true
	hover.hide()
	lattice.position=pivot.position
	update_region()

func change_depth(by: int) -> void:
	cell.z=posmod(cell.z-MAP_MIN.z+by,3)+MAP_MIN.z
	preview_cell()

func cell_action() -> int:
	return assigned_action(cell,quadrant)

func is_subdivided(address: Vector3i) -> bool:
	return address==HEAD_CELL or address==Vector3i(1,2,2)

func depth_split(address: Vector3i) -> bool:
	return address==Vector3i(1,2,2)

func region_suffix(address: Vector3i,part: int) -> String:
	if depth_split(address):
		return ".%d.%s" % [part%4+1,"front" if part>=4 else "back"]
	return "."+str(part+1) if is_subdivided(address) else ""

func region_number(address: Vector3i,part: int) -> String:
	return str(1+address.x+3*address.y+9*address.z)+region_suffix(address,part)

func region_size(address: Vector3i,part: int) -> Vector3:
	if depth_split(address): return CELL_SIZE*Vector3(.5,.5,.5)
	return CELL_SIZE*Vector3(.5,.5,1.) if is_subdivided(address) else CELL_SIZE

func region_center(address: Vector3i,part: int,subdivide := true) -> Vector3:
	var center := MAP_ORIGIN+(Vector3(address)+Vector3.ONE*.5)*CELL_SIZE
	if is_subdivided(address) and subdivide:
		var upper := part%4<2
		center+=Vector3(-.25 if part%2==0 else .25,.25 if upper else -.25,0.)*CELL_SIZE
		if depth_split(address):
			center.z+=(.25 if part>=4 else -.25)*CELL_SIZE.z
	return center

func assignment_key(address: Vector3i,part: int) -> String:
	return Regions.key(address)+region_suffix(address,part)

func assigned_action(address: Vector3i,part: int) -> int:
	var child_key := assignment_key(address,part)
	if is_subdivided(address):
		if StorySession.game_options.has_section_key("studio_three_rows",child_key):
			return int(StorySession.game_options.get_value("studio_three_rows",child_key))
		if depth_split(address):
			if part<2: return 79
			var parent_key := Regions.key(address)+"."+str(part%4+1)
			if part%4<2:
				var parent_action := int(StorySession.game_options.get_value("studio_three_rows",parent_key,78))
				return 80 if parent_action==78 else parent_action
			if StorySession.game_options.has_section_key("studio_three_rows",parent_key):
				return int(StorySession.game_options.get_value("studio_three_rows",parent_key))
			return 82 if part>=4 else 81
		if address==HEAD_CELL and part>=2: return 0
	var key := Regions.key(address)
	if StorySession.game_options.has_section_key("studio_three_rows",key):
		return int(StorySession.game_options.get_value("studio_three_rows",key))
	if address.y==2 and address.z==2 and address.x!=1: return 80
	if address.y==2 and address.z==0: return 78
	if address.y==1: return 0
	var previous := Vector3i(address.x,0 if address.y==0 else 1,address.z)
	var default_action := 10 if previous==Vector3i(1,1,1) else 0
	return int(StorySession.game_options.get_value("dig_regions",Regions.key(previous),default_action))

func pick_feed_point() -> void:
	miss_logged=false
	var half := region_size(cell,quadrant)*.5
	var bottom := maxf(-half.y,.145-highlight.global_position.y)
	feed_offset=Vector3(randf_range(-half.x,half.x),randf_range(bottom,half.y),randf_range(-half.z,half.z))

func preview_cell() -> void:
	hand_leg_preview=false
	contact_key.clear()
	update_region()
	pick_feed_point()
	var id := cell_action()
	for i in clips.size():
		if int(clips[i].id)==id:
			index=i
			legs=i
			if clips[i].kind=="overhead":
				var saved: int=StorySession.game_options.get_value("studio_hand_legs",assignment_key(cell,quadrant),-2)
				if saved>=-1 and saved<clips.size():
					legs=saved
					hand_leg_preview=true
			seek.max_value=clips[index].frames
			update_leg_buttons()
			if cell.x!=1:
				mirror.button_pressed=(cell.x<1)!=(float(clips[i].side)<0.)
			break
	
	frame=seek.min_value
	playing=true
	draw_pose()

func update_region() -> void:
	depth_label.text=["Back","Body","Front"][cell.z-MAP_MIN.z]
	var id := cell_action()
	highlight.visible=not unfinished.button_pressed or id==0
	region_label.text="#%s · %s %s - %s" % [region_number(cell,quadrant),HEIGHTS[cell.y],WIDTHS[cell.x-MAP_MIN.x],"Unassigned" if id==0 else "Action #%02d"%id]
	highlight.scale=region_size(cell,quadrant)/CELL_SIZE
	highlight.position=region_center(cell,quadrant)

func assign_region() -> void:
	var id: int=0 if legs<0 else clips[legs].id
	if hand_leg_preview:
		id=clips[index].id
		StorySession.game_options.set_value("studio_hand_legs",assignment_key(cell,quadrant),legs)
	StorySession.game_options.set_value("studio_three_rows",assignment_key(cell,quadrant),id)
	StorySession.save_options()
	rebuild_colors()
	preview_cell()

func rebuild_colors() -> void:
	var mesh := ImmediateMesh.new()
	var ink := StandardMaterial3D.new()
	ink.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.vertex_color_use_as_albedo=true
	pick_boxes.clear()
	hover.hide()
	for x in range(MAP_MIN.x,MAP_MAX.x+1):
		for y in range(MAP_MAX.y+1):
			for z in range(MAP_MIN.z,MAP_MAX.z+1):
				var address := Vector3i(x,y,z)
				var count := 8 if depth_split(address) else (4 if is_subdivided(address) else 1)
				for part in count:
					var size := region_size(address,part)
					var assigned := assigned_action(address,part)>0
					if assigned and unfinished.button_pressed: continue
					if pick_boxes.is_empty(): mesh.surface_begin(Mesh.PRIMITIVE_LINES,ink)
					var color := Color("#ae2839") if assigned else Color("#2153a4")
					var center := region_center(address,part)
					pick_boxes.append({"address":address,"part":part,"bounds":AABB(center-size*.5,size)})
					for axis in 3:
						for i in [-1,1]:
							for j in [-1,1]:
								var corner := Vector3.ZERO
								corner[axis]=-1
								corner[(axis+1)%3]=i
								corner[(axis+2)%3]=j
								mesh.surface_set_color(color)
								mesh.surface_add_vertex(center+corner*size*.48)
								corner[axis]=1
								mesh.surface_set_color(color)
								mesh.surface_add_vertex(center+corner*size*.48)
	if not pick_boxes.is_empty(): mesh.surface_end()
	lattice.mesh=mesh
	for grid in other_grids: grid.mesh=mesh
