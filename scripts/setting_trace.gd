extends RefCounted

const DIRECTORY := "user://debug/setting"
const MARKER_DIRECTORY := "user://iteration_lab/player-markers"
const MARKER_REPLAYS := "user://iteration_lab/player-marker-replays"
const SAMPLE_INTERVAL := 0.05
const MARKER_CONTEXT_EVENTS := 20
var file: FileAccess
var path := ""
var feed := 0
var started_ms := 0
var next_sample := 0.0
var closest_check := {}
var closest_margin := INF
var recent_events: Array[Dictionary] = []

func open(build: String) -> void:
	started_ms = Time.get_ticks_msec()
	recent_events.clear()
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
	var entry := {"event":kind,"feed":feed,"time":time,"session_ms":Time.get_ticks_msec()-started_ms,"data":json_value(data)}
	file.store_line(JSON.stringify(entry))
	if flush: file.flush()
	if kind == "player_marker": archive_marker(entry)
	recent_events.append(entry)
	if recent_events.size() > MARKER_CONTEXT_EVENTS: recent_events.pop_front()

func archive_marker(entry: Dictionary) -> void:
	if DirAccess.make_dir_recursive_absolute(MARKER_DIRECTORY) != OK: return
	var name_ := "%s-%d-%d.json" % [path.get_file().get_basename(),entry.session_ms,entry.feed]
	var archive := MARKER_DIRECTORY.path_join(name_)
	var marker_file := FileAccess.open(archive+".tmp",FileAccess.WRITE)
	if marker_file == null: return
	marker_file.store_string(JSON.stringify({"trace":ProjectSettings.globalize_path(path),"marker":entry,"context":recent_events}))
	marker_file.close()
	DirAccess.rename_absolute(archive+".tmp",archive)

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
