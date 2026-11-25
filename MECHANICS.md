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
