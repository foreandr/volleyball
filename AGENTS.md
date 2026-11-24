# Volleyball

- Read the indoor practice baseline in GAME_DESIGN.md before changing a drill. Build new indoor drills on scenes/indoor_practice.tscn and its controller. Update the baseline in the same commit when shared behavior changes.

- Share applicable drill behavior across all drills through common code. Fix shared camera, replay, editing, setup persistence, and diagnostics at their source. Keep each drill's saved setup independent.

- Godot 4.6 / GDScript, Compatibility renderer. Keep character assets and saves independent from FightLab and Alien Optimization.
- Implement the requested change, run a focused check, commit, and launch a fresh maximized game window at the exact scene and state most recently changed. Verify the playable handoff before sending the GitHub commit. Preserve the real career save when jumping to a review checkpoint. Close only previous Volleyball game windows. Defer broad tests and documentation until requested.
- Keep the UI minimal. No unsolicited instructions, explanatory copy, view buttons or metadata.
- Use the user-supplied Goalkeeper Idle animation as the default ready stance.
- For every authored animation, review the entire motion from front and side, including transitions, balance, contacts and recovery. Judge whether a professional in that sport would recognize believable technique. Fix problems before calling the animation finished; report limitations honestly.
- Reuse tools/animation_author.gd and per-animation recipes for body-part targets and timing. Convert model-space targets to bone-parent coordinates. Keep feet planted when the action requires it. Never copy an entire authoring implementation for a new animation.
- Keep new animation lists empty until an actual authored clip exists for that exact move type.
- For pass iterations, edit JSON recipes while the preview runs; it reloads within 0.4 seconds without resetting camera, feed or playback. Do not restart or rebake unrelated clips for pose tweaks. Compact variants can inherit an existing recipe with `extends`, shared phase values in `defaults`, and overrides in `poses` (`ready`, `prepare`, `approach`, `contact`, `follow`, `recover`, `end`). An array of recipes in one JSON file creates a batch. `tools/build_pass_batch.gd -- <ids...> --out=res://work/pass-batch` bakes selected recipes when a saved resource is needed. Use the existing focused check and front/side review only for changed motions; no full editor import or repeated screenshot batches for routine tweaks.
- Keep `user://preview_setup.cfg` intact during iterations. It restores placement, camera and ball settings. Relaunch through `work/launch_preview.gd` when available; do not use old QA launchers that overwrite the user's setup. Checks that save preview settings must redirect `StorySession.preview_path` into `work/`.

- Push each project update to GitHub and report its verified commit SHA to the user.
