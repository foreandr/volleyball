extends RefCounted

const DIVE_COST := 28.0
const SPRINT_DRAIN := 25.0
const RECOVERY_DELAY := 0.7
const RECOVERY_RATE := 17.0

var spent_total := 0.0
var value := 100.0
var delay := 0.0
var exhausted := false

var endurance := 65.

func effectiveness() -> float:
	return clampf(value/100.,0.,1.)

func can_sprint() -> bool:
	return not exhausted and value > 0.0

func spend(amount: float) -> void:
	amount=maxf(0.,amount)*100./(67.5+.5*endurance)
	spent_total+=minf(value,amount)
	value = maxf(0.0,value-amount)
	delay = RECOVERY_DELAY
	if value <= 0.0: exhausted = true

func recover(delta: float) -> void:
	var rest := maxf(0.0,delta-delay)
	delay = maxf(0.0,delay-delta)
	value = minf(100.0,value+rest*RECOVERY_RATE)
	if value >= 25.0: exhausted = false
