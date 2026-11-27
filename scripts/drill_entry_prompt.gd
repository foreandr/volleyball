extends HBoxContainer

const Xbox=preload("res://scripts/xbox_controls.gd")
var fill:=0.
var badge:=Control.new()
var caption:=Label.new()
var key_name:="Enter"

func _ready() -> void:
	badge.custom_minimum_size=Vector2(40,40)
	badge.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(badge)
	add_child(caption)
	caption.text="Hold to enter the drill"
	badge.draw.connect(paint)

func set_fraction(value:float) -> void:
	fill=clampf(value,0.,1.)
	badge.queue_redraw()

func paint() -> void:
	var c:=badge.size*.5
	badge.draw_arc(c,18.,0.,TAU,64,Color("52616d"),3.,true)
	if fill>0.: badge.draw_arc(c,18.,-PI/2.,-PI/2.+TAU*fill,64,Color("72efba"),3.,true)
	if Xbox.keyboard_prompts():
		badge.draw_string(ThemeDB.fallback_font,Vector2(0,c.y+4),key_name,HORIZONTAL_ALIGNMENT_CENTER,badge.size.x,11)
	else:
		badge.draw_texture_rect(Xbox.glyph(JOY_BUTTON_A),Rect2(c-Vector2(14,14),Vector2(28,28)),false)

static func mount(row:Container,key:String) -> Control:
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	var widget:=new()
	widget.key_name=key
	row.add_child(widget)
	return widget
