extends RefCounted

var remaining:=0
var miss_slot:=0
var last_failed:=false

func next_misses() -> bool:
	if remaining==0:
		remaining=5
		# Slot five is next. Exclude it after a miss at the group boundary.
		miss_slot=randi_range(1,4 if last_failed else 5)
	last_failed=remaining==miss_slot
	remaining-=1
	return last_failed
