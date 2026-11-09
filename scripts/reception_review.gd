extends HBoxContainer

const Flight = preload("res://scripts/pass_flight.gd")
const CASES := [
	[1,"Forward step",Vector3(0,0,0.42),Vector3(0,-5,-2)],
	[1,"Forward-right step",Vector3(-0.30,0,0.30),Vector3(0,-5,-3)],
	[1,"Right step",Vector3(-0.42,0,0),Vector3(0,-5,-3)],
	[1,"Back-right step",Vector3(-0.30,0,-0.30),Vector3(0,-5,-2)],
	[1,"Back step",Vector3(0,0,-0.42),Vector3(0,-5,-2)],
	[1,"Back-left step",Vector3(0.30,0,-0.30),Vector3(0,-5,-2)],
	[1,"Left step",Vector3(0.42,0,0),Vector3(0,-5,-3)],
	[1,"Forward-left step",Vector3(0.30,0,0.30),Vector3(0,-5,-3)],
	[2,"Forward lunge",Vector3(0,0,0.84),Vector3(0,-5,-2)],
	[2,"Forward-right reach",Vector3(-0.59,0,0.59),Vector3(0,-5,-3)],
	[2,"Right lunge",Vector3(-0.85,0,0),Vector3(0,-7,-3)],
	[2,"Back-right lunge",Vector3(-0.54,0,-0.52),Vector3(0,-7,-2)],
	[2,"Backward lunge",Vector3(0,0,-0.70),Vector3(0,-5,-3)],
	[2,"Back-left lunge",Vector3(0.54,0,-0.52),Vector3(0,-7,-2)],
	[2,"Left lunge",Vector3(0.85,0,0),Vector3(0,-7,-3)],
	[2,"Forward-left reach",Vector3(0.59,0,0.59),Vector3(0,-5,-3)],
]
const FEED_TIME := 0.70
const READY_POSITION := Vector3(0,0.04,-3.4)
const SLOW_RATE := 0.35
var page
var active := false
var paused := false
var finished := false
var loop_current := false
var slow_motion := false
var frozen := false
var animator_before_freeze := true
var index := 0
var original_transform: Transform3D
var original_control := false
var original_feed: Dictionary
var original_target: Dictionary
var review_clip: Animation
var offset := Vector3.ZERO
var released := false
var counter: Label
var play_button: Button
var previous_button: Button
var next_button: Button
var stop_button: Button
var loop_button: Button
var slow_button: Button
var freeze_button: Button
var title_card: PanelContainer
var title_count: Label
var title_move: Label

func _init(host: Control) -> void:
	page = host
	add_theme_constant_override("separation",8)
	counter = page.label("",17)
	counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(counter)
	play_button = page.button("Play all",toggle_play)
	add_child(play_button)
	previous_button = page.button("Previous",func(): load_case(posmod(index-1,CASES.size())))
	add_child(previous_button)
	next_button = page.button("Next",func(): load_case(posmod(index+1,CASES.size())))
	add_child(next_button)
	loop_button = page.button("Loop clip",toggle_loop)
	loop_button.toggle_mode = true
	add_child(loop_button)
	slow_button = page.button("Slow mo",toggle_slow_motion)
	slow_button.toggle_mode = true
	slow_button.tooltip_text = "Play the reception at 35% speed"
	add_child(slow_button)
	freeze_button = page.button("Freeze pose",toggle_freeze)
	freeze_button.toggle_mode = true
	add_child(freeze_button)
	stop_button = page.button("Stop",stop)
	add_child(stop_button)
	build_title_card()
	update_controls()
	hide()

func build_title_card() -> void:
	title_card = PanelContainer.new()
	title_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.timing_meter.get_parent().add_child(title_card)
	title_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title_card.offset_left = -142
	title_card.offset_right = 142
	title_card.offset_top = 34
	title_card.offset_bottom = 116
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055,0.10,0.16,0.90)
	panel_style.border_color = Color("526a83")
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 10
	title_card.add_theme_stylebox_override("panel",panel_style)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override("separation",0)
	title_card.add_child(text)
	title_count = page.label("",31)
	title_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_count.add_theme_color_override("font_color",Color("ffce70"))
	title_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(title_count)
	title_move = page.label("",16)
	title_move.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_move.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(title_move)
	title_card.hide()

func update_title_card(elapsed: float) -> void:
	var time := elapsed+FEED_TIME
	var opacity := smoothstep(0.0,0.22,time)*(1.0-smoothstep(0.94,1.42,time))
	title_card.modulate.a = opacity
	title_card.visible = opacity > 0.0

func update_controls() -> void:
	var progress := "%d/%d  |  Distance %d  |  %s" % [index+1,CASES.size(),CASES[index][0],CASES[index][1]] if active else "Forearm Reception Animations  |  %d available" % CASES.size()
	counter.text = progress
	play_button.text = "Replay all" if finished else ("Resume" if paused else ("Pause" if active else "Play all"))
	loop_button.set_pressed_no_signal(loop_current)
	loop_button.text = "Looping clip" if loop_current else "Loop clip"
	slow_button.set_pressed_no_signal(slow_motion)
	slow_button.text = "Slow mo on" if slow_motion else "Slow mo"
	freeze_button.set_pressed_no_signal(frozen)
	freeze_button.text = "Resume pose" if frozen else "Freeze pose"
	for button in [previous_button,next_button,loop_button,stop_button]: button.disabled = not active

func toggle_play() -> void:
	if not page.reception_drill_active(): return
	if not active:
		set_frozen(false)
		original_transform = page.preview_player.transform
		original_control = page.player_controls.active
		page.player_controls.set_active(false)
		page.set_cpu_arrows_pinned(false)
		prepare_review_clip()
		active = true
		load_case(0)
	elif finished:
		paused = false
		load_case(0)
	else:
		paused = not paused
	update_controls()

func toggle_freeze() -> void:
	if page.reception_drill_active(): set_frozen(not frozen)

func set_frozen(value: bool) -> void:
	if frozen == value: return
	var animator: AnimationPlayer = page.preview_player.animator
	if value:
		animator_before_freeze = animator.active
		animator.active = false
	else:
		animator.active = animator_before_freeze
	frozen = value
	update_controls()

func toggle_slow_motion() -> void:
	slow_motion = not slow_motion
	update_controls()

func playback_delta(delta: float) -> float:
	return delta*SLOW_RATE if slow_motion else delta

func toggle_loop() -> void:
	if not active: return
	loop_current = not loop_current
	if loop_current:
		paused = false
		if finished: load_case(index)
	update_controls()

func prepare_review_clip() -> void:
	var actor: Node3D = page.preview_player
	original_feed = actor.get_meta("feed_settings",{})
	original_target = actor.get_meta("pass_target",{})
	actor.position = READY_POSITION
	actor.rotation.y = 0.0
	actor.set_meta("feed_settings",{"speed":18.6,"source":Vector2(0,14.2),"source_height":3.3,"fit":"angle","spin":"No spin"})
	actor.set_meta("pass_target",{"position":Vector2(0,1.6),"height":4.9,"fit":"height"})
	var solver = preload("res://scripts/pass_trajectory_solver.gd").new(actor,page.source_clip)
	review_clip = solver.solve(75.0,5.0).clip
	actor.install_custom(review_clip,"preview",false)
	page.ball_preview.configure(actor,review_clip)

func load_case(next_index: int) -> void:
	index = next_index
	finished = false
	released = false
	var actor: Node3D = page.preview_player
	var ball = page.ball_preview
	page.player_controls.clear_receive_transition()
	page.player_controls.reset_reach()
	page.timing_meter.reset_serve()
	actor.transform = original_transform
	actor.position = READY_POSITION
	actor.rotation.y = 0.0
	actor.get_node("DirectionArrows").select_direction(0)
	actor.animator.play("custom_preview/clip",0)
	actor.animator.seek(0.0,true)
	actor.animator.pause()
	var relative: Vector3 = CASES[index][2]
	offset = actor.global_basis.orthonormalized()*relative
	var velocity: Vector3 = actor.global_basis.orthonormalized()*CASES[index][3]
	var aim: Vector3 = ball.platform(ball.contact_time).ball+offset
	var acceleration := Vector3.DOWN*Flight.GRAVITY
	ball.review_feed = {"aim":aim,"incoming":velocity,"acceleration":acceleration,"duration":FEED_TIME,
		"start":aim-velocity*FEED_TIME+acceleration*0.5*FEED_TIME*FEED_TIME,"side":Vector3.RIGHT,"valid":true}
	ball.recalculate()
	page.preview_clock = ball.contact_time-FEED_TIME
	title_count.text = "%d / %d" % [index+1,CASES.size()]
	title_move.text = "Distance %d  |  %s" % [CASES[index][0],CASES[index][1]]
	update_title_card(-FEED_TIME)
	page.drill_status.text = "CPU review  |  Automatic receive"
	page.distance_status.text = "Distance %d  |  %s
Distance 3  |  Dive planned" % [CASES[index][0],CASES[index][1]]
	ball.tick(page.preview_clock,false)
	ball.update_practice_aim(true)
	update_controls()

func step(delta: float) -> void:
	page.pan_camera(page.player_controls.movement_input(),delta)
	if paused: return
	delta = playback_delta(delta)
	var ball = page.ball_preview
	var previous: float = page.preview_clock
	page.preview_clock += delta
	var elapsed: float = page.preview_clock-ball.contact_time
	update_title_card(elapsed)
	if elapsed >= -0.25 and elapsed < 0.28:
		var pose_offset := minf(0.0,elapsed+0.15)*1.4+maxf(0.0,elapsed)*1.4
		page.player_controls.play_receive_pose(delta,offset,pose_offset)
		if elapsed >= -0.03:
			ball.try_practice_pass(previous,page.preview_clock,0.16)
	elif elapsed >= 0.28 and not released:
		released = true
		page.player_controls.end_receive_pose()
		page.player_controls.reset_reach()
		page.preview_player.animator.seek(0.0,true)
	if released:
		page.preview_player.animator.seek(0.0,true)
		page.player_controls.blend_receive_recovery(delta)
	var end: float = maxf(ball.cycle_end(),ball.contact_time+0.65)
	ball.tick(minf(page.preview_clock,end),true)
	ball.update_practice_aim(true)
	if page.preview_clock < end: return
	page.preview_clock = end
	if not page.player_controls.settle_for_next_feed(READY_POSITION,0.0,delta):
		ball.ball.hide()
		return
	if loop_current:
		load_case(index)
	elif index+1 < CASES.size():
		load_case(index+1)
	else:
		finished = true
		paused = true
		update_controls()

func stop(restore_control := true) -> void:
	set_frozen(false)
	if not active: return
	active = false
	loop_current = false
	title_card.hide()
	paused = false
	finished = false
	page.player_controls.clear_receive_transition()
	page.player_controls.reset_reach()
	var actor: Node3D = page.preview_player
	actor.transform = original_transform
	actor.set_meta("feed_settings",original_feed)
	actor.set_meta("pass_target",original_target)
	actor.install_custom(page.render_clip,"preview",false)
	actor.animator.seek(0.0,true)
	actor.animator.pause()
	page.ball_preview.review_feed.clear()
	page.angle_control.apply_feed_aim(actor)
	page.ball_preview.configure(actor,page.render_clip)
	page.preview_clock = minf(0.0,page.ball_preview.contact_time-page.ball_preview.feed_duration)
	page.ball_preview.tick(page.preview_clock,false)
	if restore_control and original_control: page.player_controls.set_active(true)
	update_controls()
