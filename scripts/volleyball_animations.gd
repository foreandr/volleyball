extends RefCounted
const ENTRIES := [{"id":"straight_pass_01","name":"Straight Pass 1","category":"Passing","type":"Straight","path":"res://assets/animations/straight_pass_01.tres"}]

static func entries(category: String, move_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in ENTRIES:
		if entry.category == category and entry.type == move_type: result.append(entry)
	return result
