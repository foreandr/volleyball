extends HSlider
func _draw() -> void:
	var frames: Array = get_meta("keyframes",[])
	if max_value <= 0: return
	for frame in frames:
		var x := 8.0+(size.x-16.0)*float(frame)/max_value
		draw_line(Vector2(x,size.y-5),Vector2(x,size.y),Color("ffce70"),2)
