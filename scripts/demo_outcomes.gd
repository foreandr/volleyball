extends RefCounted

var remaining:=0
var miss_slot:=0
var last_failed:=false

var group_size:int

func _init(attempts_per_miss:=5) -> void:
	group_size=maxi(2,attempts_per_miss)

func next_misses() -> bool:
	if remaining==0:
		remaining=group_size
		# The highest slot is next. Exclude it after a miss at the group boundary.
		miss_slot=randi_range(1,group_size-1 if last_failed else group_size)
	last_failed=remaining==miss_slot
	remaining-=1
	return last_failed
