# Volleyball

- Godot 4.6 / GDScript, Compatibility renderer. Keep character assets and saves independent from FightLab and Alien Optimization.
- Implement the requested change, run a focused check, commit, and launch a fresh maximized game window. Close only previous Volleyball game windows. Defer broad tests and documentation until requested.
- Keep the UI minimal. No unsolicited instructions, explanatory copy, view buttons or metadata.
- Use the user-supplied Goalkeeper Idle animation as the default ready stance.
- For every authored animation, review the entire motion from front and side, including transitions, balance, contacts and recovery. Judge whether a professional in that sport would recognize believable technique. Fix problems before calling the animation finished; report limitations honestly.
- Reuse tools/animation_author.gd and per-animation recipes for body-part targets and timing. Convert model-space targets to bone-parent coordinates. Keep feet planted when the action requires it. Never copy an entire authoring implementation for a new animation.
- Keep new animation lists empty until an actual authored clip exists for that exact move type.
