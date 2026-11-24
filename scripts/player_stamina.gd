extends RefCounted

const DIVE_COST := 28.0
const SPRINT_DRAIN := 25.0
const RECOVERY_DELAY := 0.7
const DEBT_RECOVERY_SCALE := .5

var action := ""
var action_cost := 0.0
var action_linger := 0.0
var rating := 65.0
var endurance := 65.0
var willpower := 65.0
var rested_capacity := 350.0
var spent_total := 0.0
var value := 350.0
var delay := 0.0
var exhausted := false

func capacity() -> float:
	return 25.+5.*rating

func fraction() -> float:
	return clampf(value/capacity(),0.,1.)

func set_ratings(pool: float, recovery: float, reserve: float) -> void:
	var previous := capacity()
	rating=clampf(pool,0.,100.)
	endurance=clampf(recovery,0.,100.)
	willpower=clampf(reserve,0.,100.)
	rested_capacity=clampf(rested_capacity/previous,0.,1.)*capacity()
	value=clampf(value/previous*capacity() if value>=0. else value,-willpower,rested_capacity)
	exhausted=value<=-willpower

func effectiveness() -> float:
	# Preserve a small amount of playing strength while the reserve lasts.
	var reserve_strength := .1*(value+willpower)/maxf(1.,capacity()*.1+willpower)
	return maxf(fraction(),clampf(reserve_strength,0.,.1))

func can_sprint() -> bool:
	return not exhausted and value> -willpower

func spend(amount: float, cause := "") -> void:
	var used := clampf(amount,0.,value+willpower)
	if used<=0.: return
	if cause!="":
		if cause!=action or action_linger<=0.: action_cost=0.
		action=cause
		action_linger=.45
		action_cost+=used
	spent_total+=used
	rested_capacity=maxf(0.,rested_capacity-used*.20)
	value-=used
	delay = RECOVERY_DELAY
	if value <= -willpower: exhausted = true

func recover(delta: float) -> void:
	action_linger=maxf(0.,action_linger-delta)
	if action_linger==0.:
		action=""
		action_cost=0.
	var rest := maxf(0.0,delta-delay)
	delay = maxf(0.0,delay-delta)
	var recovery := lerpf(1.,10.,endurance/100.)
	if value<0.:
		var debt_time := minf(rest,-value/(recovery*DEBT_RECOVERY_SCALE))
		value=minf(0.,value+debt_time*recovery*DEBT_RECOVERY_SCALE)
		rest-=debt_time
	rested_capacity=minf(capacity(),rested_capacity+rest*.02*recovery)
	value=minf(rested_capacity,value+rest*recovery)
	if value>=capacity()*.05: exhausted=false
