extends RefCounted

const DIVE_COST := 28.0
const SPRINT_DRAIN := 25.0
const RECOVERY_DELAY := 0.7
const RECOVERY_RATE := 17.0

var value := 100.0
var delay := 0.0
var exhausted := false

func can_sprint() -> bool:
	return not exhausted and value > 0.0

func spend(amount: float) -> void:
	value = maxf(0.0,value-amount)
	delay = RECOVERY_DELAY
	if value <= 0.0: exhausted = true

func recover(delta: float) -> void:
	var rest := maxf(0.0,delta-delay)
	delay = maxf(0.0,delay-delta)
	value = minf(100.0,value+rest*RECOVERY_RATE)
	if value >= 25.0: exhausted = false
