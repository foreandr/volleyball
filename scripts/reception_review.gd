extends HBoxContainer

const Flight = preload("res://scripts/pass_flight.gd")
const CASES := [
	[1,"Planted pass",Vector3.ZERO,Vector3(0,-5,-3)],
	[1,"Left step",Vector3(0.40,0,0),Vector3(0,-5,-3)],
	[1,"Right step",Vector3(-0.40,0,0),Vector3(0,-5,-3)],
	[1,"Back step",Vector3(0,0,-0.40),Vector3(0,-5,-2)],
	[2,"Left lunge",Vector3(0.85,0,0),Vector3(0,-5,-4)],
	[2,"Right lunge",Vector3(-0.85,0,0),Vector3(0,-5,-4)],
	[2,"Forward lunge",Vector3(0,0,0.84),Vector3(0,-5,-2)],
	[2,"Back reach",Vector3(0,0,-0.78),Vector3(0,-5,-2)],
	[2,"High shoulder reach",Vector3(0,0.42,-0.20),Vector3(0,-3,-6.3)],
]
const FEED_TIME := 0.70
var page
var active := false
var paused := false
var finished := false
var index := 0
var original_transform: Transform3D
var original_control := false
var offset := Vector3.ZERO
var counter: Label
var play_button: Button
var previous_button: Button
var next_button: Button
var stop_button: Button

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
	stop_button = page.button("Stop",stop)
	add_child(stop_button)
	update_controls()
	hide()

func update_controls() -> void:
	var progress := "%d/%d  |  Distance %d  |  %s" % [index+1,CASES.size(),CASES[index][0],CASES[index][1]] if active else "Forearm Reception Animations  |  %d available" % CASES.size()
	counter.text = progress
	play_button.text = "Replay all" if finished else ("Resume" if paused else ("Pause" if active else "Play all"))
	for button in [previous_button,next_button,stop_button]: button.disabled = not active

func toggle_play() -> void:
	if not page.reception_drill_active(): return
	if not active:
		original_transform = page.preview_player.transform
		original_control = page.player_controls.active
		page.player_controls.set_active(false)
		active = true
		load_case(0)
	elif finished:
		paused = false
		load_case(0)
	else:
		paused = not paused
	update_controls()

func load_case(next_index: int) -> void:
	index = next_index
	finished = false
	var actor: Node3D = page.preview_player
	var ball = page.ball_preview
	page.player_controls.reset_reach()
	page.timing_meter.reset_serve()
	actor.transform = original_transform
	actor.position.x = clampf(actor.position.x,-2.5,2.5)
	actor.position.z = minf(actor.position.z,-2.0)
	var court_forward := Vector3(0,0,4)-actor.position
	actor.rotation.y = atan2(court_forward.x,court_forward.z)
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
	page.drill_status.text = "CPU review  |  Automatic receive"
	page.distance_status.text = "Distance %d  |  %s
Distance 3  |  Dive planned" % [CASES[index][0],CASES[index][1]]
	ball.tick(page.preview_clock,false)
	update_controls()

func step(delta: float) -> void:
	if paused: return
	var ball = page.ball_preview
	var previous: float = page.preview_clock
	page.preview_clock += delta
	var elapsed: float = page.preview_clock-ball.contact_time
	if elapsed >= -0.25:
		page.player_controls.hold_receive(delta,offset)
		if elapsed >= -0.03:
			ball.try_practice_pass(previous,page.preview_clock,0.16)
	var end: float = maxf(ball.cycle_end(),ball.contact_time+0.65)
	ball.tick(minf(page.preview_clock,end),true)
	if page.preview_clock < end: return
	if index+1 < CASES.size():
		load_case(index+1)
	else:
		finished = true
		paused = true
		update_controls()

func stop(restore_control := true) -> void:
	if not active: return
	active = false
	paused = false
	finished = false
	page.player_controls.reset_reach()
	page.preview_player.transform = original_transform
	page.ball_preview.review_feed.clear()
	page.angle_control.apply_feed_aim(page.preview_player)
	page.ball_preview.recalculate()
	page.preview_clock = minf(0.0,page.ball_preview.contact_time-page.ball_preview.feed_duration)
	page.ball_preview.tick(page.preview_clock,false)
	if restore_control and original_control: page.player_controls.set_active(true)
	update_controls()
