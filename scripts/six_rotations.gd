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

static func receive_libero(role:int,setter_zone:int) -> bool:
	return role in [2,5] and zone(role,setter_zone) in [1,6,5]

static func key(setter_zone:int,defense:bool) -> String:
	return ("block_" if defense else "receive_")+str(setter_zone)

static func layout(options:ConfigFile,setter_zone:int,defense:bool) -> PackedVector2Array:
	var saved=options.get_value("six_rotations",key(setter_zone,defense),[])
	if saved is PackedVector2Array and saved.size()==6: return saved.duplicate()
	var marks:=PackedVector2Array()
	for role in 6:
		var spot:Vector2=RECEIVE[setter_zone-1][role]/10.
		if defense:
			var front:=zone(role,setter_zone) in [2,3,4]
			var lane:=.5 if role in [2,5] else (.16 if role in [1,4] else .84)
			spot=Vector2(lane,.09 if front else .72)
		marks.append(spot)
	return marks

static func on_court(mark:Vector2) -> Vector3:
	return Vector3((.5-mark.x)*9.,.04,4.-9.*mark.y)
