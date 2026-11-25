extends RefCounted

# Learn from completed shots. Keep the lateral angle continuous so a sharp
# cross and a shallow cross can still lead to different blocking positions.
var history: Array[float]=[]
var prediction := 0.
var confidence := 0.

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
