extends SceneTree

func _initialize(): run.call_deferred()
func run():
	seed(2400)
	var Camp=load("res://scripts/serving_camp.gd")
	for mode in [0,3]:
		var shot=Camp.TECHNIQUES[1 if mode==3 else 0].new()
		var origin:=Vector3(-1.56,3.82,-7.89)
		for speed in [45.,50.,60.,105.]:
			for depth in [4.21,11.5]:
				var previous:float=0.
				for clearance in [.03,.20,1.5]:
					Camp.configure_serve_curve(shot,origin,speed,0,mode,clearance,0.)
					Camp.strike_serve(shot,origin,Vector3(2.5,.145,depth),0.,false,true)
					var peak:float=0.
					for i in 180: peak=maxf(peak,shot.flight_point(shot.planned_duration*i/179.).y)
					assert(peak<7. and shot.velocity.length()<=speed/3.6+.001)
					if depth>10. and speed>=50. and clearance>=.20:
						assert(shot.net_hit.is_empty())
						assert(shot.flight_point(shot.planned_duration).distance_to(Vector3(2.5,.145,depth))<.38)
					assert(peak>=previous-(.22 if mode==3 else .01))
					previous=peak
					if speed==50. and depth>10.: print("50 km/h mode ",mode," clearance ",clearance," peak ",peak," landing ",shot.flight_point(shot.planned_duration))
		shot.free()
	print("PASS low-pace serve trajectories")
	quit()
