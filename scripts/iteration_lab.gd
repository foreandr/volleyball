extends Control

const Policy = preload("res://scripts/cpu_policy.gd")
var status: Label
var duration: SpinBox
var play: Button
var stop: Button
var clock := 0.0
var proposal_list: ItemList
var details: Label
var manifests: Array[Dictionary] = []
var preview: TextureRect
var tool_panel: VBoxContainer
var proposal_title: Label
var take_label: Label
var review_controls: HBoxContainer
var accept: Button
var take := 1
var frame_size := Vector2i(320,180)
var skipped := {}
var next_id := ""
var frames: Array[Texture2D] = []
var playback := false
var playback_speed := 0.0
var slow_frames := Vector2i(-1,-1)
var loop_focus := false
var frame_duration := 1.0/12.0
var frame_time := 0.0
var current_frame := 0
var view_index := 0
var result_log := ""
var review_pid := -1
var seed_input: SpinBox
var point_input: SpinBox
var note: LineEdit
var selected_id := ""

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("#111821")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,26)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",14)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	proposal_title = label("Iteration Lab",24)
	proposal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(proposal_title)
	tool_panel = VBoxContainer.new()
	tool_panel.hide()
	header.add_child(button("Tools",func(): tool_panel.visible = not tool_panel.visible))
	header.add_child(button("Back",func(): get_tree().change_scene_to_file("res://scenes/main.tscn")))

	var stage := PanelContainer.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var border := StyleBoxFlat.new()
	border.bg_color = Color("#090d13")
	border.set_corner_radius_all(10)
	border.set_content_margin_all(4)
	stage.add_theme_stylebox_override("panel",border)
	layout.add_child(stage)
	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stage.add_child(preview)

	review_controls = HBoxContainer.new()
	review_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	review_controls.add_theme_constant_override("separation",10)
	layout.add_child(review_controls)
	var left := button("‹",set_take.bind(0))
	left.tooltip_text = "Original (Left arrow)"
	left.custom_minimum_size = Vector2(42,38)
	review_controls.add_child(left)
	take_label = label("Proposed",16)
	take_label.custom_minimum_size.x = 78
	take_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	review_controls.add_child(take_label)
	var right := button("›",set_take.bind(1))
	right.tooltip_text = "Proposed (Right arrow)"
	right.custom_minimum_size = Vector2(42,38)
	review_controls.add_child(right)
	accept = button("Accept",decide.bind("Accept"))
	accept.custom_minimum_size = Vector2(100,38)
	accept.add_theme_color_override("font_color",Color("#a3e7c9"))
	review_controls.add_child(accept)
	var skip_button := button("Skip",skip)
	skip_button.custom_minimum_size = Vector2(76,38)
	review_controls.add_child(skip_button)
	details = label("",16)
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(details)
	layout.add_child(tool_panel)

	var controls := HBoxContainer.new()
	tool_panel.add_child(controls)
	play = button("Play",start_run)
	stop = button("Stop",stop_run)
	controls.add_child(play)
	controls.add_child(stop)
	controls.add_child(label("Training speed",16))
	controls.add_child(StorySession.iteration_run.speed_picker())
	duration = number_box(10,0,720,"min")
	controls.add_child(duration)
	controls.add_child(label("0 runs until Stop",16))
	controls.add_child(button("Watch latest finding",watch_latest))
	status = label("",16)
	tool_panel.add_child(status)
	proposal_list = ItemList.new()
	proposal_list.custom_minimum_size.y = 64
	proposal_list.item_selected.connect(select_proposal)
	tool_panel.add_child(proposal_list)
	var timeline := HBoxContainer.new()
	tool_panel.add_child(timeline)
	timeline.add_child(button("Play / pause",func(): playback = not playback))
	timeline.add_child(label("Clip speed",16))
	var speed := OptionButton.new()
	var rates := [0.0,1.0,0.5,0.25,0.125]
	for caption in ["Auto","1×","½×","¼×","⅛×"]: speed.add_item(caption)
	speed.select(0)
	speed.item_selected.connect(func(index: int): playback_speed = rates[index])
	timeline.add_child(speed)
	timeline.add_child(button("Camera",toggle_camera))
	timeline.add_child(label("Seed",16))
	seed_input = number_box(41,0,2147483647,"")
	timeline.add_child(seed_input)
	timeline.add_child(label("Point",16))
	point_input = number_box(1,1,100,"")
	timeline.add_child(point_input)
	timeline.add_child(button("Render comparison",decide.bind("Clip")))
	var actions := HBoxContainer.new()
	tool_panel.add_child(actions)
	actions.add_child(button("Refresh queue",func(): skipped.clear(); refresh_proposals()))
	actions.add_child(button("Re-test",decide.bind("Review")))
	actions.add_child(button("Reject",decide.bind("Reject")))
	note = LineEdit.new()
	note.placeholder_text = "Feedback"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(note)
	actions.add_child(button("Send back",decide.bind("Feedback")))
	refresh_proposals()
	refresh_status()

func number_box(value: int, minimum: int, maximum: int, suffix: String) -> SpinBox:
	var item := SpinBox.new()
	item.min_value = minimum
	item.max_value = maximum
	item.value = value
	item.suffix = suffix
	return item

func label(caption: String, size: int) -> Label:
	var item := Label.new()
	item.text = caption
	item.add_theme_font_size_override("font_size",size)
	return item

func button(caption: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = caption
	item.pressed.connect(action)
	return item

func _process(delta: float) -> void:
	clock += delta
	if clock >= 0.8:
		clock = 0.0
		refresh_status()
	if playback and frames.size() == 2: advance_clip(delta)

func advance_clip(delta: float) -> void:
	var last := frames[0].get_width()/frame_size.x-1
	var first := 0
	if playback_speed == 0.0 and loop_focus and slow_frames.x >= 0:
		first = slow_frames.x
		last = slow_frames.y
	var next := clampi(current_frame,first,last)
	frame_time += delta
	var duration_ := clip_frame_duration(next)
	while frame_time >= duration_:
		frame_time -= duration_
		next = first if next >= last else next+1
		duration_ = clip_frame_duration(next)
	if current_frame != next: show_frame(next)

func clip_frame_duration(index: int) -> float:
	if playback_speed > 0.0: return frame_duration/playback_speed
	if index >= slow_frames.x and index <= slow_frames.y: return frame_duration*4.0
	return frame_duration

func refresh_status() -> void:
	var data := StorySession.iteration_run.status()
	var running: bool = data.running
	var learned := Policy.read_json(Policy.PATH)
	play.disabled = running
	stop.disabled = not running or data.state == "stopping"
	var state := str(data.state).capitalize()
	status.text = "%s   ·   %d matches this run   ·   %d review flags   ·   %d training matches saved" % [
		state,int(data.get("matches",0)),int(data.get("observations",0)),int(learned.get("matches",0))]
	if review_pid > 0 and not OS.is_process_running(review_pid):
		review_pid = -1
		var message := FileAccess.get_file_as_string(result_log).strip_edges() if FileAccess.file_exists(result_log) else "Error: Review tool did not return a result."
		refresh_proposals()
		if message.begins_with("Error:"): details.text = message.get_slice("\n",0)

func start_run() -> void:
	if StorySession.iteration_run.start(int(duration.value)): refresh_status()
	else: status.text = "Could not start self-play."

func stop_run() -> void:
	if StorySession.iteration_run.stop(): refresh_status()
	else: status.text = "Could not stop self-play."

func watch_latest() -> void:
	var demo_directory: String = preload("res://scripts/match_review.gd").DIRECTORY
	var demo_path := ""
	if DirAccess.dir_exists_absolute(demo_directory):
		var clips := DirAccess.get_files_at(demo_directory)
		clips.sort()
		for index in range(clips.size()-1,-1,-1):
			if clips[index].ends_with(".vreplay"):
				demo_path = demo_directory.path_join(clips[index])
				break
	var data := Policy.read_json(Policy.DIRECTORY+"/status.json")
	var run := str(data.get("run",""))
	var path := run+"/matches.jsonl"
	if run.is_empty() or not FileAccess.file_exists(path):
		if demo_path.is_empty(): details.text = "No replay findings yet."
		else: open_finding(demo_path)
		return
	var lines := FileAccess.get_file_as_string(path).split("
",false)
	for index in range(lines.size()-1,-1,-1):
		var match_: Variant = JSON.parse_string(lines[index])
		if not match_ is Dictionary: continue
		var flags: Array = match_.get("review_flags",[])
		for flag in flags:
			if not flag.has("replay"): continue
			var worker_path := str(flag.replay)
			open_finding(demo_path if not demo_path.is_empty() and FileAccess.get_modified_time(demo_path) >= FileAccess.get_modified_time(worker_path) else worker_path)
			return
	if demo_path.is_empty(): details.text = "No replay findings yet."
	else: open_finding(demo_path)

func open_finding(path: String) -> void:
	StorySession.lab_replay_path = path
	get_tree().change_scene_to_file("res://scenes/story_animations.tscn")

func refresh_proposals() -> void:
	proposal_list.clear()
	manifests.clear()
	frames.clear()
	preview.texture = null
	proposal_title.text = "Iteration Lab"
	review_controls.hide()
	details.text = "No proposals to review."
	var root := ProjectSettings.globalize_path("res://work/iterations")
	if not DirAccess.dir_exists_absolute(root): return
	var selected := -1
	var next_index := 0
	for id in DirAccess.get_directories_at(root):
		var manifest := Policy.read_json(root.path_join(id).path_join("proposal.json"))
		if manifest.get("status","") != "pending" or skipped.has(id): continue
		manifest["directory"] = root.path_join(id)
		if id == selected_id: selected = manifests.size()
		if id == next_id: next_index = manifests.size()
		manifests.append(manifest)
		proposal_list.add_item(str(manifest.get("title",id)))
	if not manifests.is_empty():
		if selected < 0: selected = next_index
		proposal_list.select(selected)
		select_proposal(selected)

func select_proposal(index: int) -> void:
	var entry := manifests[index]
	selected_id = str(entry.id)
	frames.clear()
	playback = false
	preview.texture = null
	proposal_title.text = str(entry.get("short_title",entry.get("title",selected_id)))
	details.text = ""
	review_controls.show()
	accept.disabled = review_pid > 0
	take = 1
	take_label.text = "Proposed"
	view_index = 0
	var root := str(entry.directory).path_join("clips").path_join(str(entry.candidate).left(12))
	if not DirAccess.dir_exists_absolute(root):
		details.text = "No preview yet. Render it from Tools."
		return
	var clips := DirAccess.get_directories_at(root)
	var requested := "seed-%d-point-%d" % [int(seed_input.value),int(point_input.value)]
	if requested in clips: clips = PackedStringArray([requested])
	for clip in clips:
		var before := root.path_join(clip).path_join("before")
		var after := root.path_join(clip).path_join("after")
		if not DirAccess.dir_exists_absolute(before) or not DirAccess.dir_exists_absolute(after): continue
		for filename in DirAccess.get_files_at(before):
			if not filename.ends_with(".png") or not FileAccess.file_exists(after.path_join(filename)): continue
			for directory in [before,after]:
				var sample := Image.load_from_file(directory.path_join(filename))
				if not sample.is_empty(): frames.append(ImageTexture.create_from_image(sample))
			if frames.size() == 2 and frames[0].get_size() == frames[1].get_size():
				var settings := Policy.read_json(root.path_join(clip).path_join("clip.json"))
				frame_size = Vector2i(clampi(int(settings.get("frame_width",320)),1,frames[0].get_width()),frames[0].get_height()/2)
				var count := frames[0].get_width()/frame_size.x
				frame_duration = clampf(float(settings.get("frame_seconds",1.0/12.0 if count >= 24 else 0.16)),0.01,1.0)
				slow_frames = Vector2i(clampi(int(settings.get("slow_first",-1)),-1,count-1),clampi(int(settings.get("slow_last",-1)),-1,count-1))
				if slow_frames.y < slow_frames.x: slow_frames = Vector2i(-1,-1)
				loop_focus = bool(settings.get("loop_focus",false))
				frame_time = 0.0
				playback = true
				show_frame(maxi(0,slow_frames.x) if loop_focus and playback_speed == 0.0 else 0)
				return
			frames.clear()
	details.text = "No preview yet. Render it from Tools."

func show_frame(index: int) -> void:
	current_frame = index
	var atlas := AtlasTexture.new()
	atlas.atlas = frames[take]
	atlas.region = Rect2(index*frame_size.x,view_index*frame_size.y,frame_size.x,frame_size.y)
	preview.texture = atlas

func set_take(index: int) -> void:
	take = index
	take_label.text = "Original" if index == 0 else "Proposed"
	if frames.size() == 2: show_frame(current_frame)

func _input(event: InputEvent) -> void:
	if not review_controls.visible or tool_panel.visible or not event is InputEventKey or not event.pressed: return
	match event.keycode:
		KEY_LEFT: set_take(0)
		KEY_RIGHT: set_take(1)
		_: return
	get_viewport().set_input_as_handled()

func toggle_camera() -> void:
	view_index = 1-view_index
	if frames.size() == 2: show_frame(current_frame)

func skip() -> void:
	if manifests.is_empty() or review_pid > 0: return
	queue_next()
	skipped[selected_id] = true
	refresh_proposals()

func queue_next() -> void:
	var selection := proposal_list.get_selected_items()
	if not selection.is_empty():
		next_id = str(manifests[(selection[0]+1)%manifests.size()].id)

func decide(action: String) -> void:
	var selection := proposal_list.get_selected_items()
	if selection.is_empty() or review_pid > 0: return
	if action in ["Accept","Reject"]: queue_next()
	var entry := manifests[selection[0]]
	var script := ProjectSettings.globalize_path("res://tools/iterate.ps1")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Policy.DIRECTORY))
	result_log = ProjectSettings.globalize_path(Policy.DIRECTORY+"/review-%d.txt" % Time.get_ticks_usec())
	var wrapper := ProjectSettings.globalize_path("res://tools/iteration_decision.ps1")
	var feedback := Marshalls.utf8_to_base64(note.text)
	review_pid = OS.create_process("pwsh.exe",["-NoProfile","-WindowStyle","Hidden","-File",wrapper,
		script,action,str(entry.id),result_log,str(int(seed_input.value)),str(int(point_input.value)),feedback if not feedback.is_empty() else "-"])
	accept.disabled = review_pid > 0
	details.text = "Could not open the review tool." if review_pid < 0 else "Working…"
