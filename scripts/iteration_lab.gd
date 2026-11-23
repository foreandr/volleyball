extends Control

const Policy = preload("res://scripts/cpu_policy.gd")
var status: Label
var duration: SpinBox
var background_task: Button
var clock := 0.0
var proposal_list: ItemList
var details: Label
var manifests: Array[Dictionary] = []
var previews: Array[TextureRect] = []
var choices: Array[Button] = []
var tool_panel: VBoxContainer
var proposal_title: Label
var proposal_count: Label
var proposal_description: Label
var review_controls: HBoxContainer
var listen_controls: HBoxContainer
var comparison_audio: AudioStreamPlayer
var audio_previews: Array[AudioStreamWAV] = []
var restore_master_mute := false
var frame_size := Vector2i(320,180)
var skipped := {}
var next_id := ""
var frames: Array[Image] = []
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
var finding_popup: Label
var finding_fade: Tween
var last_finding := ""

func _ready() -> void:
	MenuPresentation.backdrop(self,false)
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
	proposal_count = label("",16)
	header.add_child(proposal_count)
	tool_panel = VBoxContainer.new()
	tool_panel.hide()
	background_task = button("Start background task",toggle_background_task)
	header.add_child(background_task)
	header.add_child(button("Tools",func(): tool_panel.visible = not tool_panel.visible))
	header.add_child(button("Back",func(): get_tree().change_scene_to_file("res://scenes/main.tscn")))

	proposal_description = label("",16)
	proposal_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	proposal_description.add_theme_color_override("font_color",Color("#c3ceda"))
	proposal_description.hide()
	layout.add_child(proposal_description)

	var comparison := AspectRatioContainer.new()
	comparison.ratio = 3.3
	comparison.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(comparison)
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation",12)
	comparison.add_child(pair)
	pair.add_child(clip_choice("Original","Keep the original and move to the next proposal","Reject"))
	pair.add_child(clip_choice("Proposed","Apply this change and move to the next proposal","Accept"))

	listen_controls = HBoxContainer.new()
	listen_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	listen_controls.add_child(button("Listen to Original",listen_to_comparison.bind(0)))
	listen_controls.add_child(button("Listen to Proposed",listen_to_comparison.bind(1)))
	listen_controls.hide()
	layout.add_child(listen_controls)
	comparison_audio = AudioStreamPlayer.new()
	comparison_audio.finished.connect(stop_comparison_audio)
	add_child(comparison_audio)

	review_controls = HBoxContainer.new()
	review_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_child(review_controls)
	var skip_button := button("Skip",skip)
	skip_button.custom_minimum_size = Vector2(76,38)
	review_controls.add_child(skip_button)
	review_controls.add_child(button("Try a middle version",decide.bind("Feedback",
		"Try a version halfway between Original and Proposed for the highlighted motion. Retest it and show a new comparison.")))
	details = label("",16)
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(details)
	layout.add_child(tool_panel)

	var controls := HBoxContainer.new()
	tool_panel.add_child(controls)
	controls.add_child(label("Training speed",16))
	controls.add_child(StorySession.iteration_run.speed_picker())
	duration = number_box(0,0,720,"min")
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
	note = LineEdit.new()
	note.placeholder_text = "Feedback"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(note)
	actions.add_child(button("Send back",decide.bind("Feedback")))
	build_finding_popup()
	refresh_proposals()
	var run = StorySession.iteration_run
	last_finding = finding_key(run.status())
	if not run.lab_auto_started and DisplayServer.get_name() != "headless":
		run.lab_auto_started = true
		if not run.status().running and not run.start(int(duration.value)):
			details.text = "Could not start training."
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

func clip_choice(caption: String, hint: String, action: String) -> Button:
	var choice := button("",decide.bind(action))
	choice.tooltip_text = hint
	choice.accessibility_name = caption
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choice.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 6
	content.offset_top = 5
	content.offset_right = -6
	content.offset_bottom = -6
	var heading := label(caption,16)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(heading)
	var preview := TextureRect.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(preview)
	previews.append(preview)
	choices.append(choice)
	return choice

func clear_comparison() -> void:
	stop_comparison_audio()
	audio_previews.clear()
	listen_controls.hide()
	for preview in previews: preview.texture = null
	for choice in choices: choice.disabled = true

func listen_to_comparison(side: int) -> void:
	if audio_previews.size() != 2 or review_pid > 0: return
	stop_comparison_audio()
	restore_master_mute = AudioServer.is_bus_mute(0)
	if restore_master_mute: AudioServer.set_bus_mute(0,false)
	comparison_audio.stream = audio_previews[side]
	comparison_audio.play()

func stop_comparison_audio() -> void:
	if is_instance_valid(comparison_audio): comparison_audio.stop()
	if restore_master_mute:
		AudioServer.set_bus_mute(0,true)
		restore_master_mute = false

func _exit_tree() -> void:
	stop_comparison_audio()

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
	show_new_finding(data)
	var learned := Policy.read_json(Policy.PATH)
	background_task.disabled = data.state == "stopping"
	background_task.text = "Stopping…" if background_task.disabled else ("Stop background task" if running else "Start background task")
	var state := str(data.state).capitalize()
	status.text = "%s   ·   %d matches this run   ·   %d review flags   ·   %d training matches saved" % [
		state,int(data.get("matches",0)),int(data.get("observations",0)),int(learned.get("matches",0))]
	if review_pid > 0 and not OS.is_process_running(review_pid):
		review_pid = -1
		var message := FileAccess.get_file_as_string(result_log).strip_edges() if FileAccess.file_exists(result_log) else "Error: Review tool did not return a result."
		refresh_proposals()
		details.text = message.get_slice("\n",0)
	elif review_pid < 0:
		var pending := read_pending_proposals()
		if pending != manifests: update_proposals(pending, true)

func build_finding_popup() -> void:
	finding_popup = label("",16)
	finding_popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	finding_popup.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	finding_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := StyleBoxFlat.new()
	badge.bg_color = Color("#24384b")
	badge.set_corner_radius_all(8)
	finding_popup.add_theme_stylebox_override("normal",badge)
	add_child(finding_popup)
	finding_popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	finding_popup.offset_left = -240
	finding_popup.offset_right = 240
	finding_popup.offset_top = 108
	finding_popup.offset_bottom = 146
	finding_popup.hide()

func finding_key(data: Dictionary) -> String:
	var finding: Dictionary = data.get("latest_finding",{})
	if finding.is_empty(): return ""
	return "%s:%s" % [data.get("run",""),finding.get("number",0)]

func show_new_finding(data: Dictionary) -> void:
	var key := finding_key(data)
	if key.is_empty() or key == last_finding: return
	last_finding = key
	var finding: Dictionary = data.latest_finding
	var action := str(finding.get("action",""))
	finding_popup.text = str(finding.type)
	if not action.is_empty() and not action.contains("/"):
		finding_popup.text += " · "+action.capitalize()
	if finding_fade != null: finding_fade.kill()
	finding_popup.modulate.a = 1.0
	finding_popup.show()
	finding_fade = create_tween()
	finding_fade.tween_interval(2.3)
	finding_fade.tween_property(finding_popup,"modulate:a",0.0,0.35)
	finding_fade.tween_callback(finding_popup.hide)

func toggle_background_task() -> void:
	var run = StorySession.iteration_run
	var running: bool = run.status().running
	var changed: bool = run.stop() if running else run.start(int(duration.value))
	refresh_status()
	if not changed: details.text = "Could not stop training." if running else "Could not start training."

func watch_latest() -> void:
	var latest: Dictionary = StorySession.iteration_run.status().get("latest_finding",{})
	var worker_replay := str(latest.get("replay",""))
	var demo_directory: String = preload("res://scripts/match_review.gd").DIRECTORY
	var demo_path := ""
	if DirAccess.dir_exists_absolute(demo_directory):
		var clips := DirAccess.get_files_at(demo_directory)
		clips.sort()
		for index in range(clips.size()-1,-1,-1):
			if clips[index].ends_with(".vreplay"):
				demo_path = demo_directory.path_join(clips[index])
				break
	if not worker_replay.is_empty() and FileAccess.file_exists(worker_replay):
		if demo_path.is_empty() or FileAccess.get_modified_time(worker_replay) >= FileAccess.get_modified_time(demo_path):
			open_finding(worker_replay)
		else: open_finding(demo_path)
		return
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
	update_proposals(read_pending_proposals(), false)

func read_pending_proposals() -> Array[Dictionary]:
	var pending: Array[Dictionary] = []
	var root := ProjectSettings.globalize_path("res://work/iterations")
	for id in DirAccess.get_directories_at(root):
		var manifest := Policy.read_json(root.path_join(id).path_join("proposal.json"))
		if manifest.get("status","") != "pending" or skipped.has(id): continue
		manifest["directory"] = root.path_join(id)
		pending.append(manifest)
	return pending

func update_proposals(pending: Array[Dictionary], preserve_clip: bool) -> void:
	var previous := proposal_list.get_selected_items()
	var playing_entry := manifests[previous[0]] if preserve_clip and not previous.is_empty() else {}
	proposal_list.clear()
	manifests = pending
	proposal_count.text = "%d to review" % manifests.size()
	var selected := -1
	var next_index := 0
	for index in manifests.size():
		var manifest := manifests[index]
		var id := str(manifest.id)
		if id == selected_id: selected = index
		if id == next_id: next_index = index
		proposal_list.add_item(str(manifest.get("title",id)))
	if not manifests.is_empty():
		if selected < 0: selected = next_index
		proposal_list.select(selected)
		if playing_entry != manifests[selected]: select_proposal(selected)
	else:
		frames.clear()
		clear_comparison()
		proposal_title.text = "Iteration Lab"
		proposal_description.hide()
		review_controls.hide()
		details.text = "No proposals to review."

func select_proposal(index: int) -> void:
	var entry := manifests[index]
	selected_id = str(entry.id)
	frames.clear()
	playback = false
	clear_comparison()
	proposal_title.text = str(entry.get("short_title",entry.get("title",selected_id)))
	proposal_description.text = str(entry.get("description",entry.get("note",""))).strip_edges()
	proposal_description.visible = not proposal_description.text.is_empty()
	details.text = ""
	review_controls.show()
	view_index = 0
	var root := str(entry.directory).path_join("clips").path_join(str(entry.candidate).left(12))
	if not DirAccess.dir_exists_absolute(root):
		details.text = "No preview yet. Render it from Tools."
		return
	var audio_root := root.path_join("audio")
	if FileAccess.file_exists(audio_root.path_join("before.wav")) and FileAccess.file_exists(audio_root.path_join("after.wav")):
		for side in ["before","after"]:
			var stream := AudioStreamWAV.load_from_file(audio_root.path_join(side+".wav"))
			if stream != null: audio_previews.append(stream)
		if audio_previews.size() == 2:
			listen_controls.show()
			for side in previews.size():
				var name_ := "before" if side == 0 else "after"
				var waveform := audio_root.path_join(name_+".png")
				if FileAccess.file_exists(waveform):
					var sample := Image.load_from_file(waveform)
					if not sample.is_empty(): previews[side].texture = ImageTexture.create_from_image(sample)
			for choice in choices: choice.disabled = review_pid > 0
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
				if not sample.is_empty(): frames.append(sample)
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
				for choice in choices: choice.disabled = review_pid > 0
				show_frame(maxi(0,slow_frames.x) if loop_focus and playback_speed == 0.0 else 0)
				return
			frames.clear()
	details.text = "No preview yet. Render it from Tools."

func show_frame(index: int) -> void:
	current_frame = index
	var region := Rect2i(index*frame_size.x,view_index*frame_size.y,frame_size.x,frame_size.y)
	for side in previews.size():
		var frame := frames[side].get_region(region)
		var texture := previews[side].texture as ImageTexture
		if texture == null:
			previews[side].texture = ImageTexture.create_from_image(frame)
		else:
			texture.update(frame)

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

func decide(action: String, feedback_override := "") -> void:
	var selection := proposal_list.get_selected_items()
	if selection.is_empty() or review_pid > 0: return
	stop_comparison_audio()
	if action in ["Accept","Reject","Feedback"]: queue_next()
	var entry := manifests[selection[0]]
	var script := ProjectSettings.globalize_path("res://tools/iterate.ps1")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Policy.DIRECTORY))
	result_log = ProjectSettings.globalize_path(Policy.DIRECTORY+"/review-%d.txt" % Time.get_ticks_usec())
	var wrapper := ProjectSettings.globalize_path("res://tools/iteration_decision.ps1")
	var feedback := Marshalls.utf8_to_base64(note.text if feedback_override.is_empty() else feedback_override)
	review_pid = OS.create_process("pwsh.exe",["-NoProfile","-WindowStyle","Hidden","-File",wrapper,
		script,action,str(entry.id),result_log,str(int(seed_input.value)),str(int(point_input.value)),feedback if not feedback.is_empty() else "-",str(entry.candidate)])
	for choice in choices: choice.disabled = review_pid > 0
	details.text = "Could not open the review tool." if review_pid < 0 else "Working…"
