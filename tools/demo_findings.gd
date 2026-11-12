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
	quit(0 if Policy.write_json(args[0],{"findings":findings.values()}) == OK else 1)
