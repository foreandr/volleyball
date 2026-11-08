extends VBoxContainer
signal changed(part: String)
const BODIES := ["Auto","From clip","Balanced","Low base","Split stance","Knee drop","Hip drop"]
const HANDS := ["From platform","Firm clasp","Loose clasp"]
var body_picker: OptionButton
var hand_picker: OptionButton

func _ready() -> void:
	body_picker = picker("Body / legs",BODIES,StorySession.reception_body)
	body_picker.item_selected.connect(func(index): StorySession.reception_body = BODIES[index]; changed.emit("body"))
	hand_picker = picker("Hands",HANDS,StorySession.reception_hands)
	hand_picker.item_selected.connect(func(index): StorySession.reception_hands = HANDS[index]; changed.emit("hands"))

func picker(title_: String, entries: Array, selected: String) -> OptionButton:
	var title := Label.new()
	title.text = title_
	add_child(title)
	var option := OptionButton.new()
	option.custom_minimum_size.y = 36
	for entry in entries: option.add_item(entry)
	option.select(maxi(0,entries.find(selected)))
	add_child(option)
	return option

func apply(player: Node3D, replace_body := false) -> void:
	player.set_meta("reception_options",{"body":StorySession.reception_body,"hands":StorySession.reception_hands,"replace_body":replace_body})

func show_result(clip: Animation) -> void:
	var text := "Auto"
	if clip.has_meta("reception_body"): text += ": "+str(clip.get_meta("reception_body"))
	body_picker.set_item_text(0,text)
