extends VBoxContainer
signal angle_requested(value: float)
const PLACEMENT_FIELDS := ["feed_spot","pass_destination","pass_start"]
const PLACEMENT_HISTORY_LIMIT := 50
var placement_start := {}
var placement_history: Array[Dictionary] = []
var field: SpinBox
var slider: HSlider
var actual_label: Label
var pending := false
var requested := 45.0
var distance_field: SpinBox
var incoming_speed_field: SpinBox
var incoming_angle_field: SpinBox
var spin_picker: OptionButton
var spin_rate_field: SpinBox
var float_field: SpinBox
var reach_picker: OptionButton
var reach_distance: SpinBox
var source_pad: Control
var height_field: SpinBox
var back_field: SpinBox
const RECEIVE_DIRECTIONS := ["Centered","Forward","Forward right","Right","Back right","Back","Back left","Left","Forward left"]
const SPINS := ["No spin","Topspin","Backspin","Sidespin left","Sidespin right","Dead float"]

var tabs: TabContainer
var source_panel: VBoxContainer
var destination_panel: VBoxContainer
var build_host: VBoxContainer
var destination_pad: Control
var apex_field: SpinBox
var expected_distance := 6.0

func _ready() -> void:
	add_theme_constant_override("separation",6)
	tabs = TabContainer.new()
	tabs.name = "BallTabs"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	source_panel = VBoxContainer.new()
	source_panel.name = "Source"
	source_panel.add_theme_constant_override("separation",8)
	tabs.add_child(source_panel)
	destination_panel = VBoxContainer.new()
	destination_panel.name = "Destination"
	destination_panel.add_theme_constant_override("separation",8)
	tabs.add_child(destination_panel)
	tabs.current_tab = StorySession.ball_tab
	tabs.tab_changed.connect(func(index): StorySession.ball_tab = index)
	build_host = source_panel
	source_pad = preload("res://scripts/ball_source_pad.gd").new()
	source_pad.set_positions(StorySession.feed_spot,StorySession.pass_start)
	source_pad.source_moved.connect(func(position): place_point(position,"ball"))
	source_pad.placement_started.connect(begin_placement)
	source_pad.placement_finished.connect(finish_placement)
	build_host.add_child(source_pad)
	height_field = parameter("Source height",0.2,12.0,StorySession.source_height)
	back_field = parameter("Back from net",-12.0,40.0,StorySession.feed_spot.y-4.0)
	back_field.value_changed.connect(func(value): StorySession.feed_spot.y = 4.0+value)
	back_field.get_meta("slider").value_changed.connect(func(value): StorySession.feed_spot.y = 4.0+value)
	incoming_speed_field = parameter("Speed",1.0,120.0,StorySession.incoming_speed,"m/s")
	incoming_speed_field.value_changed.connect(func(_value): StorySession.feed_fit = "angle")
	incoming_speed_field.get_meta("slider").value_changed.connect(func(_value): StorySession.feed_fit = "angle")
	incoming_angle_field = parameter("Angle",1.0,85.0,StorySession.incoming_angle,"°")
	incoming_angle_field.value_changed.connect(func(_value): StorySession.feed_fit = "speed")
	incoming_angle_field.get_meta("slider").value_changed.connect(func(_value): StorySession.feed_fit = "speed")
	spin_picker = OptionButton.new()
	for type in SPINS: spin_picker.add_item(type)
	spin_picker.select(maxi(0,SPINS.find(StorySession.incoming_spin)))
	build_host.add_child(spin_picker)
	spin_rate_field = parameter("Spin rate",0,10,StorySession.spin_rate,"rps")
	float_field = parameter("Float strength",0,1,StorySession.float_strength,"")
	spin_picker.item_selected.connect(func(_index): update_spin_controls(); pending = true)
	update_spin_controls()
	var reach_row := HBoxContainer.new()
	build_host.add_child(reach_row)
	var reach_label := Label.new()
	reach_label.text = "Receive aim"
	reach_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reach_row.add_child(reach_label)
	reach_picker = OptionButton.new()
	for direction in RECEIVE_DIRECTIONS: reach_picker.add_item(direction)
	reach_picker.select(clampi(StorySession.receive_direction,0,RECEIVE_DIRECTIONS.size()-1))
	reach_row.add_child(reach_picker)
	reach_distance = SpinBox.new()
	reach_distance.min_value = 0.05
	reach_distance.max_value = 0.40
	reach_distance.step = 0.05
	reach_distance.suffix = "m"
	reach_distance.value = StorySession.receive_distance
	reach_distance.tooltip_text = "Distance from the centered forearm platform"
	reach_distance.editable = reach_picker.selected != 0
	reach_row.add_child(reach_distance)
	reach_picker.item_selected.connect(func(index):
		reach_distance.editable = index != 0
		pending = true)
	reach_distance.value_changed.connect(func(_value): pending = true)
	build_host = destination_panel
	destination_pad = preload("res://scripts/ball_source_pad.gd").new()
	destination_pad.mode = "destination"
	destination_pad.source_moved.connect(func(position): place_point(position,"destination"))
	destination_pad.placement_started.connect(begin_placement)
	destination_pad.placement_finished.connect(finish_placement)
	build_host.add_child(destination_pad)
	apex_field = parameter("Pass height",0.5,20.0,StorySession.pass_apex)
	apex_field.allow_greater = true
	apex_field.value_changed.connect(func(_v): StorySession.destination_fit = "height")
	apex_field.get_meta("slider").value_changed.connect(func(_v): StorySession.destination_fit = "height")
	field = parameter("Output angle",10,85,45.0,"°")
	field.allow_greater = true
	field.value_changed.connect(request)
	slider = field.get_meta("slider")
	slider.value_changed.connect(request)
	distance_field = parameter("Distance",0.2,40.0,StorySession.pass_distance)
	distance_field.allow_greater = true
	distance_field.value_changed.connect(move_distance)
	distance_field.get_meta("slider").value_changed.connect(move_distance)
	actual_label = Label.new()
	actual_label.hide()
	build_host.add_child(actual_label)

func begin_placement() -> void:
	for field_name in PLACEMENT_FIELDS:
		placement_start[field_name] = StorySession.get(field_name)

func finish_placement() -> void:
	var changed := {}
	for field_name in placement_start:
		if not placement_start[field_name].is_equal_approx(StorySession.get(field_name)):
			changed[field_name] = placement_start[field_name]
	placement_start.clear()
	if changed.is_empty(): return
	placement_history.append(changed)
	if placement_history.size() > PLACEMENT_HISTORY_LIMIT: placement_history.pop_front()

func undo_placement() -> bool:
	if not placement_start.is_empty() or placement_history.is_empty(): return false
	var previous: Dictionary = placement_history.pop_back()
	for field_name in previous:
		StorySession.set(field_name,previous[field_name])
	if StorySession.pass_destination.is_finite():
		var distance := StorySession.pass_start.distance_to(StorySession.pass_destination)
		distance_field.set_value_no_signal(distance)
		distance_field.get_meta("slider").set_value_no_signal(distance)
	pending = true
	return true

func place_point(position: Vector2, type: String) -> void:
	if type == "destination": StorySession.pass_destination = position
	else: StorySession.feed_spot = position
	pending = true

func move_distance(value: float) -> void:
	var direction := StorySession.pass_destination-StorySession.pass_start
	if not direction.is_finite() or direction.length()<0.01: direction = Vector2(0,1)
	StorySession.pass_destination = StorySession.pass_start+direction.normalized()*value
	pending = true

func update_spin_controls() -> void:
	var type: String = SPINS[spin_picker.selected]
	var rate_enabled := type != "No spin" and type != "Dead float"
	var rate_slider: HSlider = spin_rate_field.get_meta("slider")
	spin_rate_field.editable = rate_enabled
	rate_slider.editable = rate_enabled
	var tint := Color.WHITE if rate_enabled else Color(1,1,1,0.45)
	spin_rate_field.get_parent().modulate = tint
	rate_slider.modulate = tint
	var is_float := type == "Dead float"
	float_field.get_parent().visible = is_float
	float_field.get_meta("slider").visible = is_float


func parameter(title_: String, low: float, high: float, value: float, unit := "m") -> SpinBox:
	var row := HBoxContainer.new()
	build_host.add_child(row)
	var title := Label.new()
	title.text = title_
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var number := SpinBox.new()
	number.min_value = low
	number.max_value = high
	number.step = 0.1
	number.suffix = unit
	number.custom_minimum_size = Vector2(110,32)
	number.value = value
	row.add_child(number)
	var bar := HSlider.new()
	bar.min_value = low
	bar.max_value = high
	bar.step = 0.1
	bar.value = value
	build_host.add_child(bar)
	number.value_changed.connect(func(v): bar.set_value_no_signal(v); pending = true)
	bar.value_changed.connect(func(v): number.set_value_no_signal(v); pending = true)
	number.set_meta("slider",bar)
	return number

func apply_setup(player: Node3D) -> void:
	if not StorySession.pass_destination.is_finite():
		var direction := (StorySession.feed_spot-StorySession.pass_start).normalized()
		StorySession.pass_destination = StorySession.pass_start+direction*StorySession.pass_distance
	StorySession.pass_apex = apex_field.value
	StorySession.source_height = height_field.value
	StorySession.pass_distance = distance_field.value
	StorySession.incoming_speed = incoming_speed_field.value
	StorySession.incoming_angle = incoming_angle_field.value
	StorySession.incoming_spin = SPINS[spin_picker.selected]
	StorySession.spin_rate = spin_rate_field.value
	StorySession.float_strength = float_field.value
	player.position = Vector3(StorySession.pass_start.x,0.04,StorySession.pass_start.y)
	StorySession.receive_direction = reach_picker.selected
	StorySession.receive_distance = reach_distance.value
	var heading := (reach_picker.selected-1)*TAU/8.0
	var reach := Vector2(-sin(heading),cos(heading))*reach_distance.value if reach_picker.selected > 0 else Vector2.ZERO
	player.set_meta("receive_reach",reach)
	player.set_meta("feed_settings",{"speed":StorySession.incoming_speed,"angle":StorySession.incoming_angle,"source":StorySession.feed_spot,"source_height":StorySession.source_height,"fit":StorySession.feed_fit,"spin":SPINS[spin_picker.selected],"spin_rate":spin_rate_field.value,"float_strength":float_field.value})
	var facing := (StorySession.feed_spot-StorySession.pass_start).normalized()+(StorySession.pass_destination-StorySession.pass_start).normalized()
	if facing.length()<0.01: facing = (StorySession.feed_spot-StorySession.pass_start).normalized()
	player.rotation.y = atan2(facing.x,facing.y)
	player.set_meta("pass_target",{"position":StorySession.pass_destination,"height":StorySession.pass_apex,"fit":StorySession.destination_fit})


func _process(_delta: float) -> void:
	source_pad.set_positions(StorySession.feed_spot,StorySession.pass_start,StorySession.pass_destination)
	destination_pad.set_positions(StorySession.feed_spot,StorySession.pass_start,StorySession.pass_destination)
	back_field.set_value_no_signal(StorySession.feed_spot.y-4.0)
	back_field.get_meta("slider").set_value_no_signal(back_field.value)
	if pending:
		var page := get_tree().current_scene
		if page.get("player_controls")!=null and page.player_controls.active: return
		pending = false
		angle_requested.emit(requested)

func sync_feed(feed: Dictionary) -> void:
	var velocity: Vector3 = feed.incoming
	var speed := velocity.length()
	var angle := rad_to_deg(atan2(-velocity.y,Vector2(velocity.x,velocity.z).length()))
	incoming_speed_field.set_value_no_signal(speed)
	incoming_speed_field.get_meta("slider").set_value_no_signal(speed)
	incoming_angle_field.set_value_no_signal(angle)
	incoming_angle_field.get_meta("slider").set_value_no_signal(angle)
	StorySession.incoming_speed = speed
	StorySession.incoming_angle = angle
	back_field.set_value_no_signal(StorySession.feed_spot.y-4.0)
	back_field.get_meta("slider").set_value_no_signal(back_field.value)

func sync_output(ball: Node3D) -> void:
	expected_distance = Vector2(ball.impact_point.x,ball.impact_point.z).distance_to(StorySession.pass_destination)
	var range_ := StorySession.pass_start.distance_to(StorySession.pass_destination)
	StorySession.pass_distance = range_
	distance_field.set_value_no_signal(range_)
	distance_field.get_meta("slider").set_value_no_signal(range_)
	if StorySession.destination_fit == "height" and apex_field.value < ball.impact_point.y+0.05:
		StorySession.pass_apex = ball.impact_point.y+0.05
		apex_field.set_value_no_signal(StorySession.pass_apex)
		apex_field.get_meta("slider").set_value_no_signal(StorySession.pass_apex)
	if StorySession.destination_fit == "angle":
		var apex: float = ball.impact_point.y+pow(maxf(0,ball.outgoing.y),2)/(2*9.81)
		StorySession.pass_apex = apex
		apex_field.set_value_no_signal(apex)
		apex_field.get_meta("slider").set_value_no_signal(apex)

func request(value: float) -> void:
	StorySession.destination_fit = "angle"
	requested = value
	field.set_value_no_signal(value)
	slider.set_value_no_signal(value)
	pending = true

func display_result(value: float, actual: float, distance_ := -1.0) -> void:
	if StorySession.destination_fit == "height": value = actual
	pending = false
	requested = value
	field.set_value_no_signal(value)
	slider.set_value_no_signal(value)
	set_actual(actual,distance_)

func set_actual(value: float, distance_ := -1.0) -> void:
	actual_label.visible = absf(value-requested) > 1.0 or (distance_ >= 0 and absf(distance_-expected_distance)>0.15)
	actual_label.text = "Actual %.1f°" % value
	if distance_ >= 0: actual_label.text += " · %.1f m" % distance_
