extends "res://scripts/indoor_practice.gd"

func start_drill() -> void:
	scorecard=CareerSession.data.get_value(CareerSession.key(),"tryout_scorecard",[]).duplicate(true)
	rotation_drill.advance_turn()
	rep=CareerSession.progress()
	gym.update_board(rep)
	if CareerSession.stage() not in ["complete","after_tryout"] and not StorySession.game_options.get_value("tutorial","seen_net_guide",false):
		phase="net_guide"
		panel.hide()
		var guide := preload("res://scripts/setter_net_guide.gd").new()
		add_child(guide)
		guide.dismissed.connect(func():
			StorySession.game_options.set_value("tutorial","seen_net_guide",true)
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
	var order := rankings()
	for place in order.size():
		var row: Dictionary = order[place]
		score_labels[row.id].text = "%s\n%d/9 made" % [["Starting setter","Backup setter","Cut"][place],row.made]
		var tint: Color = [Color("76e59b"),Color("ffda71"),Color("ff8989")][place]
		score_labels[row.id].add_theme_color_override("font_color",tint)
		var card: PanelContainer = score_labels[row.id].get_parent().get_parent()
		card.add_theme_stylebox_override("panel",MenuPresentation.box(tint.darkened(0.83),tint,2))
		score_strip.move_child(score_labels[row.id].get_parent().get_parent(),place)
	message.text="Final standings"

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
