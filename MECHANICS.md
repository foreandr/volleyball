# Volleyball mechanics

Use this index when tuning a rep. Each row identifies the inputs to inspect and where they enter play.

| Mechanic | Interacting inputs and result | Implementation |
|---|---|---|
| Jump serve contact | Spin, float and hybrid jump serves check the descending toss against the airborne striking hand throughout the toss contact window. These serves use a stronger back arch and forward leg and torso pike. | serving_camp.gd and attacking_camp.gd |
| Serving drill reception | Before the toss the server can walk, shuffle or sprint along the service area. During the toss the stick aims. The nearest passer reads the projected forearm contact and moves to receive. Receivers use the shared directional reach, knee and low-save poses. A reachable high float can be taken overhead. Serve pace, spin, platform alignment and effective forearm reception influence pass location and height. On serve reception the extra dispersion from pace, chase and off-center contact is capped at 85% above the shared skill-based spread. Rushed setter arrivals also reduce set accuracy. The setter starts in zone one and stands upright until toss release and then runs toward zone 2�. A reachable pass lets the setter jump-set when arrival time, stamina and airborne setting range allow, or stand and hand-set toward the receiving team�s zone-four hitter. The three passers, middle and opposite wait hands-on-knees. The middle starts near the net facing the server. At toss release the passers become active and the opposite prepares to attack. Rotation-one options are P1, middle, opposite and the back-row pipe. The three server-side blockers close toward the selected lane. | serving_camp.gd |
| Attack contact at the selected pin | Standing reach and current jump determine the physical strike height. Before takeoff, the attack drill estimates jump from vertical and hitter stamina. After takeoff it uses the committed jump. Bell reads that loss using his own effective Hand setting. At full skill he places the ball at the estimated palm height. At lower skill the set can stay slightly high. The residual is (1 − skill fraction) times the smaller of lost reach and 30 cm. | Attacking camp, both CPU and player hitting, attacking_camp.gd |
| Set location and tempo | The marked pin supplies width and depth. Tempo sets flight time. Setter strength and current stamina limit horizontal distance. A jump set has 77% of standing range. Horizontal jump momentum carries into the ball, and Hand setting helps compensate. Even an accurate read of hitter fatigue cannot restore lost setting range. | attacking_camp.gd and volleyball_player.gd |
| Match set height | Incoming pace, distance to the pin, setter location, hitter readiness and transition movement influence the apex. This match planner has its own height calculation. The attack camp fatigue read currently applies to the drill. | volleyball_match.gd, cpu_set_apex |
| Attack timing | Set flight, approach distance, time to plant, jump rise, release and physical hand reach all affect contact. Changing tempo alters when the hitter has to leave the ground. | attacking_camp.gd and setter_jump.gd |
| Attack power and placement | Arm swing, strength, approach momentum and shot type influence the attack. Effective Spike placement drives aiming control. Athleticism and swing intensity shape the heel tuck and forward pike. Net clearance constrains the torso. | attacking_camp.gd |
| Hand setting and forearm play | Effective skill affects timing tolerance. Forearm accuracy also depends on incoming pace, timing and angle. The shared reachable-set calculation handles strength and airborne carry. | indoor_practice.gd, reception_accuracy.gd and volleyball_player.gd |
| Stamina across actions | Stamina rating determines pool size (25 + 5 per point). Sprinting and actions spend it. Spending also lowers recoverable capacity temporarily. Endurance controls recovery after a pause. Willpower permits a reserve below zero, where recovery runs at half speed. Effective skill scales with the remaining fraction, with a small reserve at exhaustion. | player_stamina.gd and volleyball_player.gd |
| Blocking | Blocker position, takeoff timing and vertical determine the space covered at the net. | match_block.gd and blocking_practice.gd |
| Ball flight and net contact | Contact position, launch velocity, gravity and spin shape the flight. Net collision and deformation matter for subsequent touches. | gym_physics.gd, net_collision.gd and dynamic_net.gd |
| Serving | Serve technique selects a motion and flight model. Jump serves also use the configured vertical. | volleyball_match.gd and the individual serve scripts |

## Proposed interactions

Setter–hitter chemistry could improve anticipation on quick sets. A general Game sense rating could eventually inform a setter’s read across multiple decisions. Neither is a separate rating in the attack contact calculation today.

Attack staging reserves roughly 2.7–2.85 m for the approach when space permits. Distance limits the lead step, plant and airborne travel. For a setter jump, a staggered stance drives the trailing knee and a square stance uses both legs. See attacking_camp.gd and setter_jump.gd.

In the attack drill, D-pad Up raises the set tempo preset one height and Down lowers it. The four heights stop at 0 and 3.

At attack takeoff the CPU tests its hard shot against the net using its fatigue-limited reach. A predicted blocked flight triggers a tip for targets under four horizontal meters away or a roll shot for longer placement.

CPU attackers press, hold and release the mapped attack button. The timing meter uses the same release grade as contact. Across the colored window, timing changes placement error. Physical palm reach still matters. Takeoff is timed against the predicted contact at the pin.

CPU hitters conserve stamina at 30% or below. A line bounce requires more than 50% stamina. The hard-shot clearance check allows for the palm contacting below the intended set. A fatigued line bounce becomes a roll shot.

Training Camp Blocking runs the crosscourt attack demo from the left pin. View switches between CPU and manual blocking. The attack set-height controls also apply. Three front-row blockers share coverage. The pin and middle can close together while the far blocker holds coverage. Their shuffle uses the focused hitter speed. A block touch plays the hitter hand-impact sound.
Blocking practice aims down the line, zero to one meter inside the sideline. Eight in ten targets are 4.5 m deep. The rest vary from 4 to 5 m.
Blocking practice supplies a rested hard-driven hitter each rep. This drill fixes the shot type for blocker repetitions.
Blocking feeds alternate line and zone six. Block vertical in inches controls all three blockers. The middle starts closing on the pass, and adjacent blockers split their hand targets at the seam.
Each block jump spends 5 stamina, and available stamina scales the selected vertical. Hold A and release to jump in manual blocking. View switches to the right-side blocker with the camera behind him.
Both drill viewpoints look from behind the blockers. The live HUD vertical slider and pause slider share one saved setting. Blocker stamina remains active with its overlay hidden. The middle returns to center between closes. The far blocker compares travel time with the set and drops into defense when the close is unavailable. Hand, forearm and upper-arm touches direct rebounds toward the attacking court.
Blocking home positions are centered left, middle and right at x = -2.15, 0 and +2.15 m. The coach waits for all three before tossing. The two closing blockers read the released set, comparing remaining flight time to travel and takeoff time, and peel for tips when late. The defensive camera mirrors the attacking camera about center court.
Blocking uses the hitting camera in gym coordinates. Team-local gameplay runs with court ends exchanged relative to the gym.
Blocking practice defaults to 30 m/s nominal attack speed and swing power. Approach momentum still affects actual launch speed.
Manual blocking starts on jersey 509. Holding A loads the squat while the timing cue compares predicted jump apex with attack arrival. Releasing A starts the jump with the loaded portion of takeoff accounted for. The controlled blocker shows a ring and stamina.
On a double block the middle tracks the inside shoulder of the outside blocker and shares the outside jump cue and load timing, including manual releases.
Manual blocker 509 can shuffle once the incoming ball is within one meter of the predicted setter contact point. CPU blockers read the released set.
Block arms extend as wrists cross above the tape. Arm contact uses segment-specific capsule radii, widest at the open hand. Blocking replay samples up to 60 poses per second and replays the hand sound on a recorded block touch.
Holding A on 509 layers the shuffle over the loaded squat while moving laterally. Recorded spikes, block touches and spike floor contacts trigger the impact recordings in replay playback.
Blockers bring their legs slightly forward as they press at jump apex. Forward foot travel is limited near the net and blends out before landing.
At peak block press, the hips shift back, the chest folds and both legs extend forward toward an attack-style pike. Available net clearance limits the leg angle.
Practice replay supports camera translation and look on the sticks, analog timeline scrubbing on the triggers, bumper elevation and X/B zoom.

In blocking camp the airborne left stick leans the torso toward screen left or right. LT and RT spread the respective arms independently. A central pressed hand above the tape can stuff the attack. Glancing touches pop up on the contact side.

Blocking camp independently draws the left pin, 51, pipe or right pin on each feed. All four hitters reset. A single held trigger reaches laterally over the tape with the other arm dropping for balance. Both triggers spread both arms. Replay can display the recorded arm capsules and interpolate four inspection positions per sample.

In blocking practice, all four attackers run their own approach lanes as the pass reaches Bell. On set release, the three unselected hitters brake into position-specific cover, then recover for the next feed.

The CPU middle can commit to a nearby quick runner accelerating toward Bell before release. This read uses the visible approach and can leave the middle airborne against a pipe or pin set. Each rep logs the released route and endpoint.

The pipe covers deep in six, the far pin shades inward from its own lane, and nearby front-row hitters cover shorter. The middle runs a 50 or 30 at tempo zero every feed, including decoy jumps. The pipe uses tempo 0 or 1. Pins use 0, 1 and 2. Tempo 3 is reserved for out-of-system play.

Random-height blocking feeds assign a separate tempo to every route. Each runner times the approach to that call. Uncommitted blockers observe the released ball before estimating its lateral destination.

Proposed blocker scouting combines rotation-specific set history, sample size and live approach cues. The current blocking drill uses live cues and reaction time.

All blocking-drill hitters transition from running into the shared attack swing. Blocker bumper inputs do not select the CPU shot type.

A fully held Kong reach above the tape extends the selected elbow toward 178 degrees and aligns the fingers with the lateral reach. The neighboring blocker still limits available space.

A manual block release can jump on any phase or repeat after landing. A release during flight queues the next grounded jump. Exhaustion limits its height.

Random height defaults on for blocking. The controlled blocker can move from coach release. Replay Slow-mo cycles half, quarter, eighth and sixteenth speed.

After the dead-ball reset, the ready whistle gives 509 full lateral and depth control until the rally ends. CPU close and peel assignments only steer computer-controlled blockers.

The attack aim selector offers random court placement, targeting the block and avoiding the block. Near the tape, LT squares the blocker to the net. Holding A prepares a swing block and the body completes the turn through takeoff while lateral lean and individual arm reaches remain available.

In the blocking drill adjacent blockers fast-shuffle toward the lead blocker. Nearby partners reserve their half of the seam and keep the inside arm up during a Kong reach. Block vertical restores from saved options when the drill starts.
CPU blockers can Kong toward an uncovered edge using the approaching ball and its outgoing velocity.
On a pin set the lead blocker cues every committed CPU closer to jump. Each closer leans and turns toward the next teammate in the block and carries limited lateral motion into the jump while preserving body spacing.
CPU takeoff checks the ball read against lateral reach, closing momentum and distance from the net. A reachable exposed edge calls for a one-handed Kong. Manual block release remains unconditional.
Blocking HUD hit speed (9�40 m/s) controls spike power independently of set height. Attack vertical applies on the next feed. CPU closers recheck reach after the lead jumps.
On wide quicks the middle reads the inside hitting lane, counts closing momentum, and can take a late loaded jump with a torso lean and one-hand reach. Once struck, the ball velocity informs the last reach check at the net.
On pin sets each closer evaluates their own adjacent strip of net toward cross court. Reachable CPU blockers may take off independently at the last viable instant if the lead has not jumped.
Approach and Spike exposes saved attacker vertical (inches) and nominal hard-hit speed (m/s) directly on the HUD. They feed the jump and swing calculations for human and CPU attacks.
Approach and Spike lets the hitter train against zero to three CPU blockers in Pause > Sliders. Block touches use the same swept arm and hand contact, deflection and impact audio as blocking practice.
Attack practice uses the right-side blocker for singles and adds the middle for doubles. Each has a saved block vertical. Ball speed controls display km/h while simulation and saved speed values remain in m/s.
Attack placement allows 2.5 m to either side of the selected lane. The 6 ft 5 in practice blockers shade their read immediately toward each observed shot direction, using recent sequences of up to three shots to predict the next lane. Confident attack-drill blockers can show an opening before closing late and drifting into a Kong. The attack HUD block vertical controls the pin blocker.
Player identification rings are depth-tested court geometry. The timing band shares the ring�s ground plane. Missed attacks play a soft first floor impact. Attack replay includes blocker arm capsules and impact cues. In double blocks the middle closes alongside the pin and presses straight, reserving a one-handed reach for an exposed outside edge.
Above-tape penetration with a square palm or distal forearm contact drives a stuff toward the floor just behind the opposing net. Glancing contact stays playable.
In attacking and blocking practice the four set arc presets use 15%, 40%, 70%, and 130%.

Pause > Attack setup contains the Coach, Setter, Set and Hitter map. Play starts a fresh feed. With three blockers, the pin on the set side leads the close.

All four attack setup markers allow one meter outside either sideline and 1.5 meters behind the baseline within the gym runoff.

A stuff block retains 60% of incoming ball speed at arm contact in drills and matches.
In attacking and blocking practice, two untouched middle quicks landing in court trigger a CPU middle commit. Two untouched quick scores or successful middle touches among the last ten quicks sustain the commit. The drill HUD retains block contact and distinguishes block out from untouched out. Sliders can order a middle commit. A block contact identifies the blocker, arm and collision segment.
On middle quicks, read and commit timing both support a disguised lane, late lateral correction, torso lean, a two-hand spread or a one-arm Kong into an open lane. Nearby teammates limit inward reach.
Active blocks also collide across both shoulders, neck and head. These contacts use soft deflections and count toward block-out attribution in the drills. Replay shows the same body capsules.
Blocking capsule radii are 14.4 cm at the hand, 14.25 cm at the forearm, 15.75 cm at the shoulder and about 13.2 cm at the head.
Spike approaches drive both hands overhead during the final plant. Airborne CPU drill blockers prioritize a reachable ball above the tape over their lane disguise or spread.
Both arms use the same forward lift arc on short and full spike approaches. The arc starts up to 65 ms earlier while retaining its original key intervals.
Full spike approaches reserve up to 0.90 m of forward carry into the contact stance, putting takeoff roughly one metre behind the ball. Runway and available airtime limit carry. CPU read blocks start loading 35 ms earlier.
Near the net, attack and drill block poses check both arm chains and the upper body against the tape before accepting forward travel.
In practice replay, right-stick click toggles normal playback and the last selected slow speed (initially quarter speed). Left-stick click toggles block hitboxes wherever they are available.
Training Camp serving locks the toss on first press. A selects topspin and B selects jump float. Switching A/B before release changes the strike and flight. X selects standing float and Y underhand. Release near contact to serve toward three receivers.
Serve release uses the attack ground timing arc. Its colored bounds use the same early, perfect and late thresholds as serve contact. Jump serves use the attack front lift and spike arm swing after the toss step, with a firm wrist for float hits.
Once a jump-serve toss leaves the hand it becomes a live set trajectory. Serving uses the attacking drill plant, jump, swing, palm-contact test and follow-through. Toss and outgoing flight retain their selected serving techniques.
Serving practice uses a 57-inch fresh jump vertical and ballistic toss apexes of 7.4 m for spin and 6.1 m for jump float. Approach and release timing use the descending contact time.

In rotation-one serve receive the setter signals the intended attacker and the middle�s 51 or 31 before the toss. Pass depth, travel time, jump reach, hand-setting skill and hitter recovery influence the final call. The opposite attacks on the left, P1 on the right and P2 from the pipe. The contrasting-jersey libero receives without an attack assignment. Receiving teammates steer around occupied ground space.

The setter squares to zone four for front and back sets. The libero takes second contact after the setter receives. Deep passes rule out pipe. On an in-system pass the middle approaches before release. An airborne middle gets zero tempo and a grounded middle gets a one. Ready pin and pipe hitters can also receive a one. Short block closes use lifted shuffle steps, a stable hold allows a deep squat walk, and longer CPU closes turn into a swing block.
The pipe is an occasional in-system combination. A middle must be available for the zero and airborne at release. A broken combination goes to a pin.

Serve rallies continue after playable blocks. The nearest available teammate covers, and the libero sets if the setter took the first touch. Recent scoring makes hitters more attractive. A successful quick draws a middle commit and opens the pipe and pins. Serving HUD skills and verticals apply to the receiving offense and serving-side wall. The serve speed override preserves launch direction and allows testing up to 300 km/h.

CPU blockers remember the direction of completed swings per opposing hitter on the player object. Use that read in drill and match positioning. A receiving libero clears the pipe approach after passing and covers the attack. Facing-preserving retreats use backward footfalls.

During serve reception both pins start forward and draw their arms before the set, then transition to coverage when another attacker gets the ball.
In serving camp, available front-row hitters retreat facing the ball to 3.3 m off the net, and the pipe resets 5.5 m deep. On a playable block the assigned defender covers while the others reopen their approach lanes.
After a covered block in serving camp, grounded defenders shuffle back to their own lanes. Each can shade its base by up to 45 cm using its read of the hitter in that lane before closing on the next set.
Block contacts in attack and serve rallies use the first intersected capsule and deflect according to impact direction. Replay marks the contacted segment in red. The receiving libero clears approach lanes toward deep zone five when free to cover.
Serving-camp rally hitters and middle decoys use the attack-camp plant arm lift and the same airborne pose solver as attack camp. Set tracking and contact timing remain live.
Serve-receive hitters reserve horizontal travel for the airborne approach where space allows. Their strike tracks the incoming set and replay presents the palm contact before the outgoing flight.
In serving camp, D-pad up selects topspin, left/right add sidespin, and down selects float for the spin serve. Accurate releases produce higher pace. Untouched serves rebound from gym surfaces. The setter uses available jump height, approach time and recent missed swings when choosing hitters and pin tempo. A pipe can originate in the back-row hitter's lane. Middle commits require an airborne middle on an in-system pass.

Reception Studio feeds the selected contact region. All three defenders display the shared map of 1.1-meter-wide and 1.1-meter-deep cells in three equal rows spanning 2.20 meters. WASD pans the studio camera.
Studio serves use the region assignment at a saved stance inside a two-meter ready square. Reachable feeds rebound from the forearms. Future coaching strategy will assign ready zones per team, with chase coverage deferred.
Reception Studio uses Ctrl-click for court cells. Explicit animation assignments have dark red outlines, while unassigned cells have dark blue outlines and leave the receiver in the ready pose. Three defenders can be positioned by dragging. The serve arc is fixed. Pass rise and the floor target are saved.

Ctrl-clicking a defender cell repeats a standing float there. Drag the floor ring to aim the return.
In Reception Studio the High Center Body cell defaults to overhead hand pass #10. Each standing float samples a point inside the selected box once per repetition.
Studio overhead hand passes use the shared standing set load, extension and follow-through. Lower centered feeds use legs 4 or 6, low lateral feeds use a short mirrored step from legs 7, and high feeds can trigger a jump set with contact at the apex.
Reception Studio can trace the incoming ball in red only inside the selected defender grid, stopping at a successful pass in live playback and timeline review. The trail resets with each feed and the toggle persists.

Future feature: players can create custom setter hand signs and assign each gesture to a setting option for pre-play calls.
Reflexes (0-100) controls CPU read latency in blocking and digging drills, serve-return defense and match play. Effective Reflexes includes stamina. A live set cues a read block and an attack cues a defensive reaction. At full effectiveness the delay ranges from 240 ms to 60 ms; anticipation on a commit block is separate. Older player profiles default to 65.
Assigned reception misses display the contact gap from the contact frame onward and log time, defender, region, animation, target, and contact position once per live feed. Hand passes lean toward the feed, adjust squat and step depth, and drift toward high feeds in the jump.
High Center in the Back slice defaults to jump set #78, timing an upright directional jump from the predicted hand-contact height and horizontal distance, with lower feeds met on descent.
Back-top jump sets meet the descending serve earlier along its existing flight. The receiver starts loading the knees 0.32 seconds before takeoff, lowers the hips up to 0.17 m from the load alone, and finishes extending during early ascent.
On the studio back-top jump set, backward launch speed is limited so the receiver lands within 20 cm behind takeoff.
In the Body depth slice, High Center is region 17. Its four full-depth quadrants are 17.1 through 17.4, numbered from the upper left in the front view. 17.1 and 17.2 inherit the same overhead hand pass and reach toward their own feeds. 17.3 and 17.4 use the grounded Legs 04 step into the overhead set. Each quadrant supports hover, Ctrl-click, independent assignments and incoming feeds.
Reception Studio remembers Unassigned only. Hidden regions are excluded from drawing and picking. Jump sets aim for contact in front of the head, allow a small torso adjustment, and use backward travel only beyond a five-centimeter tolerance.
Upper front-center region 26 has four independently assignable full-depth quadrants. Upper back regions 7, 8 and 9 default to jump set #78.
Regions 26.1 through 26.4 each have front and back halves, 0.55 m deep, with independent assignments inherited initially from their parent.
The back halves of 26.1 and 26.2 use grounded overhead action 79, stepping toward the incoming ball with Legs 04. Their front halves use action 80, using the spike approach�s right-left plant toward the feed before taking off with setting hands.
Regions 26.3 and 26.4 use directional Legs 02 under an overhead pass. Their front halves first use a grounded right-left approach plant, then adjust the wide step to the remaining reach.
Regions 25 and 27 split top/bottom. Regions 16 and 18 also split left/right. Their upper cells use the right-left plant into a jump set and their lower cells use the grounded plant into Legs 02.
Reception Studio restores the selected defender, region and subdivision. The first assigned region crossed by the incoming flight triggers its reception motion. The occupied box lights green during playback and scrubbing; an unassigned region stays ready unless explicitly auditioned. On an unassigned middle-tier cell, selecting legs auditions the shared forearm platform. Assign saves the choice.
In Reception Studio, Test selected box only limits animation triggers to the selected box, including its unsaved audition. Turning it off restores first-crossed routing.
Region 14 has eight independently assignable sections. Region 23 has upper and lower sections at both depths. Lower back uses Legs 02, lower front uses Legs 03, upper front uses Legs 22, and upper back starts unassigned. Studio forearm motions turn the torso toward the feed during preparation (up to 24 degrees), lean up to three degrees toward the feed, then angle the joined platform up to nine additional degrees toward contact. Reception Studio aims the selected forearm leg clip toward the intercept. Reception hitboxes shows the wrist-to-fingertip, forearm, upper-arm and shoulder-to-upper-chest capsules used during forearm passes, and the hand pocket during overhead passes.
Forearm reception checks the moving ball against the animated reception capsules at 480 Hz once per feed. Playback and replay use the first detected touch. A forearm miss reports the closest separation between surfaces.
Reception Studio has saved bottom-panel feed controls for serve technique, pace in km/h and starting court coordinates. Close forearm misses can use a small additional leg reach, with contact checked again against the animated capsules.
Random assigned boxes picks an assigned region on the center receiver and a point inside it for each studio feed. Repeats are allowed. Disabling it restores the manual selection.
Outgoing receptions carry backspin about the horizontal axis across the pass direction. Fast forearm receptions scale to 47 degrees of post-contact bend at 120 km/h.

Reception Studio, serve reception, CPU digs and match reception use the shared arms-out gesture on a CPU out call.
Indoor service placement and approach setup use the expanded gym runoff.
Reception Studio bends slower feeds more and plans net clearance and an in-court descent through the selected contact point when feasible.
Reception Studio credits a forearm reception within 2 cm of its contact capsules at the closest sampled instant.
Reception Studio faces receivers toward the service origin and previews CPU hold and release timing on the shared floor ring. The release sample stays fixed when replaying the feed.
Overhead serve receptions leave the hands with 0.25 revolutions per second of backspin for both float and spin serves.
Reception Studio measures remaining reach at contact and blends a body adjustment into assigned receptions. Sampled poses lift to clear the court at the feet, knees, hips, hands and head.
Reception Studio review starts at serve contact on frame zero and advances to the next repetition immediately after the ball reaches the floor.
Reception Studio splits box 22 vertically into left and right halves. Both inherit the previous box assignment until individually reassigned.
Each side of box 22 also has separate front and back targets, inheriting its side assignment.
The current map merges 22 and 23 into a double-width region with two full-depth height bands. The lower band is split left and right. Both lower regions start unassigned.
Within 22-23.bottom.left, near and far divide the lateral reach from the receiver in two. Both span the full depth.
22-23 now has four full-depth lateral columns in each of two rows. The finished bottom-left near region uses 72. Its opposite-body counterpart is 24.bottom.near and plays mirrored.
Reception Studio saves a lead-foot choice per region. Animation 72 leads right in 22-23.bottom.right.left and left in 22-23.bottom.right.right.
Every Reception Studio forearm leg movement can swing the joined platform toward the intercept. The reaching shoulder drops with lateral error, up to 20 degrees, unless the clip specifies its own drop.
Reception Studio leg movement 33 can use the spike approach right plant and closing left step during the simulated hold. Distance depends on the projected contact and available time, with up to 32 cm of travel before the lunge.
14 is mapped to 22-23.top.left.near and its mirror 24.top.near. Its chin tucks and the shoulder dip increases with lateral reach.
Reception Studio zones 13 and 15 use opposite orientations of Legs 21 for lateral forearm passes.
Reception Studio zones 19 and 21 use opposite orientations of Legs 21 with a forearm platform. Unassigned low and middle zones preview leg choices with the forearm platform.
In zones 19 and 21, Legs 21 uses a wider, deeper lunge, extra torso lean toward contact, and a two-step entry of up to 60 cm in 0.23 seconds when time and distance allow. Low contact corrections deepen the squat over the planted foot.
Zone 20 uses the low Legs 21 reception on both full-depth halves. The left half defaults to a right-foot lead and the right half to a left-foot lead.
Zones 10 and 12 use mirrored Legs 21 forearm passes. The receiver reads an earlier point on the incoming flight and reaches the joined platform in front of the shoulders.
Both upper-right sections of the combined 22-23 zone use Legs 04 for forearm reception.
Zone 14 uses Legs 04 with the early forearm intercept on both depth halves. Upper quadrants 14.1 and 14.2 add a grounded backward two-step with a lower hand target. Lower quadrants 14.3 and 14.4 meet the ball from the ground.
Jump floats load the legs and torso before contact and pike through the follow-through with a firm striking wrist.
Reception Test and Reception Studio share region assignments, mirrored poses, lead feet and saved receiver positions. Zones 1 through 6 have no default assignment. In the test the first assigned region on the serve path wins, with the closer receiver taking simultaneous overlaps. The three receivers use the studio forearm and overhead motions.
Serve receive shades toward in-bounds aces in Reception Test, Serve and Receive, and CPU match reception. Nearby repeated landings strengthen the read; successful first contacts reduce it. The off-blocker in Serve and Receive also learns from uncovered attack landings. Tactical offsets apply to the saved base formation for the current session.
Reception Test flashes the receiving court perimeter green for an ace or red for a serve fault at the surface for one second; review preserves the call. Practice replay records spike-serve hand contact, attack contact and the serve landing.
Before a serve in Serving Camp and Reception Test, LB and RB rotate the held ball in opposite directions. A tap turns five degrees; a hold turns continuously. The chosen panel orientation starts each toss and persists between serves and launches.

In Reception Test the left pin walks into the approach during the pass and attacks deep zone six. The server can move into defense, hold A and release near platform contact to dig.
During serve receive, hitters shuffle to a setup spot that varies each rep, then walk forward with the pass and carry their stride into the plant. In Reception Test, the incoming attack selects the defender�s assigned reception motion. The floor timing arc tracks the A release against the predicted contact.
In Reception Test, attack speed scales the defender's preparation up to 1.8x. The assigned pose reaches its contact frame early and holds through the predicted arrival.
In Reception Test, a serve outside all stationary contact maps triggers a ball-facing sprint shuffle toward a reachable assigned motion, including forward and backward coverage.
In Reception Test, recorded digs include the defender's mapped pose. Dig release timing also accepts actual platform contact, and successful digs rise 3.4 m above contact. The libero shifts in depth on uncovered serves across all three lanes.
