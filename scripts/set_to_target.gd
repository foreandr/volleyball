extends Node3D

const Flight = preload("res://scripts/pass_flight.gd")
const Match = preload("res://scripts/volleyball_match.gd")
const Player = preload("res://scripts/volleyball_player.gd")
const SOURCE := Vector3(0,2.85,12.95)
const RECEIVE_START := Vector3(0,0.04,-2.7)
const SETTER_START := Vector3(-1.45,0.04,0.4)
const PASS_TARGET := Vector3(0.55,3.35,1.50)
const LEFT_PIN := Vector3(3.55,0.065,3.28)
const STEP := 1.0/60.0

var game: Node3D
var trail: MultiMeshInstance3D
var running := false
var budget := 0.0

func configure(status: Label) -> void:
	var setter := Player.new()
	add_child(setter)
	game = Match.new()
	game.spectator = true
	add_child(game)
	var score := Label.new()
	add_child(score)
	score.hide()
	game.configure(setter,score,status,"Set to Target",2,false,false)
	game.set_ball_sound(false)
	game.passing_skill = 100.0
	game.setting_skill = 100.0
	game.drill_set_pin = LEFT_PIN
	trail = MultiMeshInstance3D.new()
	trail.multimesh = MultiMesh.new()
	trail.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var dot := SphereMesh.new()
	dot.radius = 0.035
	dot.height = 0.07
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color("3bafff")
	blue.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.material = blue
	trail.multimesh.mesh = dot
	add_child(trail)
	reset_players()
	game.ball.global_position = SOURCE
	game.ball.show()
	status.text = "Ready"

func reset_players() -> void:
	game.begin_point()
	game.phase = game.Phase.FINISHED
	game.serve.ball.hide()
	game.aim_ring.hide()
	game.trajectory_node.hide()
	game.score_label.hide()
	for index in game.players.size():
		game.players[index].visible = index < 2
	game.players[0].position = SETTER_START
	game.players[1].position = RECEIVE_START

func launch_rep() -> void:
	reset_players()
	trail.hide()
	budget = 0.0
	game.phase = game.Phase.LIVE
	game.drill_pass_target = PASS_TARGET
	var duration := 1.62
	var landing := Vector3(0,Flight.FLOOR,-4.0)
	var acceleration := Vector3.DOWN*Flight.GRAVITY
	var velocity := (landing-SOURCE)/duration-acceleration*duration*0.5
	game.launch(SOURCE,velocity,"serve",2,0.0,-1,Vector3.ZERO,acceleration)
	game.receiving_team = 0
	game.cpu_choice = 1
	game.cpu_technique = 0
	game.info.text = "Float serve"
	running = true

func _physics_process(delta: float) -> void:
	if not running: return
	budget += delta
	while running and budget+0.000001 >= STEP:
		budget -= STEP
		step_rep()

func step_rep() -> void:
	game.match_clock += STEP
	var previous: float = game.elapsed
	var kind: String = game.flight_kind
	game.elapsed = minf(previous+STEP,game.flight_end())
	game.ball.global_position = game.path_point(game.elapsed)
	game.animated.fill(false)
	game.advance_recoveries(STEP)
	game.advance_set_jumps(STEP)
	game.advance_ball_spin(STEP)
	if kind in ["serve","pass"]:
		game.tick_receive(STEP,previous)
		if game.flight_kind == "pass" and kind == "serve":
			game.cpu_choice = 0
			game.cpu_technique = 1
			game.info.text = "Pass to setter"
		elif game.flight_kind == "set":
			show_set_path()
			game.info.text = "Set to left pin"
	game.advance_idle_players(STEP)
	if game.elapsed >= game.flight_end():
		running = false
		game.phase = game.Phase.FINISHED
		if kind == "serve": game.info.text = "Missed serve"
		elif kind == "pass": game.info.text = "Missed set"

func show_set_path() -> void:
	var duration: float = game.flight_end()
	trail.multimesh.instance_count = 32
	for index in 32:
		var point: Vector3 = game.path_point(duration*index/31.0)
		trail.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,point))
	trail.show()
