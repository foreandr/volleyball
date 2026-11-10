extends RefCounted

const DIRECTORY := "user://debug/setting"
const SAMPLE_INTERVAL := 0.05
var file: FileAccess
var path := ""
var feed := 0
var started_ms := 0
var next_sample := 0.0
var closest_check := {}
var closest_margin := INF

func open(build: String) -> void:
	started_ms = Time.get_ticks_msec()
	if DirAccess.make_dir_recursive_absolute(DIRECTORY) != OK: return
	var timestamp := Time.get_datetime_string_from_system(true).replace(":","-")
	path = DIRECTORY.path_join("%s-%d.jsonl" % [timestamp,Time.get_ticks_usec()])
	file = FileAccess.open(path,FileAccess.WRITE)
	write("session",0.0,{"schema":1,"build":build,"utc":Time.get_datetime_string_from_system(true),"units":"metres, seconds, radians"},true)

func begin_feed(data: Dictionary) -> void:
	feed += 1
	next_sample = 0.0
	closest_check.clear()
	closest_margin = INF
	write("feed_start",0.0,data,true)

func check_contact(data: Dictionary) -> void:
	if data.is_empty() or data.margin >= closest_margin: return
	closest_margin = data.margin
	closest_check = data.duplicate()

func sample(time: float, data: Dictionary) -> void:
	if time < next_sample: return
	next_sample = time+SAMPLE_INTERVAL
	write("sample",time,data)

func write(kind: String, time: float, data: Dictionary, flush := false) -> void:
	if file == null: return
	file.store_line(JSON.stringify({"event":kind,"feed":feed,"time":time,"session_ms":Time.get_ticks_msec()-started_ms,"data":json_value(data)}))
	if flush: file.flush()

func close(time: float) -> void:
	write("session_end",time,{"closest_check":closest_check},true)
	file = null

static func json_value(value: Variant) -> Variant:
	if value is Vector3:
		return [value.x,value.y,value.z] if value.is_finite() else null
	if value is Vector2:
		return [value.x,value.y] if value.is_finite() else null
	if value is float and not is_finite(value): return null
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = json_value(value[key])
		return result
	return value
