extends RefCounted
## Tiny synthesized sound cues (no audio files): pickup chime, denied buzz,
## tool thud and craft sparkle. Streams are generated once and cached.
##
## Example: `Sfx.play(self, "pickup")` from any node inside the tree.

const RATE := 22050

static var _cache := {}


## Builds (once) the AudioStreamWAV for a cue name.
static func stream(cue: String) -> AudioStreamWAV:
	if _cache.has(cue):
		return _cache[cue]
	var notes: Array = []  # [freq_start, freq_end, seconds, volume, wave]
	match cue:
		"pickup":
			notes = [[660.0, 880.0, 0.07, 0.35, "sine"], [990.0, 1320.0, 0.09, 0.3, "sine"]]
		"deny":
			notes = [[180.0, 140.0, 0.16, 0.3, "square"]]
		"thud":
			notes = [[140.0, 70.0, 0.1, 0.5, "sine"]]
		"craft":
			notes = [[523.0, 523.0, 0.06, 0.3, "sine"], [659.0, 659.0, 0.06, 0.3, "sine"], [784.0, 1046.0, 0.14, 0.3, "sine"]]
		_:
			notes = [[440.0, 440.0, 0.05, 0.2, "sine"]]
	var data := PackedByteArray()
	var phase := 0.0
	for n in notes:
		var count := int(float(n[2]) * RATE)
		for i in range(count):
			var t := float(i) / float(count)
			var f: float = lerpf(n[0], n[1], t)
			phase += TAU * f / RATE
			var env := minf(1.0, t * 12.0) * (1.0 - t) * (1.0 - t)
			var v := sin(phase) if n[4] == "sine" else (1.0 if sin(phase) > 0.0 else -1.0) * 0.5
			var s := int(clampf(v * env * float(n[3]), -1.0, 1.0) * 32767.0)
			data.append(s & 0xFF)
			data.append((s >> 8) & 0xFF)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	_cache[cue] = w
	return w


## Plays a cue on a throwaway player attached to `host` (frees itself).
static func play(host: Node, cue: String, volume_db := -6.0) -> void:
	if host == null or not host.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream(cue)
	p.volume_db = volume_db
	host.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
