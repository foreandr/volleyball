# Position 4 Spike Demo

Recovered November 12, 2026 standalone demo with a numbered navy uniform, tiered court stands, and 39 captured spike frames. This is a separate animation demo; the main volleyball game remains at the repository root.

Open this folder's `project.godot` in Godot 4.6 and run it. The demo includes replay, timeline scrubbing, three camera angles, and slow motion. The player is a simplified model, and ball flight is scripted to meet the captured hand contact.

`position_4_spike.bvh` contains the captured animation; `spike_frames.json` supplies the demo's joint positions.

Focused check:

```powershell
godot --headless --path demos/position_4_spike -- --check
```
