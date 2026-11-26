# Volleyball mechanics

Use this index when tuning a rep. Each row identifies the inputs to inspect and where they enter play.

| Mechanic | Interacting inputs and result | Implementation |
|---|---|---|
| Jump serve contact | Spin, float and hybrid jump serves check the descending toss against the airborne striking hand throughout the toss contact window. These serves use a stronger back arch and forward leg and torso pike. | serving_camp.gd and attacking_camp.gd |
| Serving drill reception | Before the toss the server can walk, shuffle or sprint along the service area. During the toss the stick aims. The nearest passer reads the projected forearm contact and moves to receive. Receivers use the shared directional reach, knee and low-save poses. A reachable high float can be taken overhead. Serve pace, spin, platform alignment and effective forearm reception influence pass location and height. Chasing fast serves and reaching off-center increase dispersion. Rushed setter arrivals also reduce set accuracy. The setter starts in zone one and releases toward the net after service contact. A reachable pass lets the setter jump-set when arrival time, stamina and airborne setting range allow, or stand and hand-set toward the receiving team’s zone-four hitter. The outside attacks against three server-side blockers who close and jump when within reach. | serving_camp.gd |
| Attack contact at the selected pin | Standing reach and current jump determine the physical strike height. Before takeoff, the attack drill estimates jump from vertical and hitter stamina. After takeoff it uses the committed jump. Bell reads that loss using his own effective Hand setting. At full skill he places the ball at the estimated palm height. At lower skill the set can stay slightly high. The residual is (1 âˆ’ skill fraction) times the smaller of lost reach and 30 cm. | Attacking camp, both CPU and player hitting, attacking_camp.gd |
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

Setterâ€“hitter chemistry could improve anticipation on quick sets. A general Game sense rating could eventually inform a setterâ€™s read across multiple decisions. Neither is a separate rating in the attack contact calculation today.

Attack staging reserves roughly 2.7â€“2.85 m for the approach when space permits. Distance limits the lead step, plant and airborne travel. For a setter jump, a staggered stance drives the trailing knee and a square stance uses both legs. See attacking_camp.gd and setter_jump.gd.

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
Blocking HUD hit speed (9–40 m/s) controls spike power independently of set height. Attack vertical applies on the next feed. CPU closers recheck reach after the lead jumps.
On wide quicks the middle reads the inside hitting lane, counts closing momentum, and can take a late loaded jump with a torso lean and one-hand reach. Once struck, the ball velocity informs the last reach check at the net.
On pin sets each closer evaluates their own adjacent strip of net toward cross court. Reachable CPU blockers may take off independently at the last viable instant if the lead has not jumped.
Approach and Spike exposes saved attacker vertical (inches) and nominal hard-hit speed (m/s) directly on the HUD. They feed the jump and swing calculations for human and CPU attacks.
Approach and Spike lets the hitter train against zero to three CPU blockers in Pause > Sliders. Block touches use the same swept arm and hand contact, deflection and impact audio as blocking practice.
Attack practice uses the right-side blocker for singles and adds the middle for doubles. Each has a saved block vertical. Ball speed controls display km/h while simulation and saved speed values remain in m/s.
Attack placement allows 2.5 m to either side of the selected lane. The 6 ft 5 in practice blockers shade their read immediately toward each observed shot direction, using recent sequences of up to three shots to predict the next lane. Confident attack-drill blockers can show an opening before closing late and drifting into a Kong. The attack HUD block vertical controls the pin blocker.
Player identification rings are depth-tested court geometry. The timing band shares the ring’s ground plane. Missed attacks play a soft first floor impact. Attack replay includes blocker arm capsules and impact cues. In double blocks the middle closes alongside the pin and presses straight, reserving a one-handed reach for an exposed outside edge.
Above-tape penetration with a square palm or distal forearm contact drives a stuff toward the floor just behind the opposing net. Glancing contact stays playable.
In attacking and blocking practice the four set arc presets use 15%, 40%, 70%, and 130%.

Pause > Attack setup contains the Coach, Setter, Set and Hitter map. Play starts a fresh feed. With three blockers, the pin on the set side leads the close.

All four attack setup markers allow one meter outside either sideline and 1.5 meters behind the baseline within the gym runoff.

A stuff block retains 60% of incoming ball speed at arm contact in drills and matches.
In attacking and blocking practice, two untouched middle quicks landing in court trigger a CPU middle commit. Two untouched quick scores or successful middle touches among the last ten quicks sustain the commit. The drill HUD retains block contact and distinguishes block out from untouched out. Sliders can order a middle commit. A block contact identifies the blocker, arm and collision segment.
On middle quicks, read and commit timing both support a disguised lane, late lateral correction, torso lean, a two-hand spread or a one-arm Kong into an open lane. Nearby teammates limit inward reach.
Active blocks also collide across both shoulders, neck and head. These contacts use soft deflections and count toward block-out attribution in the drills. Replay shows the same body capsules.
Blocking capsule radii are 18 cm at the hand, 14.25 cm at the forearm, 15.75 cm at the shoulder and about 13.2 cm at the head.
Spike approaches drive both hands overhead during the final plant. Airborne CPU drill blockers prioritize a reachable ball above the tape over their lane disguise or spread.
Both arms use the same forward lift arc on short and full spike approaches. The arc starts up to 65 ms earlier while retaining its original key intervals.
Full spike approaches reserve up to 0.90 m of forward carry into the contact stance, putting takeoff roughly one metre behind the ball. Runway and available airtime limit carry. CPU read blocks start loading 35 ms earlier.
Near the net, attack and drill block poses check both arm chains and the upper body against the tape before accepting forward travel.
In practice replay, right-stick click toggles normal playback and the last selected slow speed (initially half speed). Left-stick click toggles block hitboxes wherever they are available.
Training Camp serving locks the toss on first press. A selects topspin and B selects jump float. Switching A/B before release changes the strike and flight. X selects standing float and Y underhand. Release near contact to serve toward three receivers.
Serve release uses the attack ground timing arc. Its colored bounds use the same early, perfect and late thresholds as serve contact. Jump serves use the attack front lift and spike arm swing after the toss step, with a firm wrist for float hits.
Once a jump-serve toss leaves the hand it becomes a live set trajectory. Serving uses the attacking drill plant, jump, swing, palm-contact test and follow-through. Toss and outgoing flight retain their selected serving techniques.
Serving practice uses a 57-inch fresh jump vertical and ballistic toss apexes of 7.4 m for spin and 6.1 m for jump float. Approach and release timing use the descending contact time.
