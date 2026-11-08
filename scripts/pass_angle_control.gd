extends VBoxContainer
signal angle_requested(value: float)
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
var source_pad: Control
var height_field: SpinBox
var back_field: SpinBox
const SPINS := ["No spin","Topspin","Backspin","Sidespin left","Sidespin right","Dead float"]

func _ready() -> void:
	add_theme_constant_override("separation",6)
	var source_label := Label.new()
	source_label.text = "Source"
	add_child(source_label)
	source_pad = preload("res://scripts/ball_source_pad.gd").new()
	source_pad.set_positions(StorySession.feed_spot,StorySession.pass_start)
	source_pad.source_moved.connect(func(position): StorySession.feed_spot = position; pending = true)
	add_child(source_pad)
	height_field = parameter("Source height",0.2,12.0,StorySession.source_height)
	back_field = parameter("Back from net",-12.0,40.0,StorySession.feed_spot.y-4.0)
	back_field.value_changed.connect(func(value): StorySession.feed_spot.y = 4.0+value)
	back_field.get_meta("slider").value_changed.connect(func(value): StorySession.feed_spot.y = 4.0+value)
	var row := HBoxContainer.new()
	add_child(row)
	var title := Label.new()
	title.text = "Output angle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	field = SpinBox.new()
	field.name = "OutputAngle"
	field.min_value = 10
	field.max_value = 80
	field.step = 0.1
	field.suffix = "°"
	field.custom_minimum_size = Vector2(110,36)
	field.value_changed.connect(request)
	row.add_child(field)
	slider = HSlider.new()
	slider.min_value = 10
	slider.max_value = 80
	slider.step = 0.1
	slider.value_changed.connect(request)
	add_child(slider)
	actual_label = Label.new()
	actual_label.hide()
	add_child(actual_label)
	distance_field = parameter("Distance",0.5,18.0,StorySession.pass_distance)
	incoming_speed_field = parameter("Incoming speed",1.0,120.0,StorySession.incoming_speed,"m/s")
	incoming_speed_field.value_changed.connect(func(_value): StorySession.feed_fit = "angle")
	incoming_speed_field.get_meta("slider").value_changed.connect(func(_value): StorySession.feed_fit = "angle")
	incoming_angle_field = parameter("Incoming angle",1.0,85.0,StorySession.incoming_angle,"°")
	incoming_angle_field.value_changed.connect(func(_value): StorySession.feed_fit = "speed")
	incoming_angle_field.get_meta("slider").value_changed.connect(func(_value): StorySession.feed_fit = "speed")
	spin_picker = OptionButton.new()
	for type in SPINS: spin_picker.add_item(type)
	spin_picker.select(maxi(0,SPINS.find(StorySession.incoming_spin)))
	add_child(spin_picker)
	spin_rate_field = parameter("Spin rate",0,10,StorySession.spin_rate,"rps")
	float_field = parameter("Float strength",0,1,StorySession.float_strength,"")
	spin_picker.item_selected.connect(func(_index): update_spin_controls(); pending = true)
	update_spin_controls()

func update_spin_controls() -> void:
	var type: String = SPINS[spin_picker.selected]
	for control in [spin_rate_field,float_field]:
		var show_: bool = type == "Dead float" if control == float_field else not type in ["Dead float","No spin"]
		control.get_parent().visible = show_
		control.get_meta("slider").visible = show_


func parameter(title_: String, low: float, high: float, value: float, unit := "m") -> SpinBox:
	var row := HBoxContainer.new()
	add_child(row)
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
	add_child(bar)
	number.value_changed.connect(func(v): bar.set_value_no_signal(v); pending = true)
	bar.value_changed.connect(func(v): number.set_value_no_signal(v); pending = true)
	number.set_meta("slider",bar)
	return number

func apply_setup(player: Node3D) -> void:
	StorySession.source_height = height_field.value
	StorySession.pass_distance = distance_field.value
	StorySession.incoming_speed = incoming_speed_field.value
	StorySession.incoming_angle = incoming_angle_field.value
	StorySession.incoming_spin = SPINS[spin_picker.selected]
	StorySession.spin_rate = spin_rate_field.value
	StorySession.float_strength = float_field.value
	player.position = Vector3(StorySession.pass_start.x,0.04,StorySession.pass_start.y)
	player.set_meta("feed_settings",{"speed":StorySession.incoming_speed,"angle":StorySession.incoming_angle,"source":StorySession.feed_spot,"source_height":StorySession.source_height,"fit":StorySession.feed_fit,"spin":SPINS[spin_picker.selected],"spin_rate":spin_rate_field.value,"float_strength":float_field.value})
	player.rotation.y = atan2(StorySession.feed_spot.x-StorySession.pass_start.x,StorySession.feed_spot.y-StorySession.pass_start.y)


func _process(_delta: float) -> void:
	source_pad.set_positions(StorySession.feed_spot,StorySession.pass_start)
	back_field.set_value_no_signal(StorySession.feed_spot.y-4.0)
	back_field.get_meta("slider").set_value_no_signal(back_field.value)
	if pending:
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

func request(value: float) -> void:
	requested = value
	field.set_value_no_signal(value)
	slider.set_value_no_signal(value)
	pending = true

func display_result(value: float, actual: float, distance_ := -1.0) -> void:
	pending = false
	requested = value
	field.set_value_no_signal(value)
	slider.set_value_no_signal(value)
	set_actual(actual,distance_)

func set_actual(value: float, distance_ := -1.0) -> void:
	actual_label.visible = absf(value-requested) > 1.0 or (distance_ >= 0 and absf(distance_-distance_field.value)>0.15)
	actual_label.text = "Actual %.1f°" % value
	if distance_ >= 0: actual_label.text += " · %.1f m" % distance_
