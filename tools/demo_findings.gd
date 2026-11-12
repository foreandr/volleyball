extends SceneTree

const Review = preload("res://scripts/match_review.gd")
const Policy = preload("res://scripts/cpu_policy.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	var findings := {}
	Review.collect_findings(findings)
	Review.collect_player_markers(findings)
	quit(0 if Policy.write_json(args[0],{"review_focus":Review.REVIEW_FOCUS,"findings":Review.ordered_findings(findings)}) == OK else 1)
