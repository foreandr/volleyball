extends "res://scripts/mapped_reception.gd"

var cell := Vector3i(1,1,1)
var quadrant := 0
var hover_number := Label3D.new()
const WIDTHS := ["Right","Center","Left"]
const HEIGHTS := ["Low","Mid","High"]
const Gym = preload("res://scripts/tryout_gym.gd")
const SERVES := preload("res://scripts/serving_camp.gd").TECHNIQUES
const SERVE_NAMES := ["Spin","Jump float","Standing float","Underhand"]
var feed_curve := 0.0
var serve_type := 2
var serve_from := Vector3(0,.04,13.4)
const FeedBase = preload("res://scripts/underhand_serve.gd")
var feed: FeedBase
var server = preload("res://scripts/volleyball_player.gd").new()
var zone := MeshInstance3D.new()
var hover := MeshInstance3D.new()
var actors: Array[Node3D]=[]
var place := CheckButton.new()
var dragging := -1
var drag_offset := Vector3.ZERO
var pass_marker := MeshInstance3D.new()
var dragging_target := false
var camera_dirty := false
var camera_offset := Vector3.ZERO
var other_grids: Array[MeshInstance3D]=[]
var pass_arc := HSlider.new()
var feed_offset := Vector3.ZERO
# Local bone endpoints and world-space capsule radii used for both contact and display.
var arm_volumes: Array[MeshInstance3D]=[]
var hand_volume := MeshInstance3D.new()
var hand_toggle := CheckButton.new()
var contact_point := Vector3.ZERO
var timing_display := preload("res://scripts/tryout_player_ring.gd").new()
var cpu_release_offset := 0.
var closest_surface_gap := 0.
var actual_fraction := 1.
var contact_key := []
var route_key := []
var routed_fraction := 1.
var routed_region := Vector4i(-1,-1,-1,-1)
var flight_boxes: Array[Dictionary]=[]
var crossing := MeshInstance3D.new()
var feed_fraction := 1.
var ball_trail := MeshInstance3D.new()
var trail_mesh := ImmediateMesh.new()
var trail_ink := StandardMaterial3D.new()
var incoming_floor_fraction := 1.
var pass_end_frame := 0.
var reachable := false
var lattice := MeshInstance3D.new()
var highlight := MeshInstance3D.new()
var miss_label := Label.new()
var miss_logged := false
var foot_choice := Button.new()
var region_label := Label.new()
var depth_label := Label.new()
const Catalog := "res://assets/reception_studio.json"
var pivot := Node3D.new()
var camera := Camera3D.new()
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
var line_read_error := 0.
var leave_feed := false
var random_feeds := CheckButton.new()
var selected_only := CheckButton.new()
var unfinished := CheckButton.new()
var sidebar := PanelContainer.new()
var leg_grid := GridContainer.new()
var leg_label := Label.new()
var forearm_preview := false
var hand_leg_preview := false
var incoming_speed := HSlider.new()
var speed_label := Label.new()


func _ready() -> void:
	player=preload("res://scripts/volleyball_player.gd").new()
	add_child(timing_display)
	timing_display.hide()
	timing_display.set_process(false)
	add_child(pivot)
	pivot.add_child(player)
	player.animator.pause()
	for child in player.get_children():
		if child.get_script()==preload("res://scripts/player_direction_arrows.gd"): child.hide()
	for modifier in player.skeleton.get_children():
		if modifier is SkeletonModifier3D: modifier.active=false
	preload("res://scripts/practice_kit.gd").apply(player,false,2)
	bind_receiver(player)
	var gym := Gym.new()
	add_child(gym)
	gym.seat_teammates(create_spectator)
	Gym.light_gym(self)
	add_child(server)
	preload("res://scripts/practice_kit.gd").apply(server,false,5)
	serve_type=clampi(StorySession.game_options.get_value("reception_studio","serve_type",2),0,3)
	serve_from=StorySession.game_options.get_value("reception_studio","serve_from",serve_from)
	configure_feed()
	var square := PlaneMesh.new()
	square.size=Vector2(2,2)
	var paint := StandardMaterial3D.new()
	paint.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.albedo_color=Color(.25,.75,1.,.28)
	square.material=paint
	zone.mesh=square
	add_child(zone)
	zone.position=StorySession.game_options.get_value("reception_studio","zone",DEFAULT_STANCES[0])
	pivot.position=StorySession.game_options.get_value("reception_studio","stance",zone.position)
	defenders.append(pivot)
	actors.append(player)
	for i in [1,2]:
		var receiver = preload("res://scripts/volleyball_player.gd").new()
		var anchor := Node3D.new()
		add_child(anchor)
		anchor.add_child(receiver)
		preload("res://scripts/practice_kit.gd").apply(receiver,false,2+i)
		anchor.position=StorySession.game_options.get_value("reception_studio","defender_%d"%i,DEFAULT_STANCES[i])
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
	var view: Vector3=StorySession.game_options.get_value("reception_studio","camera_view",Vector3(yaw,elevation,distance))
	yaw=view.x
	elevation=view.y
	distance=view.z
	camera_offset=StorySession.game_options.get_value("reception_studio","camera_offset",camera_offset)
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
		StorySession.game_options.set_value("studio_mirror",assignment_key(cell,quadrant),on)
		StorySession.save_options()
		defenders[receiving].scale.x=-1. if on else 1.
		draw_pose())
	button(row,"-1 frame",step.bind(-1))
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
	var serve_row := HBoxContainer.new()
	column.add_child(serve_row)
	random_feeds.text="Random assigned boxes"
	random_feeds.button_pressed=StorySession.game_options.get_value("reception_studio","random_assigned",false)
	serve_row.add_child(random_feeds)
	random_feeds.toggled.connect(func(on):
		if on:
			save_selection()
			next_assigned_feed()
		else:
			restore_selection()
		StorySession.game_options.set_value("reception_studio","random_assigned",on)
		StorySession.save_options())
	var types := OptionButton.new()
	for title in SERVE_NAMES: types.add_item(title)
	types.select(serve_type)
	serve_row.add_child(types)
	types.item_selected.connect(func(i):
		serve_type=i
		configure_feed()
		save_feed())
	serve_row.add_child(speed_label)
	serve_row.add_child(incoming_speed)
	incoming_speed.custom_minimum_size.x=115
	incoming_speed.min_value=25.
	incoming_speed.max_value=140.
	incoming_speed.step=1.
	incoming_speed.value=StorySession.game_options.get_value("reception_studio","incoming_kmh",100.)
	incoming_speed.value_changed.connect(func(value):
		StorySession.game_options.set_value("reception_studio","incoming_kmh",value)
		StorySession.save_options()
		draw_pose())
	for axis in [0,2]:
		var caption := Label.new()
		caption.text="Server X" if axis==0 else "Server Z"
		serve_row.add_child(caption)
		var coord := SpinBox.new()
		coord.min_value=-5.5 if axis==0 else 12.5
		coord.max_value=5.5 if axis==0 else 19.
		coord.step=.1
		coord.suffix="m"
		coord.value=serve_from[axis]
		serve_row.add_child(coord)
		coord.value_changed.connect(func(value):
			serve_from[axis]=value
			feed.serve_start=serve_from
			feed.reset()
			save_feed())
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
	seek.min_value=0.
	seek.step=1
	seek.value_changed.connect(func(value): playing=false; frame=value; draw_pose())
	refresh()
	update_leg_buttons()
	restore_selection()
	if random_feeds.button_pressed: next_assigned_feed()

func restore_selection() -> void:
	var selection: Dictionary=StorySession.game_options.get_value("reception_studio","selection",{})
	cell=Vector3i(selection.get("cell",cell)).clamp(MAP_MIN,MAP_MAX)
	var part := int(selection.get("part",0))
	if cell==REGION_23:
		cell=REGION_22
		part=0 if part<2 else 1
	quadrant=clampi(part,0,region_parts(cell)-1)
	activate_receiver(0)
	preview_cell()

func create_spectator(at: Vector3,color: String) -> Node3D:
	var viewer := preload("res://scripts/volleyball_player.gd").new()
	viewer.team_color=Color(color)
	viewer.position=at
	add_child(viewer)
	viewer.get_node("DirectionArrows").hide()
	viewer.animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return viewer

func configure_feed() -> void:
	if is_instance_valid(feed): feed.stop()
	feed=SERVES[serve_type].new()
	add_child(feed)
	feed.configure(server,serve_from,PI)
	feed.aim_ring.hide()
	feed.path_preview.hide()

func save_feed() -> void:
	seek.min_value=0.
	StorySession.game_options.set_value("reception_studio","serve_type",serve_type)
	StorySession.game_options.set_value("reception_studio","serve_from",serve_from)
	StorySession.save_options()
	frame=seek.min_value
	draw_pose()

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
	draw_pose()

func step(by: int) -> void:
	playing=false
	frame=clampf(roundf(frame)+by,seek.min_value,seek.max_value)
	draw_pose()

func toggle_play() -> void:
	playing=not playing
	draw_pose()

func _process(delta: float) -> void:
	var pan := Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S))).normalized()
	if pan!=Vector2.ZERO:
		var forward := -camera.basis.z.slide(Vector3.UP).normalized()
		camera_offset+=(camera.basis.x*pan.x+forward*pan.y)*delta*4.
		camera_dirty=true
		position_camera()
	elapsed+=delta
	if elapsed>.5:
		elapsed=0.
		save_camera_view()
		refresh()
	if playing:
		if frame>=pass_end_frame and pass_end_frame>0.:
			frame=seek.min_value
			if random_feeds.button_pressed:
				next_assigned_feed()
				return
			pick_feed_point()
		else:
			frame=minf(frame+delta*60.,pass_end_frame)
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
					random_feeds.button_pressed=false
					activate_receiver(0)
					cell=address
					quadrant=part
					save_selection()
					preview_cell()
					return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		yaw+=event.relative.x*.008
		elevation=clampf(elevation+event.relative.y*.005,-.1,1.1)
		camera_dirty=true
		position_camera()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		distance=clampf(distance+(-.25 if event.button_index==MOUSE_BUTTON_WHEEL_UP else .25),1.8,7.)
		camera_dirty=true
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

func save_camera_view() -> void:
	if not camera_dirty: return
	camera_dirty=false
	StorySession.game_options.set_value("reception_studio","camera_view",Vector3(yaw,elevation,distance))
	StorySession.game_options.set_value("reception_studio","camera_offset",camera_offset)
	StorySession.save_options()

func _exit_tree() -> void:
	save_camera_view()

func position_camera() -> void:
	var target := pivot.position+camera_offset+Vector3(0,.92,.15)
	camera.position=target+Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))*distance
	camera.look_at(target)

static func serve_curve(launch: Vector3,aim: Vector3,duration: float) -> float:
	# u=1 is the requested airborne contact. Gravity bends a slower feed more.
	var curve := maxf(.01,4.905*duration*duration)
	var travel := aim-launch
	if travel.z>=-.001: return curve
	var net_u := (4.-launch.z)/travel.z
	if net_u>0. and net_u<1.:
		curve=maxf(curve,(2.505+BALL_RADIUS+.05-launch.lerp(aim,net_u).y)/(net_u*(1.-net_u)))
	# For interior targets, steepen the descent enough to land before the
	# first baseline or sideline along this heading. Cap the correction so
	# a high target right on a boundary can still genuinely go long.
	var edge_u := (-4.85-launch.z)/travel.z
	if absf(travel.x)>.001:
		edge_u=minf(edge_u,(signf(travel.x)*4.35-launch.x)/travel.x)
	if edge_u>1.001:
		var needed := (launch.lerp(aim,edge_u).y-BALL_RADIUS)/(edge_u*(edge_u-1.))
		curve=maxf(curve,minf(needed,16.))
	return curve

func draw_pose() -> void:
	pass_goal=pass_marker.position
	pass_rise=pass_arc.value
	feed_kmh=incoming_speed.value
	var c: Dictionary=clips[index]
	if hand_leg_preview:
		c=c.duplicate()
		c.step_legs=0 if legs<0 else int(clips[legs].id)
		c.audition=true
	play_button.text="Pause" if playing else "Play"
	for anchor in defenders:
		var toward_server := serve_from-anchor.position
		var facing := Basis(Vector3.UP,atan2(toward_server.x,toward_server.z))
		if anchor==defenders[receiving] and mirror.button_pressed: facing.x=-facing.x
		anchor.basis=facing
	var aim := highlight.global_position+feed_offset
	var launch: Vector3=feed.preview_origin
	var full_duration := launch.distance_to(aim)/maxf(1.,incoming_speed.value/3.6)
	speed_label.text="Serve %d km/h" % incoming_speed.value
	var rig: Skeleton3D=player.skeleton
	var grid := grid_for(receiving)
	var key := [incoming_speed.value,line_read_error,serve_type,launch,aim,grid.global_transform,cell,quadrant,forearm_preview,hand_leg_preview,selected_only.button_pressed]
	if route_key!=key:
		route_key=key
		feed_curve=serve_curve(launch,aim,full_duration)
		var arc_height := feed_curve
		var slope := aim.y-launch.y+arc_height
		incoming_floor_fraction= (slope+sqrt(slope*slope+4.*arc_height*(launch.y-.145)))/(2.*arc_height)
		leave_feed=preload("res://scripts/pass_flight.gd").reads_out(launch.lerp(aim,incoming_floor_fraction),line_read_error,player.effective_rating("Forearm reception"))
		trace_incoming_regions(grid.to_local(launch),grid.to_local(aim))
	feed_fraction=routed_fraction
	var target := launch.lerp(aim,feed_fraction)+Vector3.UP*feed_curve*feed_fraction*(1.-feed_fraction)
	set_intercept=target
	var duration := full_duration*feed_fraction
	incoming_lead_seconds=duration
	var touch_frame := duration*60.
	var region := routed_region
	var address := Vector3i(region.x,region.y,region.z)
	var assigned := assigned_action(address,region.w) if region.w>=0 else 0
	var selected := address==cell and region.w==quadrant
	var active := not leave_feed and (assigned>0 or (selected and (forearm_preview or hand_leg_preview)))
	var motion_legs := legs
	if assigned>0 and not (selected and (hand_leg_preview or forearm_preview)) and (not selected or c.id!=assigned):
		for i in clips.size():
			if clips[i].id!=assigned: continue
			c=clips[i]
			motion_legs=i
			if c.kind=="overhead":
				var saved: int=StorySession.game_options.get_value("studio_hand_legs",assignment_key(address,region.w),-2)
				if saved>=-1 and saved<clips.size():
					c=c.duplicate()
					c.step_legs=0 if saved<0 else int(clips[saved].id)
					c.audition=true
					motion_legs=saved
			break
	if active and Regions.movement(c) and early_platform(address):
		# Set the platform on the incoming flight before the ball crowds the receiver.
		feed_fraction=maxf(0.,feed_fraction-.55/maxf(.55,launch.slide(Vector3.UP).distance_to(aim.slide(Vector3.UP))))
		target=launch.lerp(aim,feed_fraction)+Vector3.UP*feed_curve*feed_fraction*(1.-feed_fraction)
		set_intercept=target
		duration=full_duration*feed_fraction
		incoming_lead_seconds=duration
		touch_frame=duration*60.
	c=reception_recipe(c,address,region.w)
	if active and not selected and assigned>0:
		var routed_mirror := default_mirror(address,region.w,c)
		var orientation := Basis(Vector3.UP,atan2(serve_from.x-defenders[receiving].position.x,serve_from.z-defenders[receiving].position.z))
		if StorySession.game_options.get_value("studio_mirror",assignment_key(address,region.w),routed_mirror): orientation.x=-orientation.x
		defenders[receiving].basis=orientation
	var pose_frame := clampf(frame-touch_frame+c.contact,0.,c.frames)
	posed_lead_foot=lead_foot(address,region.w) if region.w>=0 else "Auto"
	if defenders[receiving].basis.determinant()<0. and posed_lead_foot!="Auto":
		posed_lead_foot="Left" if posed_lead_foot=="Right" else "Right"
	var signature := [posed_lead_foot,active,serve_type,launch,index,legs,mirror.button_pressed,incoming_speed.value,source,region,assigned,motion_legs,target,feed_offset,cell_action(),defenders[receiving].position]
	if signature!=contact_key:
		contact_key=signature
		reach_adjustment=Vector3.ZERO
		intercept_shift=Vector3.ZERO
		shift_frame=c.contact
		actual_fraction=feed_fraction
		sample_receiver(c,c.contact,active,motion_legs)
		if c.kind=="overhead":
			contact_point=HandPass.contact_center(player)
			if active and contact_point.distance_to(target)>HAND_RADIUS:
				intercept_shift=target-contact_point
				sample_receiver(c,c.contact,true,motion_legs)
				contact_point=HandPass.contact_center(player)
			reachable=active and contact_point.distance_to(target)<=HAND_RADIUS
		else:
			reachable=false
			var nominal := feed_fraction
			var best_gap := INF
			# Sample the moving ball and posed capsules on the same clock. Cache per feed for replay.
			var bounds := AABB(MAP_ORIGIN,CELL_SIZE*3.).grow(.45)
			var samples := ceili(full_duration*1.6*480.)
			var correction := Vector3.ZERO
			for attempt in 2:
				if attempt==1:
					if reachable or best_gap<=FOREARM_CONTACT_GRACE or best_gap>.095 or not Regions.movement(c): break
					reach_adjustment=rig.global_basis.inverse()*correction.limit_length(.11)
					best_gap=INF
				for tick in range(samples+1):
					if not active: break
					var u := tick/(480.*full_duration)
					var ball := launch.lerp(aim,u)+Vector3.UP*feed_curve*u*(1.-u)
					if ball.y<BALL_RADIUS: break
					if not bounds.has_point(grid.to_local(ball)): continue
					var at_frame := clampf(c.contact+(u-nominal)*full_duration*60.,0.,c.frames)
					sample_receiver(c,at_frame,true,motion_legs)
					var separation := INF
					var nearest_delta := Vector3.ZERO
					for shape in RECEPTION_CAPSULES:
						var segment := reception_segment(rig,shape)
						var point := Geometry3D.get_closest_point_to_segment(ball,segment[0],segment[1])
						var gap := point.distance_to(ball)-float(shape[2])-BALL_RADIUS
						if gap<separation:
							separation=gap
							nearest_delta=ball-point
					if separation<best_gap:
						best_gap=separation
						correction=nearest_delta.normalized()*(maxf(0.,separation)+.018)
						contact_point=ball
						actual_fraction=u
					if separation<=0.:
						reachable=true
						break
			# Use the closest sampled instant for grazing passes.
			reachable=active and best_gap<=FOREARM_CONTACT_GRACE
			if active and not reachable and is_finite(best_gap):
				shift_frame=clampf(c.contact+(actual_fraction-nominal)*full_duration*60.,0.,c.frames)
				for adjustment in 3:
					if c.get("stack_knee",false) and correction.y<0.:
						# Lower the hips over the planted foot rather than translating the feet below the court.
						reach_adjustment.y+=correction.y
						correction.y=0.
					if c.get("grounded_platform",false):
						if correction.y<0.: reach_adjustment.y+=correction.y
						correction.y=0.
					intercept_shift+=correction
					sample_receiver(c,shift_frame,true,motion_legs)
					best_gap=INF
					for shape in RECEPTION_CAPSULES:
						var seg := reception_segment(rig,shape)
						var p := Geometry3D.get_closest_point_to_segment(contact_point,seg[0],seg[1])
						var gap := p.distance_to(contact_point)-float(shape[2])-BALL_RADIUS
						if gap<best_gap:
							best_gap=gap
							correction=(contact_point-p).normalized()*(maxf(0.,gap)+.018)
					reachable=best_gap<=FOREARM_CONTACT_GRACE
					if reachable or not (c.get("stack_knee",false) or c.get("grounded_platform",false)): break
			closest_surface_gap=best_gap
	if active and c.kind!="overhead":
		feed_fraction=actual_fraction
		target=launch.lerp(aim,feed_fraction)+Vector3.UP*feed_curve*feed_fraction*(1.-feed_fraction)
		touch_frame+=(feed_fraction-duration/full_duration)*full_duration*60.
		duration=full_duration*feed_fraction
	var missed: bool= frame>=touch_frame and active and not reachable
	miss_label.visible=missed or leave_feed
	if leave_feed: miss_label.text="Leave \u00b7 out"
	if missed:
		var gap := contact_point.distance_to(target) if c.kind=="overhead" else closest_surface_gap
		miss_label.text="Miss \u00b7 %d cm gap"%roundi(gap*100.)
		if playing and not miss_logged:
			print("studio_miss ",Time.get_datetime_string_from_system()," defender=",receiving+1," cell=",address," region=",region_number(address,region.w)," assigned=",assigned," playing=",c.id," target=",target," contact=",contact_point," gap_m=",gap)
			miss_logged=true
	if c.kind=="overhead": pose_frame=maxf(0.,frame-touch_frame+c.contact)
	sample_receiver(c,pose_frame,active,motion_legs)
	if leave_feed: player.pose_leave_ball((frame-touch_frame)/60.+duration)
	hand_volume.visible=hand_toggle.button_pressed and c.kind=="overhead" and active
	if hand_volume.visible: hand_volume.global_position=HandPass.contact_center(player)
	for i in arm_volumes.size():
		var volume := arm_volumes[i]
		volume.visible=hand_toggle.button_pressed and not hand_volume.visible
		if volume.visible:
			var segment := reception_segment(rig,RECEPTION_CAPSULES[i])
			var axis := segment[1]-segment[0]
			var capsule := volume.mesh as CapsuleMesh
			var height := axis.length()+2.*capsule.radius
			if not is_equal_approx(capsule.height,height): capsule.height=height
			volume.global_transform=Transform3D(Basis(Quaternion(Vector3.UP,axis.normalized())),(segment[0]+segment[1])*.5)
	var seconds := (frame-touch_frame)/60.
	update_cpu_ring(seconds,duration,active)
	var serve_time := clampf(feed.contact_time()+seconds+duration,0.,feed.contact_time()+.42)
	feed.pose(serve_time)
	feed.ball.show()
	if ball_trail.visible: trail_mesh.clear_surfaces()
	crossing.hide()
	var lift := sqrt(2.*9.81*pass_arc.value)
	var landing := (lift+sqrt(lift*lift+2.*9.81*maxf(0.,target.y-.145)))/9.81
	var end_seconds := duration+landing if reachable else full_duration*incoming_floor_fraction
	pass_end_frame=ceilf(end_seconds*60.)
	seek.set_block_signals(true)
	seek.max_value=pass_end_frame
	seek.set_block_signals(false)
	seek.set_value_no_signal(frame)
	label.text=" %02d / %02d     Frame %d / %d " % [c.id,clips.size(),roundi(frame),int(pass_end_frame)]
	seconds=minf(seconds,end_seconds-duration)
	var point := flight_point(seconds,launch,target,duration,lift,landing)
	var occupied := contact_region(point) if seconds<=0. or not reachable else Vector4i(-1,-1,-1,-1)
	if reachable and region.w>=0 and seconds>=0. and seconds<.20: occupied=region
	if occupied.w>=0 and point.y>=.145:
		var box_address := Vector3i(occupied.x,occupied.y,occupied.z)
		crossing.global_position=grid.to_global(region_center(box_address,occupied.w))
		crossing.scale=region_size(box_address,occupied.w)/CELL_SIZE
		crossing.show()
	feed.ball.rotation=Vector3.ZERO
	if reachable and seconds>0.:
		preload("res://scripts/pass_flight.gd").rotate_reception_ball(feed.ball,(pass_marker.position-target)/landing,seconds,feed.reception_spin_rps(),c.kind=="overhead")
	feed.ball.position=point
	feed.ball.visible=point.y>=.144
	if ball_trail.visible and seconds > -duration:
		draw_ball_trail(seconds,launch,target,duration,lift,landing)

# Sweep the incoming parabola once per feed, including its continuation past the aim point.
func update_cpu_ring(seconds: float,duration: float,active: bool) -> void:
	for actor in timing_display.floor_rings:
		if actor!=player: timing_display.floor_rings[actor].hide()
	timing_display.position_floor_ring(player)
	if not active or seconds < -duration or seconds > cpu_release_offset+.65: return
	var clean := preload("res://scripts/indoor_practice.gd").BUMP_ON_TIME
	var cursor := clampf(inverse_lerp(-.25,.25,minf(seconds,cpu_release_offset)),0.,1.)
	timing_display.timing_arc(player,cursor,inverse_lerp(-.25,.25,-clean),inverse_lerp(-.25,.25,clean),
		Vector2(.10,.90),Color("14191d"),seconds>=cpu_release_offset)

func trace_incoming_regions(start: Vector3, aim: Vector3) -> void:
	routed_fraction=1.
	routed_region=Vector4i(-1,-1,-1,-1)
	var previous := start
	for i in range(1,193):
		var u := i/96.
		var point := start.lerp(aim,u)+Vector3.UP*feed_curve*u*(1.-u)
		var earliest := INF
		for box in flight_boxes:
			var selected: bool=box.address==cell and box.part==quadrant
			if selected_only.button_pressed and not selected: continue
			var audition: bool=selected and (forearm_preview or hand_leg_preview)
			if not box.assigned and not audition: continue
			var span := zone_interval(previous,point,box.bounds)
			if span.y<=span.x or span.x>=earliest: continue
			earliest=span.x
			var address: Vector3i=box.address
			routed_region=Vector4i(address.x,address.y,address.z,box.part)
			routed_fraction=1. if box.bounds.has_point(aim) else (i-1+(span.x+span.y)*.5)/96.
		if routed_region.w>=0 or point.y<.09: return
		previous=point

func flight_point(t: float,launch: Vector3,target: Vector3,duration: float,lift: float,landing: float) -> Vector3:
	if reachable and t>0.:
		var point := target.lerp(Vector3(pass_marker.position.x,target.y,pass_marker.position.z),t/landing)
		point.y+=lift*t-4.905*t*t
		return point
	var u := (t+duration)/duration
	return launch.lerp(target,u)+Vector3.UP*feed_curve*feed_fraction*feed_fraction*u*(1.-u)

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

func select_legs(which: int) -> void:
	if cell.y<2 and (cell_action()==0 or Regions.movement(clips[index])):
		hand_leg_preview=false
		forearm_preview=which>=0
		legs=which
		if forearm_preview:
			index=which
			apply_cell_mirror(clips[index])
		frame=seek.min_value
		playing=true
		contact_key.clear()
		update_leg_buttons()
		draw_pose()
		return
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
		contact_key.clear()
		update_leg_buttons()
		draw_pose()
		return
	legs=which
	if which>=0:
		index=which
	update_leg_buttons()
	draw_pose()

func update_leg_buttons() -> void:
	leg_label.text=("Forearm pass / Legs   " if forearm_preview or (cell.y==1 and Regions.movement(clips[index])) else "Legs   ")+("Ready" if legs<0 else "#%02d" % clips[legs].id)
	for choice in leg_grid.get_children():
		choice.set_pressed_no_signal(choice.get_meta("clip")==legs)

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
	selected_only.text="Test selected box only"
	selected_only.button_pressed=StorySession.game_options.get_value("reception_studio","test_selected_only",false)
	tiers.add_child(selected_only)
	selected_only.toggled.connect(func(on):
		StorySession.game_options.set_value("reception_studio","test_selected_only",on)
		StorySession.save_options()
		draw_pose())
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
	for shape in RECEPTION_CAPSULES:
		var capsule := CapsuleMesh.new()
		capsule.radius=shape[2]
		capsule.material=ink
		var volume := MeshInstance3D.new()
		volume.mesh=capsule
		volume.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(volume)
		arm_volumes.append(volume)
	hand_toggle.text="Reception hitboxes"
	hand_toggle.button_pressed=StorySession.game_options.get_value("reception_studio","hand_hitbox",false)
	tiers.add_child(hand_toggle)
	hand_toggle.toggled.connect(func(on):
		StorySession.game_options.set_value("reception_studio","hand_hitbox",on)
		StorySession.save_options()
		draw_pose())
	place.text="Place ready zone"
	place.button_pressed=StorySession.game_options.get_value("reception_studio","place_zone",false)
	place.toggled.connect(func(on):
		StorySession.game_options.set_value("reception_studio","place_zone",on)
		StorySession.save_options())
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
	button(depth,"\u2039",change_depth.bind(-1))
	depth.add_child(depth_label)
	button(depth,"\u203a",change_depth.bind(1))
	editor.add_child(region_label)
	miss_label.modulate=Color("#ff897c")
	editor.add_child(miss_label)
	editor.add_child(foot_choice)
	foot_choice.pressed.connect(func():
		var choices := ["Auto","Left","Right"]
		var next: String=choices[(choices.find(lead_foot(cell,quadrant))+1)%3]
		StorySession.game_options.set_value("studio_lead_foot",assignment_key(cell,quadrant),next)
		StorySession.save_options()
		update_region()
		draw_pose())
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
	crossing.mesh=box
	var active_style := tint.duplicate() as StandardMaterial3D
	active_style.albedo_color=Color(.18,1.,.43,.48)
	crossing.material_override=active_style
	add_child(crossing)
	crossing.hide()
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
	if cell==REGION_23: cell=REGION_22
	quadrant=mini(quadrant,region_parts(cell)-1)
	save_selection()
	preview_cell()

func save_selection() -> void:
	StorySession.game_options.set_value("reception_studio","selection",{"receiver":receiving,"cell":cell,"part":quadrant})
	StorySession.save_options()

func contact_region(world_point: Vector3) -> Vector4i:
	var point := grid_for(receiving).to_local(world_point)
	var address := Vector3i(((point-MAP_ORIGIN)/CELL_SIZE).floor())
	if address!=address.clamp(MAP_MIN,MAP_MAX): return Vector4i(-1,-1,-1,-1)
	if address==REGION_23: address=REGION_22
	for part in region_parts(address):
		var size := region_size(address,part)
		if AABB(region_center(address,part)-size*.5,size).has_point(point):
			return Vector4i(address.x,address.y,address.z,part)
	return Vector4i(-1,-1,-1,-1)

func cell_action() -> int:
	return assigned_action(cell,quadrant)

func next_assigned_feed() -> void:
	var assigned := flight_boxes.filter(func(box): return box.assigned)
	if assigned.is_empty():
		playing=false
		return
	var box: Dictionary=assigned.pick_random()
	activate_receiver(0)
	cell=box.address
	quadrant=box.part
	preview_cell()

func pick_feed_point() -> void:
	cpu_release_offset=randf_range(-.16,.16)
	line_read_error=randf_range(-1.,1.)
	miss_logged=false
	var half := region_size(cell,quadrant)*.5
	var bottom := maxf(-half.y,.145-highlight.global_position.y)
	feed_offset=Vector3(randf_range(-half.x,half.x),randf_range(bottom,half.y),randf_range(-half.z,half.z))

func preview_cell() -> void:
	forearm_preview=false
	hand_leg_preview=false
	contact_key.clear()
	update_region()
	pick_feed_point()
	var id := cell_action()
	if id==0: apply_cell_mirror({})
	for i in clips.size():
		if int(clips[i].id)==id:
			index=i
			legs=i
			if clips[i].kind=="overhead":
				var saved: int=StorySession.game_options.get_value("studio_hand_legs",assignment_key(cell,quadrant),-2)
				if saved>=-1 and saved<clips.size():
					legs=saved
					hand_leg_preview=true
			update_leg_buttons()
			apply_cell_mirror(clips[i])
			break
	
	frame=seek.min_value
	playing=true
	draw_pose()

func apply_cell_mirror(clip: Dictionary) -> void:
	var automatic := default_mirror(cell,quadrant,clip)
	var on: bool=StorySession.game_options.get_value("studio_mirror",assignment_key(cell,quadrant),automatic)
	mirror.set_pressed_no_signal(on)
	defenders[receiving].scale.x=-1. if on else 1.

func update_region() -> void:
	foot_choice.text="Lead foot: "+lead_foot(cell,quadrant)
	depth_label.text=["Back","Body","Front"][cell.z-MAP_MIN.z]
	var id := cell_action()
	highlight.visible=not unfinished.button_pressed or id==0
	region_label.text="#%s \u00b7 %s %s - %s" % [region_number(cell,quadrant),HEIGHTS[cell.y],("22-23" if cell==REGION_22 else WIDTHS[cell.x-MAP_MIN.x]),"Unassigned" if id==0 else "Action #%02d"%id]
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
	flight_boxes.clear()
	route_key.clear()
	hover.hide()
	for x in range(MAP_MIN.x,MAP_MAX.x+1):
		for y in range(MAP_MAX.y+1):
			for z in range(MAP_MIN.z,MAP_MAX.z+1):
				var address := Vector3i(x,y,z)
				var count := region_parts(address)
				for part in count:
					var size := region_size(address,part)
					var assigned := assigned_action(address,part)>0
					var center := region_center(address,part)
					flight_boxes.append({"address":address,"part":part,"assigned":assigned,"bounds":AABB(center-size*.5,size)})
					if assigned and unfinished.button_pressed: continue
					if pick_boxes.is_empty(): mesh.surface_begin(Mesh.PRIMITIVE_LINES,ink)
					var color := Color("#ae2839") if assigned else Color("#2153a4")
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
