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
var before_view: TextureRect
var after_view: TextureRect
var frames: Array[Texture2D] = []
var playback := false
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
	background.color = Color("#111c28")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,26)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",10)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := label("Iteration Lab",28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(button("Back",func(): get_tree().change_scene_to_file("res://scenes/main.tscn")))
	var controls := HBoxContainer.new()
	layout.add_child(controls)
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
	layout.add_child(status)
	var row := HSplitContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(row)
	proposal_list = ItemList.new()
	proposal_list.custom_minimum_size.x = 290
	proposal_list.item_selected.connect(select_proposal)
	row.add_child(proposal_list)
	var review := VBoxContainer.new()
	review.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(review)
	details = label("",16)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	review.add_child(details)
	var images := HBoxContainer.new()
	images.size_flags_vertical = Control.SIZE_EXPAND_FILL
	review.add_child(images)
	before_view = view_column(images,"Before")
	after_view = view_column(images,"After")
	var timeline := HBoxContainer.new()
	review.add_child(timeline)
	timeline.add_child(button("Play / pause",func(): playback = not playback))
	timeline.add_child(button("Camera",toggle_camera))
	timeline.add_child(label("Seed",16))
	seed_input = number_box(41,0,2147483647,"")
	timeline.add_child(seed_input)
	timeline.add_child(label("Point",16))
	point_input = number_box(1,1,100,"")
	timeline.add_child(point_input)
	timeline.add_child(button("Render comparison",decide.bind("Clip")))
	var actions := HBoxContainer.new()
	review.add_child(actions)
	actions.add_child(button("Refresh",refresh_proposals))
	actions.add_child(button("Re-test",decide.bind("Review")))
	actions.add_child(button("Accept",decide.bind("Accept")))
	actions.add_child(button("Reject",decide.bind("Reject")))
	actions.add_child(button("Skip",skip))
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

func view_column(parent: Node, caption: String) -> TextureRect:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	column.add_child(label(caption,16))
	var preview := TextureRect.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(preview)
	return preview

func _process(delta: float) -> void:
	clock += delta
	if clock >= 0.8:
		clock = 0.0
		refresh_status()
	if playback and frames.size() == 2:
		frame_time += delta
		var count := frames[0].get_width()/320
		var next := floori(frame_time/(0.083333 if count >= 24 else 0.16))%count
		if current_frame != next: show_frame(next)

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
		var message := FileAccess.get_file_as_string(result_log).strip_edges() if FileAccess.file_exists(result_log) else "Review tool did not return a result."
		refresh_proposals()
		details.text = message

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
	before_view.texture = null
	after_view.texture = null
	details.text = "No proposals awaiting review."
	var root := ProjectSettings.globalize_path("res://work/iterations")
	if not DirAccess.dir_exists_absolute(root): return
	var selected := 0
	for id in DirAccess.get_directories_at(root):
		var manifest := Policy.read_json(root.path_join(id).path_join("proposal.json"))
		if manifest.get("status","") != "pending": continue
		manifest["directory"] = root.path_join(id)
		if id == selected_id: selected = manifests.size()
		manifests.append(manifest)
		proposal_list.add_item(str(manifest.get("title",id)))
	if not manifests.is_empty():
		proposal_list.select(selected)
		select_proposal(selected)

func select_proposal(index: int) -> void:
	var entry := manifests[index]
	selected_id = str(entry.id)
	frames.clear()
	playback = false
	before_view.texture = null
	after_view.texture = null
	details.text = str(entry.get("note",""))
	var root := str(entry.directory).path_join("clips").path_join(str(entry.candidate).left(12))
	if not DirAccess.dir_exists_absolute(root):
		details.text += "\nChoose a seed and point to render a comparison."
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
			if frames.size() == 2:
				frame_time = 0.0
				show_frame(0)
				return
			frames.clear()
	details.text += "\nChoose a seed and point to render a comparison."

func show_frame(index: int) -> void:
	current_frame = index
	for view in 2:
		var source := frames[view]
		var atlas := AtlasTexture.new()
		atlas.atlas = source
		atlas.region = Rect2(index*320,view_index*180,320,180)
		if view == 0: before_view.texture = atlas
		else: after_view.texture = atlas

func toggle_camera() -> void:
	view_index = 1-view_index
	if frames.size() == 2: show_frame(current_frame)

func skip() -> void:
	var selection := proposal_list.get_selected_items()
	if selection.is_empty() or manifests.is_empty(): return
	var next := (selection[0]+1)%manifests.size()
	proposal_list.select(next)
	select_proposal(next)

func decide(action: String) -> void:
	var selection := proposal_list.get_selected_items()
	if selection.is_empty() or review_pid > 0: return
	var entry := manifests[selection[0]]
	var script := ProjectSettings.globalize_path("res://tools/iterate.ps1")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Policy.DIRECTORY))
	result_log = ProjectSettings.globalize_path(Policy.DIRECTORY+"/review-%d.txt" % Time.get_ticks_usec())
	var wrapper := ProjectSettings.globalize_path("res://tools/iteration_decision.ps1")
	var feedback := Marshalls.utf8_to_base64(note.text)
	review_pid = OS.create_process("pwsh.exe",["-NoProfile","-WindowStyle","Hidden","-File",wrapper,
		script,action,str(entry.id),result_log,str(int(seed_input.value)),str(int(point_input.value)),feedback if not feedback.is_empty() else "-"])
	details.text = "Could not open the review tool." if review_pid < 0 else "Working…"
