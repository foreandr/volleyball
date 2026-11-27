# Volleyball feature record

The following describes the intended full game. A menu route, stored rating or prototype does not establish that a feature is finished.

## Indoor practice baseline

Dig from Five shares the Serve and Receive camera: 52-degree field of view, pivot (0, 1.5, -4.4), and arm length 0.48 times the saved distance plus 2 metres, with the same orbit, elevation and gym obstruction check. Middle-button drag orbits the live digging camera for the current visit. Reopening the drill restores this opening view. The coach feeds a far-side setter for a zone-four attack against one pin blocker; the near-side defender starts in five.

The studio places the receiver in a two-meter ready square in the indoor gym and previews serves across three widths, three heights and three depths around each of the three defenders. The top edge stays 2.20 meters above the grid base. Existing bottom and upper assignments carry into the bottom and top rows. In Dig from Five, holding A prepares the mapped movement for the projected contact and releasing A times the dig. Dives are separate full-body actions.

For a two-arm forearm reception, dig, or bump set, establish one platform before the footwork develops. The shoulders reach together, the elbows extend toward the ball, and the hands stay clasped as the elbows absorb impact. The rendered pose and replay must preserve that same platform through the lunge. Overhead hand sets use their own hand shape.

In serve-and-defend rallies the server can move into defense after recovering from the serve. A pin blocker who cannot close in time peels into short defense, shuffling while facing the ball and attempting digs alongside the server.

CPU hitters recover off the net with a forward-facing shuffle toward the three-metre line before their next approach.

During live play, coaches and athletes track the active ball with bounded head yaw and pitch. Tracking eases off during fast chases and when the ball passes behind them.

A new indoor drill starts with practice already happening in a staffed gym. Inherit `scenes/indoor_practice.tscn` and extend `scripts/indoor_practice.gd`. The career setter tryout uses this entry point. Older standalone drill scenes predate it and require migration when revised.

| Carry into the next drill | Shared implementation and behavior |
| --- | --- |
| Gym and people | Rooted hair strands respond to head motion and air movement. Court shoes vary in collar height and upper construction. Oversized practice jerseys hang over the shorts, with longer sleeves and loose hems. Shorts, jersey hems and cuffs ripple with movement and settle at rest. Keep the court, flexible net, posts, seated teammates, bleachers, scoreboard, lighting and camera collision. Use the player profile, numbered practice jerseys, varied bodies and equipment, and the coach’s separate outfit. See `tryout_gym.gd`, `practice_kit.gd`, `bleacher_seat.gd` and `gym_physics.gd`. |
| Practice in progress | `tryout_rotation.gd` owns the coach’s supply, issued balls, loose balls, pickups, deposits and cart exchanges. Coach and crew use the same distance-driven walking pose with both hands on the cart. The coach turns the cart toward each station before pushing forward. CPU setters and demonstrations use neutral tempo. The athlete starts neutral and can select another tempo. The one-time net guide introduces seven spots and three arcs. Acknowledge it with the Xbox confirm glyph. All three rounds feed the active forehead with no horizontal chase. The crew stops moving when standings appear. Three setters each take 10, 32 and 72 at zones 1, 6 and 5. Rank their nine sets by targets made, then cumulative target error (unreleased balls count as ten metres), then roster order for an exact tie. The top-center score strip tracks makes and attempts for all three setters. Each scored attempt gives color feedback and a brief sound through the master volume. The results name the starter, backup and cut and offer restart or continue. Six crew members work in pairs. Human players can shag, move and set between turns. A stationary outgoing setter clears the next setter’s spot even after manually jumping or collecting a ball. Credit Team Chemistry on completed human returns. |
| Crew decisions | When supplies run low, roaming crew can take a ball from the off-turn setter and replenish the coach directly.  Reserve a reachable ball, approach from outside, yield to the feed, pick up, carry, deposit and return to station. Leave balls under the stands. When losses reduce usable inventory below ten, stage a replacement at a sideline cart for the crew. Final body turns have speed and acceleration limits. A final skeleton modifier bounds torso, neck and limb rotations and their per-frame changes across clip and procedural transitions. Walking without progress for one second triggers recovery around obstacles and people. Preserve physical contacts during recovery. |
| Xbox controls | Use `xbox_controls.gd` for bindings and button images. LT squares up, RT sprints, and LT + RT gives a faster shuffle. With LT held, X calls the 10, Y the 32 and B the 72 back set. Hold Xbox A to load a jump and release it to take off. LS click toggles the trajectory. Right-stick up/down selects high/fast tempo and either horizontal direction selects normal. The selection persists across sets and CPU turns. Moving the stick previews the arc before a target button is held. The active setter has a gold surname on the existing stamina ring. |
| Ball contact and feedback | Hold to prepare, release at the hands. Incoming flight and physical hand contact govern timing. A valid hand release sends the set even when the standing or jumping technique misses the rep objective. Keep skill-based timing windows, the floor ring, surname, stamina, jump and set cues, and the target glyph. Focus turns through the shortest angle, brakes at the selected stance and holds that heading. At release, facing the set reduces placement scatter for human and CPU setters. Back sets use a net-facing stance and a wider angular tolerance. CPU setters run to late balls and square up when time allows. On stationary reps the coach aims above the active setter’s forehead at their own height. Human and CPU setters can rotate and jump with their feet planted horizontally. |
| Review | Pause offers Reset drill to restart the session at rep one with fresh carts and crews. Career rewards already earned stay credited. Preserve input and interaction traces, the visible clock and rolling recordings. Watch a rep at gameplay distance. Check both pins, feet, hands, clothing and contact through movement. |

For a new exercise, change its objective, feed, targets, scoring and progression in the derived controller. The shared scene supplies working setting reps by default. Override `start_drill()` for entry and `save_scorecard()` for drill-specific progress. Keep career checkpoints in the career controller. Verify a new exercise through its menu entry, including a short athlete, an unattended toss, a remapped controller prompt and a loose-ball return during another setter’s turn.

## Competition and progression
Home offers Career, Play, Training Camp with performance stars, Create Player, Settings and Quit. Offline standard matches support 2–6 players per side. Online stays disabled. Select both squads and uniforms from a large generated roster, or edit everyone to either height extreme. The 2v2 career progresses through tournament arcs with dialogue explaining opponents’ philosophies. Opponents specialize in blocking, attacking, defense, serving, all-round play, deceptive jump sets and setter dumps, cut shots, roll shots, line attacks, high hands, and early one- or two-contact returns. Start with a small salary. Tournament winnings buy skills, haircuts, footwear, branded garments and accessories.

## Rules and techniques
Short court confines both teams to the three-meter zones and allows normal attacks, back sets and jump sets. Volleys begins with an underhand serve and requires one touch over the net. Singles plays like tennis. Team volleys rotates entrants through the back and eliminates the responsible player on a floor ball or error, down to uneven sides such as 1v6. Support short-court volleys. Arcade supports 1v1 through 10v10 with slow time, fire, ice, stun, super jumps, teleportation and lightning.

Future camera feature: optional ball-follow in the swing preview to watch the landing and rebound.

Future arcade spike challenges include two power shots:

- Roof the ball. Spike the ball into the opposite court and bounce it high enough to hit the gym ceiling.
- Bounce it back. Spike the ball into the opposite court, bounce it off the gym wall, and have the wall rebound carry it back over the net to the hitter's side without another touch.

All players have individual forearm and hand ratings for each of reception, setting and defense. Dives and lunges use the relevant rating. Height spans 5–7 feet, vertical 10–60 inches. Include wingspan, block, speed, stamina and separate ratings for underhand, standing float, jump float, spin, spin-to-float hybrid, float-to-spin hybrid and sky ball. Hold to prepare, reducing mobility. Release at the contact hitbox. Mouse wheel and controller adjust angles. Timing, force, incoming pace, wetness and skill control the vertical and horizontal error cone, including backward errors. Absorb hard contact with elbow give. High arcs enable sky balls; powerful serves have narrower timing and fast descents.

Support cross, line, high hands and stuff blocks. CPU pairs in 3v3 and triples in 6v6 share one block takeoff instant. Include swing, squat and deep beach blocks and long-approach and squat attacks. Include dolphin, pokey, fist, punch, double pokey, spike, jump set, two-ball pokey, back-bump dump, hand-set dump and back-set dump. Dig with either arm, both arms, hands, center platform, chest, head and pancake. Use distinct reach, contact and recovery animations.

## Presentation and venues
Target realistic, high-detail player models, clothing, officials and stadiums. Indoor, outdoor hard court, grass and beach sand support varied venues and short court. Grass throws dirt from running feet and ball impacts. Add ground-specific sounds, distinct ball and block contact, high-speed wind trails and impact rumble. Momentum modestly improves skill, power and jump. Hands on knees before serve, transition into reception, high-five after rallies and vary team celebrations.

Advance from quiet facilities to public courts with sparse spectators and optional refs, championships with first and second referees, major championships with line judges, large stands, Olympic-scale stadiums and domes. Rain makes contacts slippery; wind affects flight and moves trees and national flags.

Crowds split allegiance, hush before serves, chant, jump, wave, celebrate, argue, fetch food, hold flyers, throw streamers, wear coordinated shirt patterns and display player-name signs and big-head cutouts. Include rhythmic clapping, fans following long sky balls together, and delayed away-section reactions. Announcers react to score swings, tactical tendencies, substitutions where applicable and individual plays. Allow crowd, commentary and presentation effects to be toggled separately.

## Wardrobe
Support forward, backward and sideways strapback, snapback and fitted caps; sunglasses in multiple shapes; hoodies up/down, tees, tanks, shirtless, long sleeves and compression layers; varied shorts lengths, patterns and colors; pants, compression bottoms, bikinis, sand socks, shoes, leg/arm/calf sleeves, sock lengths, gloves, headbands, masks and haircuts. Layer masks, hoods and headbands. Generate coordinated CPU looks, including optional capes, armor and exotic effects.

Each high-school setter takes nine consecutive attempts. Jordan opens, the career athlete goes second, and Micah finishes. Hold A during Jordan's turn to skip his remaining attempts. The handoff fades through black. School players have a saved studio headshot, age, hometown and handedness. Final standings use green, yellow and red in rank order. The setter tryout starts with high sets. RS down or sideways selects medium, and RS up selects high. D-pad up toggles 35% speed. Coach dialogue appears briefly above the speaker. The top score strip pairs circular player portraits with names, made attempts and final placements. During a teammate’s turn the score strip stays visible. Carts block player movement, including while being pushed. After scoring, the crew collects reachable balls and joins the setters and coach for a center-court huddle.

Desktop uses Forward+ with high-resolution shadows. Practice target cords are anchored at the rim and transmit localized impact through neighboring knots. Clothing responds to changes in movement, and the seated team tracks the current ball. Test the full scored rotation as well as off-center rim impacts when changing simulation or presentation.

Leave room for the last player to enter the huddle, then close the circle together. Use the nearer shoulder or back panel when teammates differ in height. Frame the debrief from player height. Huddle contact comes from behind each teammate: high arms wrap the shoulders, low arms reach around the waistband. Inspect both from the rear. The indoor tryout uses 1.35� linear render scale and 8� MSAA.

Huddle hands open at contact. High palms rest face down on the neighboring shoulder; low palms face into the rear waistband. Training jerseys accumulate localized dampness from distance covered and stamina spent, then dry gradually at rest. Rebuild the shorts and reference skin weights with tools/bake_practice_garments.gd, then fit the sourced tee using tools/fit_training_tee.gd. The player jersey supplies the huddle contact surface. Check the cuff, shoulder, and printed number with arms both raised and lowered.

The four practice carts each have four rolling casters. Balls are stored in cart-local slots and follow the frame when it turns. A loose ball that settles inside an open cart joins its inventory.

## Game notes

When a request begins with “game notes,” record the idea here for future consideration. Implementation waits for a separate request.

- **Uneven matchups.** Let each side choose its own team size. Examples include 2v3, 2v4, and 1v6. One possible variation has one side playing one-contact volleys while the other plays regular volleyball.

- **Licensed teams and athletes.** Explore partnerships with leagues, universities and schools for participating teams and athlete likenesses, rosters, statistics, ratings and rankings. Track which teams, athletes and seasons each agreement covers.
- **Conditioning after a poor performance.** A future shuttle-run drill could use timed button presses to race teammates. One possible consequence for finishing last is reduced playing time.

- **Unlockable block reactions.** A stuff block (“pack”) could trigger an exaggerated, optional reaction from the blocked attacker, such as snapping their head back in surprise. Special reaction animations could be earned through play.
- **Learn from opponents.** Face a specialist and see their signature skill in a match. Beating them could unlock a chance to train with them afterward and learn the skill they used.
- **Linked beach and indoor careers.** Carry learned skills between both campaigns. Beach opponents could teach pokeys, dolphins, and cutties, while indoor specialists teach their own exclusive skills. A player could bring a beach technique back indoors or return to the beach with something learned in the gym.
  The progression goal is one athlete with a growing repertoire. Each form of volleyball should offer that athlete a reason to play it.

Indoor practice counts descending rim rebounds that enter the called basket. Early release has 65 ms of additional grace while the ball reaches the hands. Timing percentages are measured against the setter's timing window. Collectors turn and accelerate into new paths, and huddle neighbors can reopen a gap for a late arrival. Gameplay pause opens on Resume, with Options, Restart and Quit below.

## Future setter moves

Setters should be able to tip-set to a teammate with either hand, or send the second ball over the net with a left- or right-handed dump. A jumping setter can choose a soft tip dump or a hard, spike-like attack dump. A full spike approach should also support either a set to a teammate or a hit over the net.

The movement system needs to distinguish a straight-up jump from an approach jump while preserving the choice of what to do with the ball in the air. How players signal the jump type, hand and contact is an open control-design question.

Two designated collectors retrieve loose balls after the coach finishes the tryout throws. The active setter can tap a loose ball away from their feet. In the developer console, vison and visoff show and hide current commands over the team. A cut career athlete must restart the tryout. The school captain wears a bar below the number on both jersey panels.

## Future referee challenges

Occasionally a referee should make an incorrect call. Teams should be able to challenge the call and have the decision upheld or overturned after review. The challenge system is a future feature. The review should use the rally replay, including the sequence of ball, block and floor contacts. Challenge limits, eligible calls and controls are open design decisions.

The tilde console lists career and diagnostic commands. In indoor practice, replay pauses the drill and exposes recent poses with a scrubber and independent inspection camera. The gym court surface and player floor clearance follow the raised maple deck.

The practice coach wears a whistle and signals the start and finish before handling another ball. Rival setters aim for two to four makes per nine attempts, including skipped attempts.

Feeding resumes at the active setter and station. Coaches can feed from either side or the handle of a cart. A missed jump-set toss continues to forehead height. The whistle cue is shared for future officials. Huddles use idle legs and can clear movable carts and target stands. Practice footwear includes low, mid and high collars, varied upper panels, sock colors and heights, and full or three-quarter tights.

Indoor hand sets preserve the physical button-release time while a prepared setter waits for the descending ball to enter reach. A 65 ms on-time band and a short hand cushion accommodate releases around visible contact. Jump technique is graded separately.

Training Camp / Setting / Set to Target runs on the same indoor practice controller as the career tryout. Solo practice recycles issued balls after each result and repeats standing and jump sets without roster rotation. Play and Training Camp use the indoor gym and shared athlete kit for match-based drills.

Gameplay prompts default to mapped Xbox glyphs regardless of connected devices or recent key presses. Keyboard prompt text requires an explicit opt-in in Controls.

Solo Set to Target starts with the CPU demonstrating on the active athlete. Xbox View switches to player control and back. When ownership changes during a toss, the coach feeds a fresh ball for that setter.

Keep Xbox prompt textures resident across redraws so CPU and player prompts render the same mapped button.

CPU setters choose a takeoff lead and release offset per toss. In solo camp a centered release aims at the target center, while early and late releases change set depth.

Solo setting camp samples tosses across a one-metre disk around the setting spot. The player moves with the left stick and the CPU shuffles under the feed. Lateral placement is independent of toss height.

CPU setters delay squaring to the target until the closing part of the toss. Both front and back sets use a slower turn, continuing into the practice follow-through.

During setting practice LT tracks the live incoming ball. Holding a target button with LT turns the setter toward the appropriate set heading. CPU setters simulate that same sequence. Turning away increases placement spread while leaving over-the-shoulder sets available.

Grounded pivots alternate support feet, lift the swinging shoe, and settle into idle. Airborne yaw follows the jump pose. Front and middle sets budget enough turning time to square by release; back sets begin slightly later.

Solo CPU camp can be used to inspect reception: the setter stays grounded, moves the forehead under the incoming ball, faces the called set heading and holds the two-handed setting shape for 1.5 seconds before the next toss. View restores playable sets.

The shared natural ready stance raises the torso by 20 degrees while retaining its knee bend and foot placement.
Grounded turns use longer alternating steps and keep the feet planted through small heading adjustments.
Setters raise their hands during the hold and finish shaping them as the toss descends. Offline match setup remembers the selected ball brand and displays its panel colors on court.
Grounded square-ups use a short right plant and a longer left swing. The hips finish turning with the left foot.
In Setting Camp the CPU runs toward higher backcourt tosses and finishes each approach with one right-left plant. The hands rise within roughly a meter of the forehead. Pause Options can open Animation Frames on the recorded setter rep; saved copies retain the selected frame.
The setter pivots on the ball of the right foot as the hips square up. The left foot lands to give a stance slightly wider than the athlete's neutral ready stance.
Setting Camp targets position four on every rep, alternating standing and jump sets. The coach can feed both sidelines and deep zone six, within sprint range on clear floor.
Camp jump reps alternate vertical and moving takeoffs. Moving jump sets carry the approach velocity to the projected contact; sprinting is optional.
On a set the ball stays in the hands through a short yield to the forehead and a full arm extension. Flight starts at the fingertips.
Approach pace selects walk, compact jog, run, or sprint clips. Setting hands rise earlier with spread fingers and close thumbs; the outward push is quicker than the cushion. Strength governs horizontal set range from 5 to 13 meters.
On the lift to receive the set, elbows travel near the torso and stay near a right angle while straight wrists pass the face. The elbows open on the outward send.
The reference setting lift leads with open hands past the chest and face while the elbows trail underneath. The receiving pocket sits forward of the forehead, yields back, and drives up and forward.
Setting Camp exposes Edit set frames directly from Pause and opens on the recorded contact. The 105 ms cushion leads into a 40 ms outward push.
In Animation Frames, holding a rotation arrow repeats at five degrees per increment; single clicks adjust one tenth of a degree.
Setters keep a fixed open-hand pose, use the saved elbow lift during preparation and intercept the ball in front of the forehead. Standing setters load the knees and extend on the push. Saving a frame copy returns to the originating drill scene.
Setting fingers stay broadly fanned on the lift and descent. Wrists stay back through the 50 ms cushion and 25 ms push, then roll forward only in free flight.
Each athlete's current stamina percentage scales skill effectiveness linearly. Stamina spending and recovery use the same athlete-owned meter; endurance changes the cost of exertion.
Forward sets hold the wrists flat for 120 ms after easing out of the loaded grip before the wrists turn toward the target.
Camp pause sliders tune the active setter for this session and show current medium/high set ranges. Fingers open on the gather from the relaxed running gait.
RB cycles set heights. The incoming toss shows its projected flight and floor landing ring. Holding the set input begins opening the hands.
On descending tosses an active setter can lean and reach to either side. Contact follows the swept ball and the actual palm pocket, including on off-center releases.

Setting camp feeds cluster around the home between zones 2 and 3. Inside the attack line the setter can also call middle. The coach prepares the next toss during flight. Planted sets load the knees according to distance and available strength. Airborne contact has 77% of planted horizontal range.
Consecutive setting-camp tosses differ by at least one meter on each court axis. The practice HUD separates player identity, stamina, action expenditure, vertical jump charge and sport timing.
Incoming tosses use a small dark landing dot with a light edge. The outgoing arc is opt-in with left-stick click. Jump charge holds through flight and for 0.85 seconds after landing, then fades over 0.30 seconds and the setting timing arc appears during preparation and release in both CPU and player control.
Exertion also accrues slow-recovering fatigue. Endurance scales recovery between reps. The stamina bar communicates skill deterioration without a separate skill rating. Restarting the drill restores a fresh athlete.
Hold LB with a setting target to time an automatic jump to the descending toss. LT controls alignment independently. The timing arc uses the same on-time tolerance as release feedback and retains the original grade for buffered input.
For a playable off-center toss, the setter leans through the spine and extends both arms as the ball descends. Hand contact still determines the set.
The set cursor travels at one speed from the in-flight press through release. The green timing band reflects the contact tolerance at that speed. Perfect sets have a shorter outward push.
A setter already inside the coach or cart clearance margin can receive a toss along a route that exits the margin without moving closer.
Setting camp supports B back sets in addition to outside and eligible middle sets. Gray falls outside playable contact, orange is early, green is on time, and red is late. Playable early or late releases reduce placement accuracy.
Energy capacity is 25 plus five points per Stamina rating. Endurance sets rested recovery at 1-10 energy per second. Willpower allows one point of negative balance per rating point. Debt recovers at half rate and permits reduced skill until the reserve is depleted.
Back sets extend the arms together above the shoulders, following the spine as the torso arches farther for longer sets.
Back-set contact cups the ball with upward palms. The wrists extend into a palms-up finish and the shared follow-through tracks the outgoing arc tangent within overhead shoulder reach.
During back-set extension the chest, neck and chin lift together toward the outgoing set, easing down through recovery.
Back-set wrists keep the receive grip through ball departure and extend over the next 95 ms. Chest and chin arch progressively from the catch through follow-through over 180 ms.
The normal set pocket sits 7.5 cm forward of the head joint. Both grounded footwork and jump interception use this same forehead offset.
LT movement uses a continuous directional shuffle cycle with low alternating foot lifts, blended acceleration and a decelerating plant into contact. Stationary turn steps yield while shuffling.
Accepted manual set releases carry the descending toss into the moving palm pocket at the scheduled contact time. The incoming path still checks court and equipment collisions first.
Airborne setters transfer 22 percent of horizontal takeoff/carry velocity at contact to the set. Hand setting compensates for drift within available arm strength. Moving away from the target reduces maximum reach even for experts.
All three timing bands appear on target press, including before the toss and while moving into range. Physical reach is evaluated separately at release.
In player-controlled Setting Camp, hold the right stick to aim along the net between the two pins, then return it to center to time a bump set against the visible release meter. The authored forearm reception platform clip supplies preparation, contact and follow-through. RB selects height. Face buttons supersede the bump selection.
Andre Foreman's Volleyball uses a rotating home ball and keeps its original save directory. The animation menu opens the shared Setting Camp. Bump sets use directional reception reaches and low-save animations. Player equipment and shorts designs are selected in the creator and preserved in the profile.

Forearm sets preserve the approach shuffle, use reception footwork and low saves to intercept the toss, then carry the planted reach into a directional follow-through. Forearm placement varies with effective skill and fatigue.
Grounded forearm reception uses authored forward and lateral plant presets. Target steering affects the spine and arms. The frame editor preserves recorded body motion by default.
In Setting Camp, clicking the right stick while watching the CPU switches between overhead and forearm sets. View returns control to the player.
Back bump sets open the hips toward the hitting pin and carry the joined forearms upward through release. The planted feet anchor the turn.
On close bump sets, the setter steps into the incoming ball, plants before contact, and lets the elbows bend through the swing, especially on back bumps.
Grounded bump sets load the knees before contact and extend through the arm swing. Longer sets use a deeper load.
On grounded bump sets, the torso hinges forward with the knee bend and starts rising before contact. The back bump carries that rise into the overhead follow-through.
Grounded forearm sets use both the intended distance and arc height to scale the knee load and platform swing. The hands retain the reception grip through follow-through.
Grounded bump setters track the descending ball through a range of forearm heights. A low contact adds torso lean and wrist tilt. The back-bump follow-through runs at 75 percent speed.
The bump timing arc dedicates most of its width to playable releases. Follow-through starts from the actual forearm contact pose and uses a single directional swing.
Setting Camp Sliders allow natural, early, on-time and late CPU releases. An accepted early forearm release prepares the high intercept before the ball reaches the usual waist-height contact.
While watching the CPU in Setting Camp, left-stick click cycles release timing and right-stick click switches between hand and bump sets. CPU targets are drawn automatically from the eligible pins and middle.
During forearm preparation the platform aims at the anticipated intercept. A high descending toss does not pull the arms up and back down before the strike.
Player-controlled bump sets allow up to 23 cm of collision-checked assistance toward a nearby ball. A buffered release uses the last verified descending forearm overlap so a fast ball cannot invalidate good contact before the input is processed.
Missed sets land and roll for half a second before the next attempt. Switching target buttons during preparation starts a fresh meter, with a brief allowance for the thumb to move between buttons.
Players can change between any available set targets during preparation. Near contact, the reach check also accounts for the ball and head moving past each other within torso-lean range.
Light analog input eases into walking, with cadence matched to movement speed. The walk cycle owns its footfalls through slow turns and continues across player-controlled camp feeds.
Training Camp > Attacking > Approach and Spike uses the Setting Camp coach feed and CPU hand-set mechanics. The CPU hitter waits for the set, takes a three-step approach with a backswing, and jumps forward to spike. View toggles player control. Left stick moves, LB starts the approach, and X times the swing.

## Next session agenda

- Attack variations: cut shots, roll shots, tips, pokies, fists and dolphins. Check left- and right-handed hitters throughout.
- Setter dumps, faking an attack approach into a set, and two balls.
- Blocking, defense, digging and serving.
- Celebrations, high-fives, crowd animation and spectators in the stands.
- Review the out-of-bounds hit and how the net reacts at gameplay camera distance.

The attacking demo refreshes its feed setter's stamina each rep and the hitter shuffles into position. Shared net impacts compress the cloth and tape, then recoil around the impact point.
Every playable drill carries the active athletes' stamina and jump indicators, including CPU demonstrations. New drills inherit these readouts alongside shared practice mechanics.

Shared approach and setting jumps scale vertical reach with stamina at the start of the jump. Attack practice exposes the feed set's arc in Sliders.

In attacker control, hold X for court left, Y for middle, or B for court right from either pin. The hitter tracks the set and leads toward its intercept with the left foot. Release at contact for power. Early timing biases depth long and late timing drives the shot down.

Attacks allow 30 cm from palm to ball center during the strike window. A small upper-body reach assists close swings and eases away through the follow-through.

Player-controlled ground movement uses shared LT lock-on and RT sprint bindings. LT keeps the athlete facing the ball as the stick steers a grounded shuffle. LT and RT together accelerate that shuffle and consume stamina.

Once an automatic attack approach starts, the face button selects shot width and the left stick adjusts depth and trims width by up to one metre either side of the lane on the opponent's court until release. Every manual shot starts 4.5 metres beyond the net. Effective Spike placement controls target speed and scatter radius. Release timing can push the shot beyond the indicated area.

The attack landing marker previews the aimed ball flight: green in, yellow tape-over, red net, orange out. Depth extends ten feet beyond the baseline.

Short attack plants use the authored front arm-lift curve. The attack release meter grades releases from 85 ms early through 270 ms late as Perfect; release labels are Early, Perfect and Late.

Shared cloth and tape rebounds retain 20% of incoming speed at release. Spike launch pace depends on forward approach momentum and fatigue-adjusted jump height, including short plants at the net.

Attack timing also considers approach arrival. A playable button release can grade Late when the plant starts behind schedule or the palm first reaches the descending set late. Net contact alone does not determine the timing grade.

Attackers use their full stamina-adjusted vertical. Farther sets speed up the run-up and plant in proportion to effective Speed. The hitter must cover the ground before starting the plant.

Spike feedback centers its timing bands 305 ms earlier, checks release against palm arrival and plant timing, and confirms Perfect only after clean net clearance. Grading never redirects the launch. All spikes can rebound from the floor.

## Future court and multiball modes

- Nine-man volleyball with its own rules and court dimensions.
- Larger configurable courts, including 10 m and 15 m size options. Exact layouts are open.
- Multiple live balls at once. In Swedish two-ball, one player on each side serves simultaneously across the net to start two rallies. Scoring and restart rules are open.

## Future player chemistry

Track chemistry between teammates. Higher setter-hitter chemistry improves anticipation of set location and tempo so the hitter more consistently times the approach and takeoff.

## Future training camp drills

- Blocking test: run single, double, and triple blocks against live sets to each front-row position.

- Touch Ten
- Butterfly defense
- Drills off the box
- Transition drills
- Hitting lines
- Bounce-offs

Practice observation notes can capture each drill's starting positions, ball feeds, player rotations, and reset or scoring rules.

The practice replay legend uses Xbox glyphs for sticks, bumpers, triggers, face buttons, D-pad and View. Keyboard hints follow the Controls preference.

Blocking practice fields four available hitters. Each feed independently chooses a left pin, 51, pipe or right pin attack. During recovery, each hitter advances the grounded animation before applying shuffle footwork. The loading-screen rotation includes 4,980 historical facts derived from the Olympic athlete-events dataset through 2016 (https://github.com/rgriff23/Olympic_history).

The replay arm overlay shows all six blocking arms on every frame. Blue shows the recorded arm pose and green shows capsules eligible for block contact.

In blocking practice, all four attackers run their own approach lanes as the pass reaches Bell. On set release, the three unselected hitters brake into position-specific cover, then recover for the next feed.

The CPU middle can commit to a nearby quick runner accelerating toward Bell before release. This read uses the visible approach and can leave the middle airborne against a pipe or pin set. Each rep logs the released route and endpoint.

The pipe covers deep in six, the far pin shades inward from its own lane, and nearby front-row hitters cover shorter. The middle runs a 50 or 30 at tempo zero every feed, including decoy jumps. The pipe uses tempo 0 or 1. Pins use 0, 1 and 2. Tempo 3 is reserved for out-of-system play.

Random-height blocking feeds assign a separate tempo to every route. Each runner times the approach to that call. Uncommitted blockers observe the released ball before estimating its lateral destination.

## Future blocker scouting

Track set distribution by opponent rotation, eligible hitter and tempo. A CPU middle can combine those tendencies with a read of the live approach to shade a lane or take a first step before release. A small sample should carry little weight, and a setter running against tendency can wrong-foot the block.

All blocking-drill hitters transition from running into the shared attack swing. Blocker bumper inputs do not select the CPU shot type.

Random height defaults on for blocking. The controlled blocker can move from coach release. Replay Slow-mo cycles half, quarter, eighth and sixteenth speed.

After the dead-ball reset, the ready whistle gives 509 full lateral and depth control until the rally ends. CPU close and peel assignments only steer computer-controlled blockers.

The attack aim selector offers random court placement, targeting the block and avoiding the block. Near the tape, LT squares the blocker to the net. Holding A prepares a swing block and the body completes the turn through takeoff while lateral lean and individual arm reaches remain available.
Attacking and blocking practice report which blocker and limb touched a spike. The middle can anticipate the quick after repeated scores or through a tactical order.
Training Camp Serving includes Serve and Receive, a baseline timing drill with three passers and reversible spin/float hybrid selection.

## Future curveball serve

Reserve the full-strength sidespin trajectory (1.15 m of lateral bend at mid-flight) for a future curveball serve. Ordinary D-pad sidespin uses 30% of that bend.

## Future setter perk

An exceptional setter can deliver faster offensive sets across the net width. Ordinary setters in the serving rally currently cap horizontal set speed at 23.4 km/h.

## Future spin serve toss options

For a spin serve, the server can toss with the left hand, the right hand, or both hands together.

## Reception backspin

Across drills and matches, a received ball should generally leave the receiver with backspin.

CPU receivers signal a leave by spreading both arms as the ball approaches.
The shared indoor gym has five additional meters of runoff on each side and behind each baseline. The stands and end-wall equipment move with the walls.
Reception Studio uses the same seated teammates and four-row sideline bleachers as indoor practice.

## Future feature - skill progression through play

Players level individual volleyball skills by using them. Simulated drills award XP to the skills practiced. Completing the same drill manually awards additional skill XP. This replaces allocating stat points for skill growth. XP rates and the manual bonus are to be tuned.
