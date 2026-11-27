extends RefCounted

const Bank=preload("res://scripts/coach_line_bank.gd")
const CUES:={"dismiss":"Next runner!", "shuffle":"Hold focus and slide!", "run":"Release focus and run!", "lane":"Touch the corner!", "miss":"Watch the ball!"}
static var positive:Array=[]
static var negative:Array=[]

static func line(event:String) -> String:
	var praise:=event=="praise"
	var deck:=positive if praise else negative
	if deck.is_empty():
		deck.append_array(Bank.PRAISE if praise else Bank.CORRECTION)
		deck.shuffle()
	var joke:String=deck.pop_back()
	return joke if praise else joke+" "+str(CUES.get(event,"Reset!"))
