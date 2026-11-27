extends "res://scripts/blocking_camp.gd"

func axis(which: JoyAxis) -> float:
	return 1. if which==JOY_AXIS_LEFT_X else 0.
