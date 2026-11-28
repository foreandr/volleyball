extends RefCounted

# Role order is the starting lineup in zones 1 through 6.
const ROLES := ["Setter","P1","M1","Opposite","P2","M2"]
const SHORT := ["S","OH1","M1","RS","OH2","M2"]
# Serve-receive marks from the supplied diagram, viewed looking toward the net.
# Each pair is horizontal position and depth as tenths of the half court.
const RECEIVE := [
	[Vector2(9,3),Vector2(8,1.5),Vector2(5.5,3),Vector2(2,7),Vector2(5,7),Vector2(8,7)],
	[Vector2(7,2),Vector2(5,3.5),Vector2(2.6,3.5),Vector2(2.8,7),Vector2(5.3,7),Vector2(8,7)],
	[Vector2(6,2.5),Vector2(2.8,3.2),Vector2(3,7),Vector2(5.4,7),Vector2(8,7),Vector2(7.5,4.2)],
	[Vector2(2.2,1.1),Vector2(2.8,7),Vector2(5.4,7),Vector2(8,7),Vector2(7.4,3.8),Vector2(2.9,3.8)],
	[Vector2(1.8,2.6),Vector2(2.7,7),Vector2(5.6,7),Vector2(8,7),Vector2(5.2,3),Vector2(1.2,.9)],
	[Vector2(6,2.5),Vector2(8,7),Vector2(8.7,3),Vector2(4.7,1.3),Vector2(2,7),Vector2(5.3,7)]
]

# Saved setter-in-one defense. Each role uses its counterpart's spot when
# the other member of the pair rotates to the same row.
const BLOCK_DEFENSE := [
	Vector2(.8412067,.46990514), Vector2(.2904119,.035), Vector2(.52932805,.035),
	Vector2(.7567991,.035), Vector2(.48354766,.76305836), Vector2(.17309974,.46132505)
]

static func lineup(players:Array) -> PackedInt32Array:
	var roles:=PackedInt32Array([-1,-1,-1,-1,-1,-1])
	var remaining: Array = range(6)
	for i in 6:
		var role:String=players[i].attributes.get("position","")
		var index:=ROLES.find(role)
		if remaining.has(index):
			roles[i]=index
			remaining.erase(index)
	for i in 6:
		if players[i].attributes.get("position","")=="Libero":
			for middle in [5,2]:
				if remaining.has(middle):
					roles[i]=middle
					remaining.erase(middle)
					break
	for i in 6:
		if roles[i]<0: roles[i]=remaining.pop_front()
	return roles

static func zone(role:int,setter_zone:int) -> int:
	return posmod(role+setter_zone-1,6)+1

static func back_row_libero(role:int,setter_zone:int) -> bool:
	return role in [2,5] and zone(role,setter_zone) in [1,6,5]

static func key(setter_zone:int,defense:bool) -> String:
	return ("block_" if defense else "receive_")+str(setter_zone)

static func layout(options:ConfigFile,setter_zone:int,defense:bool) -> PackedVector2Array:
	var saved=options.get_value("six_rotations",key(setter_zone,defense),[])
	if saved is PackedVector2Array and saved.size()==6: return saved.duplicate() if defense else legal_receive(saved,setter_zone)
	var marks:=PackedVector2Array()
	for role in 6:
		var spot:Vector2=RECEIVE[setter_zone-1][role]/10.
		if defense:
			var front:=zone(role,setter_zone) in [2,3,4]
			var template_front:=zone(role,1) in [2,3,4]
			spot=BLOCK_DEFENSE[role if front==template_front else (role+3)%6]
		marks.append(spot)
	return marks if defense else legal_receive(marks,setter_zone)

static func on_court(mark:Vector2) -> Vector3:
	return Vector3((.5-mark.x)*9.,.04,4.-9.*mark.y)

# Each edge orders two rotational slots along x (sideline) or y (net depth).
static func receive_edges(rotation:int) -> Array[Vector3i]:
	var edges:Array[Vector3i]=[]
	for pair in [Vector3i(4,3,0),Vector3i(3,2,0),Vector3i(5,6,0),Vector3i(6,1,0),
			Vector3i(4,5,1),Vector3i(3,6,1),Vector3i(2,1,1),
			Vector3i(4,1,1),Vector3i(2,5,1)]:
		var edge:=Vector3i(posmod(pair.x-rotation,6),posmod(pair.y-rotation,6),pair.z)
		edges.append(edge)
	return edges

static func legal_receive(source:PackedVector2Array,rotation:int) -> PackedVector2Array:
	var marks:=source.duplicate()
	for i in marks.size(): marks[i]=marks[i].clamp(Vector2.ONE*.035,Vector2.ONE*.965)
	var edges:=receive_edges(rotation)
	# Repair old formations locally, splitting each overlap between the two feet.
	for iteration in 32:
		var changed:=false
		for e in edges:
			var near:=marks[e.x]
			var far:=marks[e.y]
			if near[e.z]<=far[e.z]: continue
			var midpoint:float=(near[e.z]+far[e.z])*.5
			near[e.z]=midpoint
			far[e.z]=midpoint
			marks[e.x]=near
			marks[e.y]=far
			changed=true
		if not changed: break
	# Eliminate any remaining floating-point residual in topological order.
	for e in edges:
		var far:=marks[e.y]
		far[e.z]=maxf(far[e.z],marks[e.x][e.z])
		marks[e.y]=far
	return marks

static func receive_bounds(marks:PackedVector2Array,role:int,edges:Array[Vector3i]) -> Rect2:
	var low:=Vector2.ONE*.035
	var high:=Vector2.ONE*.965
	for e in edges:
		if role==e.x: high[e.z]=minf(high[e.z],marks[e.y][e.z])
		elif role==e.y: low[e.z]=maxf(low[e.z],marks[e.x][e.z])
	return Rect2(low,high-low)

static func from_court(point:Vector3) -> Vector2:
	return Vector2(.5-point.x/9.,(4.-point.z)/9.)
