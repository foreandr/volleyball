extends "res://scripts/indoor_practice.gd"

func start_drill() -> void:
	rep = CareerSession.progress()
	gym.update_board(rep)
	match CareerSession.stage():
		"intro": begin("intro")
		"complete": complete()
		_: start_practice()

func credit_rep() -> bool:
	return CareerSession.credit(rep)

func finish_intro() -> bool:
	return CareerSession.checkpoint("tutorial",0)

func complete() -> void:
	super.complete()
	title.text = "MY CAREER   /   INDOOR SETTER"
	message.text = "Setter tryout complete"
	var badges: Array = CareerSession.data.get_value("badges",CareerSession.athlete_id,[])
	hint.show()
	hint.text = "Badges   •   "+"   /   ".join(badges) if not badges.is_empty() else ""
