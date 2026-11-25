# Volleyball mechanics

Use this index when tuning a rep. Each row identifies the inputs to inspect and where they enter play.

| Mechanic | Interacting inputs and result | Implementation |
|---|---|---|
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
Blocking practice uses 30 m/s nominal attack speed and swing power. Approach momentum still affects actual launch speed.
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
