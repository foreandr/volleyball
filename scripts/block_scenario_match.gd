extends "res://scripts/volleyball_match.gd"

var feed_number := -1
var feed_hitter := -1
var feed_tempo := 2
const ROUTES := ["left","middle","pipe","right"]
var attack_options:Dictionary={}
var planned_flight:=-1
var released_route:=""
var released_tempo:=-1
var pass_target := Vector3.ZERO
var instructions := ConfigFile.new()
var rules_path := "user://block_defense_ai.cfg"
var situation := ""
var teaching_moves := {}
var applying_instructions := false

func apply_receive_substitutions() -> void:
	super.apply_receive_substitutions()
	# This lab compares blue M2 at maximum Blocking. His libero keeps his own profile.
	var middle:=first_on(0)+lineup_roles[0].find(5)
	if active_identities.get(middle,-1)==5:
		players[middle].attributes.Blocking=100

func phase_key() -> String:
	if phase!=Phase.LIVE or situation.is_empty(): return ""
	var offset:=flight_number-feed_number
	if offset < -1 or offset>2 or flight_kind!=["serve","pass","set","spike"][offset+1]: return ""
	var third:=clampi(floori(3.*elapsed/maxf(.001,flight_end())),0,2)
	var lesson:=situation
	if offset<=0 and attack_options.size()>1:
		lesson="%d/%d/mixed/%s"%[setter_zones[0],setter_zones[1],situation.get_slice("/",3)]
	return "%s/%s/%d"%[lesson,flight_kind,third]

func trace_snapshot() -> Dictionary:
	var snapshot:=super.trace_snapshot()
	snapshot["scenario_phase"]=phase_key()
	snapshot["lab_route"]=released_route
	snapshot["lab_tempo"]=released_tempo
	return snapshot

func teach(section:String,index:int,point:Vector3) -> Error:
	if section.is_empty(): return ERR_INVALID_PARAMETER
	var slot:="%d/%d"%[team(index),lineup_role(index)]
	instructions.set_value(section,slot,Vector2(point.x,point.z))
	return instructions.save(rules_path)

func step_match(delta:float,controls:RefCounted) -> void:
	teaching_moves.clear()
	if phase==Phase.LIVE and flight_kind=="serve" and flight_number+1==feed_number and cpu_choice>=0 and team(cpu_choice)==1:
		var setter:=choose_setter(1,cpu_choice)
		if setter!=cpu_choice:
			var destination:=frames[1].to_global(pass_target-Vector3.BACK*.35)
			move_cpu(setter,destination,delta,5.3,toward_incoming(setter,destination),true,true)
			teaching_moves[setter]=true
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
			if teaching_moves.has(i) or is_human(i) or owns_action(i) or recoveries.has(i) or blocks.has(i): continue
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

func planned_pass() -> bool:
	return scripted_pass() or (flight_kind=="pass" and planned_flight==flight_number)

func set_height_error(error:float) -> float:
	if scripted_pass(): return clampf(error,-.04,.04)
	return super.set_height_error(error)

func six_set_tempo(hitter:int,point:Vector3) -> int:
	if planned_pass() and hitter==feed_hitter: return feed_tempo
	return super.six_set_tempo(hitter,point)

func prepare_middle_quick(side:int,delta:float) -> void:
	if planned_pass() and side==1 and feed_hitter==front_middle(side) and feed_tempo>=2: return
	super.prepare_middle_quick(side,delta)

func hitter_for_set(setter:int,allow_quick:bool=true) -> int:
	if team(setter)==1 and receiving_team==1 and flight_kind=="pass":
		if scripted_pass(): return feed_hitter
		if not attack_options.is_empty() and possession_team==1 and touches==1 and planned_flight!=flight_number:
			var route:String=attack_options.keys().pick_random()
			feed_hitter=first_on(1)+lineup_roles[1].find(role_for_route(route,setter_zones[1]))
			feed_tempo=attack_options[route]
			planned_flight=flight_number
		if planned_flight==flight_number: return feed_hitter
	return super.hitter_for_set(setter,allow_quick)

func choose_at_set_contact(setter:int,point:Vector3) -> void:
	if planned_pass() and team(setter)==1:
		rally_hitter=feed_hitter
		return
	super.choose_at_set_contact(setter,point)

func select_receiver() -> void:
	super.select_receiver()
	if planned_pass():
		cpu_dump=false
		cpu_fake_dump=false

func start_second_ball_spike(index:int,require_open_lane:=false) -> bool:
	if planned_pass(): return false
	return super.start_second_ball_spike(index,require_open_lane)

func attack_lane_for(index:int) -> Vector3:
	var lane:=super.attack_lane_for(index)
	if not lane.is_finite() and lineup_role(index)==3 and (index==feed_hitter or (team(index)==1 and attack_options.has("right"))):
		return Vector3(-3.65,.065,.82)
	return lane

static func role_for_route(route:String,rotation:int) -> int:
	for role in range(1,6):
		if Formation.attack_route(role,rotation)==route: return role
	return -1

func start_attack_plan(defense:int,offense:int,choices:Dictionary,in_system:bool,repeat_feed:=false) -> bool:
	var enabled:Dictionary={}
	for route:String in ROUTES:
		var value:int=choices.get(route,-1)
		if value>=0 and value<=3: enabled[route]=value
	if enabled.is_empty(): return false
	var route:String=enabled.keys().pick_random()
	start_feed(defense,offense,role_for_route(route,offense),in_system,enabled[route],enabled,repeat_feed)
	return true

func start_feed(defense:int,offense:int,role:int,in_system:bool,tempo:int=2,choices:Dictionary={},repeat_feed:=false) -> void:
	attack_options=choices.duplicate()
	planned_flight=-1
	released_route=""
	released_tempo=-1
	feed_tempo=clampi(tempo,0,3)
	situation="%d/%d/%d/%d"%[defense,offense,role,int(in_system)]
	feed_number=-1
	cpu_serve_override=1
	if not repeat_feed: reset_match()
	court_velocities.clear()
	movement_times.clear()
	service_team=0
	setter_zones.assign([defense,offense])
	begin_point()
	feed_hitter=first_on(1)+lineup_roles[1].find(role)
	pass_target=SETTER_BASE if in_system else Vector3(-.8,PLAYER_GROUND_Y,.25)
	feed_number=flight_number+2
	serve.test_speed_mps=0.
	serve.tape_clearance=1.
	for i in slots_for(1):
		if active_identities.get(i,-1)==6:
			var target:=frames[0].to_local(players[i].global_position)
			serve.aim(Vector3(clampf(target.x,-3.7,3.7),Flight.FLOOR,clampf(target.z+1.4,9.2,12.4)))
			break
	var roster:=[]
	for i in players.size():
		var actor:=players[i]
		roster.append({"team":team(i),"slot":i,"jersey":actor.get_meta("school_jersey_number",-1),"role":lineup_role(i),"libero":active_identities.get(i,-1)==6,"blocking":actor.attributes.Blocking})
	trace.write("scenario_roster",match_clock,{"players":roster},true)
	start_serve()
	replay.record(self)

func receive_contact(index:int,point:Vector3,motion:Vector3,technique:int) -> void:
	var release:=planned_pass() and team(index)==1
	if flight_kind=="serve" and flight_number+1==feed_number and team(index)==1:
		var target:=frames[1].to_global(pass_target+Vector3.UP*1.9)
		var setter:=choose_setter(1,index)
		var distance:=players[setter].global_position.slide(Vector3.UP).distance_to(target.slide(Vector3.UP))
		var seconds:=clampf(.85+distance/3.,1.65,2.65)
		motion=(target-point)/seconds+Vector3.UP*(.5*Flight.GRAVITY*seconds)
	super.receive_contact(index,point,motion,technique)
	if release and flight_kind=="set" and expected_hitter>=0:
		released_route=Formation.attack_route(lineup_role(expected_hitter),setter_zones[1])
		released_tempo=feed_tempo
