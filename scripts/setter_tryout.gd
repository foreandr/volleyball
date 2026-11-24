extends "res://scripts/indoor_practice.gd"

func start_drill() -> void:
	scorecard=CareerSession.data.get_value(CareerSession.key(),"tryout_scorecard",[]).duplicate(true)
	var count := scorecard.size()
	rotation_drill.round_index=mini(count/9,2)
	rotation_drill.turn=(count/3)%3
	rotation_drill.attempts=count%3
	setter=rotation_drill.roster[rotation_drill.turn]
	rep=CareerSession.progress()
	gym.update_board(rep)
	if CareerSession.stage() not in ["complete","after_tryout"] and not StorySession.game_options.get_value("tutorial","seen_net_guide",false):
		phase="net_guide"
		panel.hide()
		var guide := preload("res://scripts/setter_net_guide.gd").new()
		add_child(guide)
		guide.dismissed.connect(func(skip_rest: bool):
			StorySession.game_options.set_value("tutorial","seen_net_guide",true)
			StorySession.game_options.set_value("tutorial","skip_setter_intro",skip_rest)
			StorySession.save_options()
			guide.queue_free()
			panel.show()
			enter_chapter())
	else: enter_chapter()

func enter_chapter() -> void:
	match CareerSession.stage():
		"intro":
			if StorySession.game_options.get_value("tutorial","skip_setter_intro",false):
				if finish_intro(): start_practice()
			else: begin("intro")
		"complete","after_tryout": complete()
		_: start_practice()

func finish_intro() -> bool:
	return CareerSession.checkpoint("tutorial",0)

func complete() -> void:
	super.complete()
	title.text = "MY CAREER   /   INDOOR SETTER"
	if scorecard.size()!=27:
		message.text="Setter tryout complete"
		return
	var lines := PackedStringArray()
	for row in rankings():
		var place := lines.size()
		lines.append("%s   %s   %d/9" % [["Starting setter","Backup setter","Cut"][place],rotation_drill.roster[row.id].display_name,row.made])
	message.text="Final standings"
	hint.text="\n".join(lines)
	hint.show()

func save_scorecard() -> bool:
	CareerSession.data.set_value(CareerSession.key(),"tryout_scorecard",scorecard.duplicate(true))
	if rotation_drill.turn==0 and success:
		if not CareerSession.credit(rep): return false
		rep+=1
		return true
	if scorecard.size()==27:
		var order := rankings()
		for i in order.size():
			if order[i].id==0: CareerSession.data.set_value(CareerSession.key(),"tryout_place",i)
	return CareerSession.checkpoint("complete" if scorecard.size()==27 else "tutorial",rep)

func reset_drill() -> void:
	CareerSession.data.set_value(CareerSession.key(),"tryout_scorecard",[])
	if CareerSession.checkpoint("tutorial",0): super.reset_drill()

func leave() -> void:
	if phase=="complete" and scorecard.size()==27:
		if not CareerSession.checkpoint("after_tryout",rep): return
	super.leave()
