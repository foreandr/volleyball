extends VBoxContainer
signal angle_requested(value: float)
var field: SpinBox
var slider: HSlider
var actual_label: Label
var pending := false
var requested := 45.0

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

func _process(_delta: float) -> void:
	if pending:
		pending = false
		angle_requested.emit(requested)

func request(value: float) -> void:
	requested = value
	field.set_value_no_signal(value)
	slider.set_value_no_signal(value)
	pending = true

func display_result(value: float, actual: float) -> void:
	pending = false
	requested = value
	field.set_value_no_signal(value)
	slider.set_value_no_signal(value)
	set_actual(actual)

func set_actual(value: float) -> void:
	actual_label.visible = absf(value-requested) > 1.0
	actual_label.text = "Actual %.1f°" % value
