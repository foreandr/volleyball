# Volleyball feature record

The following describes the intended full game. A menu route, stored rating or prototype does not establish that a feature is finished.

## Indoor practice baseline

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

Occasionally a referee should make an incorrect call. Teams should be able to challenge the call and have the decision upheld or overturned after review. Challenge limits, eligible calls and controls are open design decisions.

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
