extends Control

const WIDTH := 132.0
const HEIGHT := 34.0
var jump_height := 0.0
var fraction := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(WIDTH,HEIGHT)
	hide()

func show_height(projected_feet: Vector2, viewport_size: Vector2, value: float, maximum: float) -> void:
	jump_height = value
	fraction = clampf(value/maximum,0.0,1.0)
	position = (projected_feet+Vector2(-WIDTH*0.5,10.0)).clamp(Vector2(4,4),(viewport_size-size-Vector2(4,4)).max(Vector2(4,4)))
	show()
	queue_redraw()

func _draw() -> void:
	var badge := StyleBoxFlat.new()
	badge.bg_color = Color("152331")
	badge.set_corner_radius_all(6)
	draw_style_box(badge,Rect2(Vector2.ZERO,size))
	var track := Rect2(8,22,WIDTH-16,6)
	draw_rect(track,Color("3a4a5b"))
	var color := Color("ffd16d") if fraction>=0.995 else Color("64dcec")
	draw_rect(Rect2(track.position,Vector2(track.size.x*fraction,track.size.y)),color)
	for part in [0.25,0.50,0.75]:
		var marker := track.position+Vector2(track.size.x*part,0)
		draw_line(marker,marker+Vector2(0,track.size.y),Color("152331"),1.0)
	var readout := "%d in" % roundi(jump_height/0.0254)
	draw_string(ThemeDB.fallback_font,Vector2(0,16),readout,HORIZONTAL_ALIGNMENT_CENTER,int(WIDTH),14,Color.WHITE)
