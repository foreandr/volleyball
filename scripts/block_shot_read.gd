extends RefCounted

# Learn from completed shots. Keep the lateral angle continuous so a sharp
# cross and a shallow cross can still lead to different blocking positions.
var history: Array[float]=[]
var prediction := 0.
var confidence := 0.

func shade(distance: float,remaining := 0.) -> float:
	var offset := clampf(prediction*clampf(distance,.45,2.),-1.55,1.55)
	if confidence>.54 and history.size()%3!=0:
		return lerpf(offset,-offset*.45,smoothstep(.34,.68,remaining))
	return offset

func record_velocity(velocity: Vector3) -> void:
	if absf(velocity.z)>.1: observe(velocity.x/absf(velocity.z))

func observe(slope: float) -> void:
	history.append(clampf(slope,-2.,2.))
	if history.size()>20: history.pop_front()
	var last := history.size()-1
	var best_length := 0
	var weight_sum := 0.
	var weighted := 0.
	var squared := 0.
	for i in range(last):
		var length := 0
		while length<3 and i>=length and absf(history[i-length]-history[last-length])<.36:
			length+=1
		if length==0 or length<best_length: continue
		if length>best_length:
			best_length=length
			weight_sum=0.
			weighted=0.
			squared=0.
		var weight := pow(.84,last-i-1)
		var following := history[i+1]
		weight_sum+=weight
		weighted+=following*weight
		squared+=following*following*weight
	if weight_sum<.30:
		prediction=history[last]*.82
		confidence=.25
		return
	prediction=weighted/weight_sum
	var scatter := sqrt(maxf(0.,squared/weight_sum-prediction*prediction))
	confidence=clampf((.32+.22*best_length+.10*weight_sum)/(1.+2.*scatter),.15,1.)
