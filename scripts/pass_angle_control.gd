extends VBoxContainer
signal angle_requested(value: float)
var field: SpinBox
var slider: HSlider
var actual_label: Label
var pending := false
var requested := 45.0
var distance_field: SpinBox
var x_field: SpinBox
var depth_field: SpinBox

func _ready() -> void:
	add_theme_constant_override("separation",6)
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
	x_field = parameter("Left / right",-4.0,4.0,StorySession.pass_start.x)
	depth_field = parameter("From net",1.5,8.5,4.0-StorySession.pass_start.y)

func parameter(title_: String, low: float, high: float, value: float) -> SpinBox:
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
	number.suffix = "m"
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
	return number

func apply_setup(player: Node3D) -> void:
	StorySession.pass_distance = distance_field.value
	StorySession.pass_start = Vector2(x_field.value,4.0-depth_field.value)
	player.position = Vector3(StorySession.pass_start.x,0.04,StorySession.pass_start.y)


func _process(_delta: float) -> void:
	if pending:
		pending = false
		angle_requested.emit(requested)

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
