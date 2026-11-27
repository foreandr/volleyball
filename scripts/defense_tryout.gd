extends "res://scripts/digging_camp.gd"

var attack_in_play := false
var leaving_court := false

func start_drill() -> void:
	super.start_drill()
	cpu_defense=false
	target_marker.hide()
	title.text="DEFENSE EVALUATION"
	update_prompts("ready")

func build_rally_sliders() -> void:
	pass

func handle_drag(_event: InputEvent) -> bool:
	return false

func update_prompts(_next: String) -> void:
	if prompt_phase=="career_dig": return
	prompt_phase="career_dig"
	if Xbox.keyboard_prompts():
		Xbox.prompts(controls_row,[])
		var hint := Label.new()
		hint.text="Hold / release Space to dig"
		controls_row.add_child(hint)
	else: Xbox.prompts(controls_row,[[JOY_BUTTON_A,"Hold / release to dig"]])

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_BACK): return
	if event is InputEventKey and event.keycode==KEY_SPACE and not get_tree().paused and not replay_inspector.active:
		if not event.echo:
			if event.pressed:
				chosen_cell=Vector3i(-1,-1,-1)
				release_window=0.
			elif dig_held and phase=="serve_return": release_window=.18
			dig_held=event.pressed
		get_viewport().set_input_as_handled()
		return
	super._input(event)

func return_struck(actor: Node3D,point: Vector3,velocity: Vector3,spin: float) -> void:
	super.return_struck(actor,point,velocity,spin)
	attack_in_play=true

func next_serve() -> void:
	if leaving_court: return
	if attack_in_play:
		attack_in_play=false
		if CareerSession.record_defense(last_digger==hitter) and CareerSession.defense_finished:
			leaving_court=true
			set_process(false)
			MenuPresentation.load_scene.call_deferred("res://scenes/story.tscn")
			return
	var reps := int(CareerSession.data.get_value(CareerSession.key(),"defense_reps",0))
	var score := int(CareerSession.data.get_value(CareerSession.key(),"defense_score",0))
	homes=[FIVE,Vector3(-1.6,.04,-2.2)]
	floor_target=FIVE+Vector3([.1,-.66,.62,-.34,.39][reps],.105,.55)
	super.next_serve()
	cpu_defense=false
	title.text="DEFENSE EVALUATION"
	message.text="Dig %d of 5    /    %d up" % [reps+1,score]
