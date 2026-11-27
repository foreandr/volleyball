extends SceneTree

# Run with Godot --headless --fixed-fps 60 --path . --script tools/check_court_feedback.gd.
func _initialize() -> void:
	check.call_deferred()

func check() -> void:
	change_scene_to_file("res://scenes/career_hitting_lesson.tscn")
	await scene_changed
	var drill=current_scene
	var seen:Dictionary={}
	for frame in 1800:
		await process_frame
		if drill.phase in ["receive_toss","pass","set","spike"] and drill.landing_ring.is_visible_in_tree():
			seen[drill.phase]=true
		if seen.size()==4: break
	if seen.size()!=4:
		fail("Demo missing a visible flight marker: "+str(seen))
		return
	drill.enter_hitting_turn()
	var target:=Vector3.INF
	var visible_frames:=0
	for frame in 1800:
		await process_frame
		if drill.phase=="receive_toss":
			if not drill.landing_ring.is_visible_in_tree():
				fail("Missing human coach-toss marker")
				return
			var point:Vector3=drill.landing_ring.global_position
			if not target.is_finite(): target=point
			if point.distance_to(target)>.001:
				fail("Untouched toss marker moved")
				return
			visible_frames+=1
		elif visible_frames>0 and drill.phase=="drop":
			var error:float=(drill.ball.position-target).slide(Vector3.UP).length()
			if error>.025:
				fail("Missed feed landed %.3f m from its marker"%error)
				return
			await process_frame
			if not drill.court_boundary.visible or drill.court_boundary.verdict!=1:
				fail("In-bounds landing did not flash")
				return
			print("Court feedback passed: ",seen.keys(),", human toss visible for ",visible_frames," frames, landing error ",error," m")
			quit()
			return
	fail("Human toss did not reach the floor")

func fail(reason:String) -> void:
	push_error(reason)
	quit(1)
