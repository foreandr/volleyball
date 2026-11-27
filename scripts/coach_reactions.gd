extends RefCounted

const Bank=preload("res://scripts/coach_line_bank.gd")
const CUES:={"dismiss":"Next runner!", "shuffle":"Hold focus and slide!", "run":"Release focus and run!", "lane":"Touch the corner!", "miss":"Watch the ball!"}
const BAFFLED := [
	"?", "??????????", "wat", "sir.", "...", "HOW", "please explain the triangle.",
	"i have refreshed the page. still happened.", "was that on purpose y/n", "citation needed",
	"who installed that", "brb telling the internet", "my other eyebrow just logged in",
	"404: explanation not found", "the floor has left the chat", "unplug it. the whole gym.",
	":|", "o_O", "well that was certainly a thing", "that move is a .zip file",
	"loading excuse... 3%", "WHY IS THERE A SECOND CURSOR", "unsubscribe",
	"did you get that off a toolbar", "the replay has requested a replay",
	"I clicked no and it happened anyway.", "please insert disc 2", "can the witnesses log off",
	"new folder (17)", "I have enabled confusion.", "who gave the ball admin",
	"this is why we lost guestbook privileges"
]
const APPROVAL := [
	"!", ":D", "yes.", "approved by all three pixels", "saving that as final_FINAL.gif",
	"+1 internet", "do it again my webcam was off", "five stars. site only goes to four.",
	"you may enter the secret page", "high score: yes", "adding this to my away message",
	"somebody put flames on that username", "the hamster is pleased", "the dial-up noise stopped for you",
	"achievement unlocked: coach quiet", "this gets its own forum signature"
]
static var baffled:Array=[]
static var approval:Array=[]
static var positive:Array=[]
static var negative:Array=[]

static func line(event:String) -> String:
	var praise:=event=="praise"
	if randf()<(.48 if praise else .72):
		var short_deck:=approval if praise else baffled
		if short_deck.is_empty():
			short_deck.append_array(APPROVAL if praise else BAFFLED)
			short_deck.shuffle()
		return short_deck.pop_back()
	var deck:=positive if praise else negative
	if deck.is_empty():
		deck.append_array(Bank.PRAISE if praise else Bank.CORRECTION)
		deck.shuffle()
	var joke:String=deck.pop_back()
	return joke if praise else joke+" "+str(CUES.get(event,"Reset!"))
