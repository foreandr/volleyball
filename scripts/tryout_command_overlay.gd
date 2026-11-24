extends Control

var game: Control
var actors: Array = []
var bubble := StyleBoxFlat.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 8
	bubble.bg_color = Color("14242bf2")
	bubble.set_corner_radius_all(6)
	actors = [game.coach] + game.rotation_drill.roster + game.rotation_drill.workers.map(func(w): return w.actor)
	for seat in game.seats_in_use: actors.append(seat.actor)

func _process(_dt: float) -> void:
	visible = CareerSession.show_commands and not game.settings.visible
	if visible: queue_redraw()

func command_for(actor: Node3D) -> String:
	var r = game.rotation_drill
	if not r.roster.has(actor) and actor != game.coach and not r.workers.any(func(w): return w.actor==actor):
		return "Watch from bench"
	if game.phase == "complete":
		if r.unloading.has(actor): return "Put ball in cart"
		if r.human_cargo.size() and actor==r.roster[0]: return "Return balls to cart"
		if r.settled_positions.has(actor): return "Address team" if actor==game.coach else "Stand in huddle"
		if actor.has_meta("huddle_joining"): return "Join huddle"
		for w in r.workers:
			if w.actor==actor: return w.get("command","Join huddle")
		return "Join huddle"
	if game.phase in ["intro","net_guide"]: return "Introduce drill" if actor==game.coach else "Listen"
	if actor == game.coach:
		if r.coach_pushing: return "Push ball cart"
		if r.round_index != r.station: return "Reach cart handle"
		if game.phase=="feed": return "Toss to "+game.setter.display_name
		if r.waiting_ball: return "Pick up ball" if r.fetch_time<0.74 else "Hold next ball"
		return "Move to cart" if game.phase=="cart" else "Watch set"
	if actor == game.setter:
		if r.tap_remaining>0: return "Tap loose ball away"
		if game.phase=="cart": return "Move to setting spot" if actor.position.distance_to(game.BASE)>.12 else "Wait for toss"
		if game.phase in ["feed","pass"]: return "Set "+game.TARGETS[game.called()]
		return "Watch set"
	if r.roster.has(actor):
		if r.unloading.has(actor): return "Put ball in cart"
		if actor==r.roster[0] and not r.human_cargo.is_empty(): return "Carry loose ball"
		return "Player control" if actor==r.roster[0] and r.manual_wait else "Wait for turn"
	return "Watch the setter"

func _draw() -> void:
	var placed: Array[Rect2] = []
	var font := ThemeDB.fallback_font
	for actor: Node3D in actors:
		var head: Vector3 = game.head_position(actor)+Vector3.UP*.22
		if game.camera.is_position_behind(head): continue
		var tip: Vector2 = game.camera.unproject_position(head)
		if not Rect2(Vector2.ZERO,size).has_point(tip): continue
		var caption := command_for(actor)
		if actor.has_meta("school_jersey_number"): caption = "#%d  %s" % [actor.get_meta("school_jersey_number"),caption]
		var extent := Vector2(font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x+14,24)
		var rect := Rect2(Vector2(clampf(tip.x-extent.x/2,0,maxf(0,size.x-extent.x)),tip.y-extent.y-5),extent)
		for i in placed.size():
			if not placed.any(func(other): return rect.intersects(other)): break
			rect.position.y-=25
		if rect.position.y<0: rect.position.y=0
		placed.append(rect)
		draw_line(tip,Vector2(rect.get_center().x,rect.end.y),Color("b2d9ce"),1.5,true)
		draw_style_box(bubble,rect)
		draw_string(font,rect.position+Vector2(7,17),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14)
