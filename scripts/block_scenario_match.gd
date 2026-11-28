extends "res://scripts/volleyball_match.gd"

var feed_number := -1
var feed_hitter := -1
var instructions := ConfigFile.new()
var rules_path := "user://block_defense_ai.cfg"
var situation := ""
var teaching_moves := {}
var applying_instructions := false

func phase_key() -> String:
	if situation.is_empty(): return ""
	var offset:=flight_number-feed_number
	if offset<0 or offset>2 or flight_kind!=["pass","set","spike"][offset]: return ""
	var third:=clampi(floori(3.*elapsed/maxf(.001,flight_end())),0,2)
	return "%s/%s/%d"%[situation,flight_kind,third]

func trace_snapshot() -> Dictionary:
	var snapshot:=super.trace_snapshot()
	snapshot["scenario_phase"]=phase_key()
	return snapshot

func teach(section:String,index:int,point:Vector3) -> Error:
	if section.is_empty(): return ERR_INVALID_PARAMETER
	var slot:="%d/%d"%[team(index),lineup_role(index)]
	instructions.set_value(section,slot,Vector2(point.x,point.z))
	return instructions.save(rules_path)

func step_match(delta:float,controls:RefCounted) -> void:
	teaching_moves.clear()
	var section:=phase_key()
	if phase==Phase.LIVE and instructions.has_section(section):
		applying_instructions=true
		for slot in instructions.get_section_keys(section):
			var parts:=slot.split("/")
			if parts.size()!=2: continue
			var side:=parts[0].to_int()
			if side not in [0,1]: continue
			var local:=lineup_roles[side].find(parts[1].to_int())
			if local<0: continue
			var i:=first_on(side)+local
			if is_human(i) or owns_action(i) or recoveries.has(i) or blocks.has(i): continue
			if i==cpu_choice or i==expected_hitter or (flight_kind=="pass" and i in [rally_setter,rally_hitter]): continue
			var mark:Vector2=instructions.get_value(section,slot)
			var target:=frames[side].to_global(Vector3(mark.x,PLAYER_GROUND_Y,mark.y))
			move_cpu(i,target,delta,5.,toward_incoming(i,target),true,true)
			teaching_moves[i]=true
		applying_instructions=false
	super.step_match(delta,controls)

func move_cpu(index:int,target:Vector3,delta:float,speed:=5.3,receive_facing:=Vector3.INF,chase:=false,turn_to_travel:=false,turn_rate:=12.5,paced_run:=false,run_cadence:=0.,shuffle_pace:=0.,outside_direction:=0.,shoulder_x:=0.) -> void:
	if not applying_instructions and teaching_moves.has(index): return
	super.move_cpu(index,target,delta,speed,receive_facing,chase,turn_to_travel,turn_rate,paced_run,run_cadence,shuffle_pace,outside_direction,shoulder_x)

func scripted_pass() -> bool:
	return flight_number==feed_number and flight_kind=="pass"

func hitter_for_set(setter:int,allow_quick:bool=true) -> int:
	if scripted_pass() and team(setter)==1: return feed_hitter
	return super.hitter_for_set(setter,allow_quick)

func choose_at_set_contact(setter:int,point:Vector3) -> void:
	if scripted_pass():
		rally_hitter=feed_hitter
		return
	super.choose_at_set_contact(setter,point)

func select_receiver() -> void:
	super.select_receiver()
	if scripted_pass():
		cpu_dump=false
		cpu_fake_dump=false

func start_second_ball_spike(index:int,require_open_lane:=false) -> bool:
	if scripted_pass(): return false
	return super.start_second_ball_spike(index,require_open_lane)

func attack_lane_for(index:int) -> Vector3:
	var lane:=super.attack_lane_for(index)
	if index==feed_hitter and not lane.is_finite() and lineup_role(index)==3:
		return Vector3(-3.65,.065,.82)
	return lane

func start_feed(defense:int,offense:int,role:int,in_system:bool) -> void:
	situation="%d/%d/%d/%d"%[defense,offense,role,int(in_system)]
	feed_number=-1
	reset_match()
	service_team=0
	setter_zones.assign([defense,offense])
	begin_point()
	var setter:int=first_on(1)+lineup_roles[1].find(0)
	feed_hitter=first_on(1)+lineup_roles[1].find(role)
	var passer:=first_on(1)
	for i in slots_for(1):
		if active_identities.get(i,-1)==6: passer=i
	for i in slots_for(0): players[i].position=formation_home(i,true)
	var destination:=SETTER_BASE if in_system else Vector3(-.8,PLAYER_GROUND_Y,.25)
	players[setter].position=destination-Vector3.BACK*.35
	var lane:=attack_lane_for(feed_hitter)
	players[feed_hitter].position=GroundMovement.attack_staging(lane)
	var start:Vector3=players[passer].position+Vector3.UP*1.05
	var finish:=destination+Vector3.UP*1.9
	var duration:=1.4
	var motion:=(finish-start)/duration+Vector3.UP*(.5*Flight.GRAVITY*duration)
	phase=Phase.LIVE
	serve.ball.hide()
	possession_team=1
	touches=1
	feed_number=flight_number+1
	launch(frames[1].to_global(start),frames[1].global_basis*motion,"pass",passer)
