extends SceneTree

func _initialize() -> void:
	check.call_deferred()

func check() -> void:
	change_scene_to_file("res://scenes/career_hitting_lesson.tscn")
	await scene_changed
	var game=current_scene
	var timing=root.get_node("ContactTiming")
	var clip:=""
	var meter:=false
	var stamina:=false
	var early:=false
	var bright:=false
	var fading:=false
	var faded:=false
	var sent:=false
	var released:=false
	game.enter_hitting_turn()
	for i in 2400:
		await process_frame
		if game.phase=="receive_toss" and not released:
			if not sent:
				pad(game,true)
				sent=true
			if game.rings.displayed_timing.has(game.hitter):
				var ring=game.rings.floor_rings[game.hitter]
				var fill=ring.get_surface_override_material(1)
				stamina=ring.is_visible_in_tree() and absf(fill.get_shader_parameter("remaining")-game.hitter.stamina.fraction())<.01
				meter=meter or (ring.get_child_count()>0 and ring.get_child(0).is_visible_in_tree())
			if not game.motion.is_empty():
				clip=str(game.motion.id)
				if game.elapsed>game.receive_at-.28:
					pad(game,false)
					released=true
		if released and timing.caption.text.begins_with("Reception   Missed / Early"):
			early=true
			if timing.caption.visible and timing.caption.modulate.a>.95: bright=true
			if bright and timing.caption.modulate.a<.8: fading=true
			if fading and not timing.caption.visible:
				faded=true
				break
	print("HUD: mapped clip=",clip," stamina=",stamina," held ring=",meter," early miss=",early," full opacity=",bright," fading=",fading," hidden=",faded)
	quit(0 if clip!="" and meter and stamina and early and bright and faded else 1)

func pad(game,pressed:bool) -> void:
	var event:=InputEventJoypadButton.new()
	event.button_index=game.Xbox.physical(JOY_BUTTON_A)
	event.pressed=pressed
	game._input(event)
