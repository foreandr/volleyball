extends Node3D

const Regions = preload("res://scripts/reception_regions.gd")
var cell := Vector3i(1,1,1)
const MAP_MIN := Vector3i(-1,0,-1)
const MAP_MAX := Vector3i(3,3,3)
const WIDTHS := ["Wide R","Right","Center","Left","Wide L"]
const HEIGHTS := ["Low","Mid","High","Above"]
const CELL_SIZE := Regions.CELL*1.20
const MAP_ORIGIN := Vector3(-1.5,0,-1.5)*CELL_SIZE
const Gym = preload("res://scripts/tryout_gym.gd")
var feed := preload("res://scripts/standing_float_serve.gd").new()
var server = preload("res://scripts/volleyball_player.gd").new()
var zone := MeshInstance3D.new()
var hover := MeshInstance3D.new()
var vary := CheckButton.new()
var place := CheckButton.new()
var contact_point := Vector3.ZERO
var contact_key := []
var reachable := false
var lattice := MeshInstance3D.new()
var highlight := MeshInstance3D.new()
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
var distance := 4.8
var label := Label.new()
var play_button := Button.new()
var seek := HSlider.new()
var mirror := CheckButton.new()
var elapsed := 0.
var source := ""
var sidebar := PanelContainer.new()
const FOREARM = preload("res://assets/animations/straight_pass_02.res")
var leg_grid := GridContainer.new()
var leg_label := Label.new()
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
	add_child(camera)
	camera.current=true
	position_camera()
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	layer.add_child(panel)
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
		pivot.scale.x=-1. if on else 1.
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
	sidebar.offset_right=224
	var tiers := VBoxContainer.new()
	sidebar.add_child(tiers)
	var torso_label := Label.new()
	torso_label.text="Torso - Forearm reception"
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
	build_map(tiers)
	tiers.add_child(leg_label)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	tiers.add_child(scroll)
	leg_grid.columns=4
	scroll.add_child(leg_grid)
	column.add_child(seek)
	seek.min_value=-85
	seek.step=1
	seek.value_changed.connect(func(value): playing=false; frame=value; draw_pose())
	refresh()
	update_leg_buttons()
	draw_pose()
	cell=Vector3i(((lattice.to_local(contact_point)-MAP_ORIGIN)/CELL_SIZE).floor()).clamp(MAP_MIN,MAP_MAX)
	preview_cell()

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
	index=posmod(index+by,clips.size())
	frame=seek.min_value
	legs=index
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
	elapsed+=delta
	if elapsed>.5:
		elapsed=0.
		refresh()
	if playing:
		frame+=delta*60.
		if frame>=clips[index].frames+1.:
			frame=seek.min_value
			if vary.button_pressed:
				cell=Vector3i(randi_range(MAP_MIN.x,MAP_MAX.x),randi_range(0,2),randi_range(1,MAP_MAX.z))
				preview_cell()
		draw_pose()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		var ray := camera.project_ray_origin(event.position)
		var direction := camera.project_ray_normal(event.position)
		var click: bool=event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed
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
			var hit=Plane(Vector3.BACK,highlight.global_position.z).intersects_ray(ray,direction)
			hover.hide()
			if hit!=null:
				var hovered := Vector3i(((lattice.to_local(hit)-MAP_ORIGIN)/CELL_SIZE).floor())
				if hovered.x>=MAP_MIN.x and hovered.x<=MAP_MAX.x and hovered.y>=0 and hovered.y<=MAP_MAX.y:
					hover.position=MAP_ORIGIN+(Vector3(hovered.x,hovered.y,cell.z)+Vector3.ONE*.5)*CELL_SIZE
					hover.show()
					if click:
						pick_cell(hovered.x,hovered.y)
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

func position_camera() -> void:
	var target := pivot.position+Vector3(0,.92,.15)
	camera.position=target+Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))*distance
	camera.look_at(target)

func draw_pose() -> void:
	var c: Dictionary=clips[index]
	var f := clampf(roundf(frame),0.,c.frames)
	seek.set_value_no_signal(frame)
	label.text=" %02d / %02d     Frame %d / %d " % [c.id,clips.size(),roundi(frame),c.frames]
	play_button.text="Pause" if playing else "Play"
	var signature := [index,legs,mirror.button_pressed,incoming_speed.value,source,cell,pivot.position]
	if signature!=contact_key:
		contact_key=signature
		sample_receiver(c,c.contact)
		var rig: Skeleton3D=player.skeleton
		var center := Vector3.ZERO
		for side in ["l","r"]:
			var wrist := rig.get_bone_global_pose(rig.find_bone("hand_"+side)).origin
			var elbow := rig.get_bone_global_pose(rig.find_bone("lowerarm_"+side)).origin
			center+=rig.to_global(wrist.lerp(elbow,.32))*.5
		contact_point=center+Vector3(0,.075,.075)
		var offset := (contact_point-highlight.global_position).abs()-CELL_SIZE*.5
		reachable=maxf(offset.x,maxf(offset.y,offset.z))<=.12
	sample_receiver(c,f)
	var target := contact_point if reachable else highlight.global_position
	var launch: Vector3=feed.preview_origin
	var duration := clampf(launch.distance_to(target)/maxf(1.,incoming_speed.value/3.6),.48,1.25)
	var seconds := (frame-float(c.contact))/60.
	var serve_time := clampf(feed.contact_time()+seconds+duration,0.,feed.contact_time()+.42)
	feed.pose(serve_time)
	feed.ball.show()
	if seconds < -duration: return
	var u := (seconds+duration)/duration
	var arc := maxf(.95,3.05-launch.lerp(target,.60).y)
	var point := launch.lerp(target,u)+Vector3.UP*4.*arc*u*(1.-u)
	if reachable and seconds>0.:
		point=target+Vector3(0,5.4,4.)*seconds+Vector3.DOWN*4.905*seconds*seconds
	feed.ball.position=point
	feed.ball.visible=point.y>=.145

func sample_receiver(c: Dictionary,f: float) -> void:
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

func select_legs(which: int) -> void:
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
	if c.kind=="overhead":
		for side in ["l","r"]:
			var sign_x := 1. if side=="l" else -1.
			author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,chest+Vector3(sign_x*.12,.38,.30),Vector3(sign_x,-.1,.1),weight)
	for bone in pose.size(): rig.set_bone_pose(bone,pose[bone])

func build_map(tiers: VBoxContainer) -> void:
	var title := Label.new()
	title.text="Contact map"
	tiers.add_child(title)
	place.text="Place ready zone"
	tiers.add_child(place)
	vary.text="Vary serves"
	tiers.add_child(vary)
	var editor := VBoxContainer.new()
	tiers.add_child(editor)
	var depth := HBoxContainer.new()
	editor.add_child(depth)
	button(depth,"‹",change_depth.bind(-1))
	depth.add_child(depth_label)
	button(depth,"›",change_depth.bind(1))
	var cells := GridContainer.new()
	cells.columns=5
	editor.add_child(cells)
	for y in range(MAP_MAX.y,-1,-1):
		for x in range(MAP_MIN.x,MAP_MAX.x+1):
			var b := Button.new()
			b.text=WIDTHS[x-MAP_MIN.x]
			b.tooltip_text=HEIGHTS[y]
			b.pressed.connect(pick_cell.bind(x,y))
			cells.add_child(b)
	editor.add_child(region_label)
	button(editor,"Assign current action",assign_region)
	var lines := ImmediateMesh.new()
	var ink := StandardMaterial3D.new()
	ink.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	ink.albedo_color=Color("68cfc958")
	lines.surface_begin(Mesh.PRIMITIVE_LINES,ink)
	for axis in 3:
		for i in range(MAP_MIN[(axis+1)%3],MAP_MAX[(axis+1)%3]+2):
			for j in range(MAP_MIN[(axis+2)%3],MAP_MAX[(axis+2)%3]+2):
				var start := Vector3(MAP_MIN)
				start[(axis+1)%3]=i
				start[(axis+2)%3]=j
				var end := start
				end[axis]=MAP_MAX[axis]+1
				lines.surface_add_vertex(MAP_ORIGIN+start*CELL_SIZE)
				lines.surface_add_vertex(MAP_ORIGIN+end*CELL_SIZE)
	lines.surface_end()
	lattice.mesh=lines
	add_child(lattice)
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
	hover.hide()
	lattice.position=pivot.position
	update_region()

func pick_cell(x: int,y: int) -> void:
	cell.x=x
	cell.y=y
	preview_cell()

func change_depth(by: int) -> void:
	cell.z=posmod(cell.z-MAP_MIN.z+by,5)+MAP_MIN.z
	preview_cell()

func cell_action() -> int:
	var outer := cell.x<0 or cell.x>2 or cell.z<0 or cell.z>2 or cell.y>2
	if outer:
		var fallback := 12 if cell.x!=1 else 11
		return int(StorySession.game_options.get_value("dig_regions",Regions.key(cell),fallback))
	return Regions.assignment(cell)

func preview_cell() -> void:
	update_region()
	var id := cell_action()
	for i in clips.size():
		if int(clips[i].id)==id:
			select_legs(i)
			if cell.x!=1:
				mirror.button_pressed=(cell.x<1)!=(float(clips[i].side)<0.)
			break
	if id==0: select_legs(-1)
	frame=seek.min_value
	playing=true
	draw_pose()

func update_region() -> void:
	depth_label.text=["Far back","Back","Body","Front","Far front"][cell.z-MAP_MIN.z]
	var id := cell_action()
	region_label.text="%s %s - %s" % [HEIGHTS[cell.y],WIDTHS[cell.x-MAP_MIN.x],"Ready" if id==0 else "Action #%02d"%id]
	highlight.position=MAP_ORIGIN+(Vector3(cell)+Vector3.ONE*.5)*CELL_SIZE

func assign_region() -> void:
	var id: int=0 if legs<0 else clips[legs].id
	StorySession.game_options.set_value("dig_regions",Regions.key(cell),id)
	StorySession.save_options()
	update_region()
