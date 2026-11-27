extends RefCounted

# Independent short beats keep the bubble readable at gameplay distance.
const OPENERS := ["Whistle check!", "Time out!", "Oh, for %$#! sake!", "My clipboard just flinched.", "Hang on!", "Mercy!", "Sweet jumping kneepads!", "Who ordered that?!", "Well, butter my whistle!", "Hold the phone!"]
const CHEERS := ["Yes!", "Look at that!", "Frame that one!", "Now we're cooking!", "Beautiful!", "That's the ticket!", "Bench, did you see that?", "Print it!", "There we go!", "That's volleyball!"]
const NEXT := ["Again!", "Reset those feet.", "Show me the next one.", "Take a breath.", "You've got another shot.", "Eyes up.", "Back to work.", "Let's see it.", "Your move.", "I'm watching."]
const LINES := {
	"dismiss":["Get off the court! Next runner!", "Back of the line! I ordered a shuffle!", "Great sprint. Wrong drill. Next!", "Off the court! Those feet owe me a shuffle!", "Next athlete! Take those racing shoes with you!", "Back of the line! My clipboard needs a minute!"],
	"shuffle":["Hold focus and slide!", "Keep those feet shuffling!", "Save the sprint for the straight!", "Slide all the way across!", "Stay square to the net!", "Sideways, superstar!"],
	"run":["Release focus and run!", "Take the brake off!", "Free those feet!", "Run the straightaway!", "Save the shuffle for the corner!", "Let go of that trigger!"],
	"lane":["Follow the green square!", "That's a shortcut!", "The corner's over there!", "No sightseeing!", "Stay in your lane!", "Touch every corner!"],
	"miss":["Beat the ball to the spot!", "Read it sooner!", "Find the contact point!", "Watch the ball in!", "Get set before contact!", "Give yourself a chance!"],
	"praise":["Great job! That's the rhythm!", "I'd put that on film!", "Just like practice!", "The timing was money!", "You made that look easy!", "That's how we do it!"]
}

static func line(event:String) -> String:
	var lead:Array=CHEERS if event=="praise" else OPENERS
	return "%s %s %s"%[lead.pick_random(),LINES[event].pick_random(),NEXT.pick_random()]
