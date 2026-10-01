extends Node

# Autoload "Sfx": Silly mode's sounds (owner, 2026-10-02: goofy, goat-simulator
# feel). The project has no audio files, so the sounds are synthesized here
# once at start - sine sweeps, a little vibrato, a pinch of noise - into
# in-memory AudioStreamWAVs: nothing to import, nothing to license. A small
# pool of plain (non-positional) players keeps the cost flat. Serious mode is
# silent for now; play() does nothing there.
#   Sfx.play("boing")            Sfx.play("splat", 0.5)   # 0..1 = how hard
# Headless can't judge sound: the owner listens. If these sound cheap, the
# fallback is a CC0 pack (ask before copying any files in).

const RATE := 22050
const POOL := 6
const VOLUME_DB := -8.0

## name -> [start Hz, end Hz, seconds, vibrato Hz, vibrato depth (0-1), noise (0-1), wave ("sine"/"square"), decay]
const SOUNDS := {
	"boing": [170.0, 520.0, 0.38, 16.0, 0.12, 0.0, "sine", 2.5],     # jump
	"splat": [130.0, 55.0, 0.24, 0.0, 0.0, 0.45, "sine", 9.0],       # landing
	"bonk": [340.0, 250.0, 0.14, 0.0, 0.0, 0.08, "sine", 22.0],      # wall bump, smasher hit
	"squeak": [900.0, 1500.0, 0.11, 0.0, 0.0, 0.0, "sine", 12.0],    # poke
	"honk": [230.0, 205.0, 0.3, 6.0, 0.03, 0.0, "square", 4.0],      # something breaks
	"pop": [620.0, 1250.0, 0.08, 0.0, 0.0, 0.0, "sine", 18.0],       # pickup
	"wahwah": [420.0, 140.0, 0.5, 7.0, 0.18, 0.0, "square", 3.0],    # hit in a fight, cursed
}

var streams := {}            # name -> AudioStreamWAV (tests read it)
var _players: Array[AudioStreamPlayer] = []
var _next := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for id in SOUNDS:
		streams[id] = _synth(SOUNDS[id])
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.volume_db = VOLUME_DB
		add_child(p)
		_players.append(p)

## Plays a sound in Silly mode. `strength` 0..1 makes it louder and lower.
func play(id: String, strength: float = 1.0) -> void:
	if not Game.silly() or not streams.has(id):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = streams[id]
	p.volume_db = VOLUME_DB + lerpf(-10.0, 0.0, clampf(strength, 0.0, 1.0))
	p.pitch_scale = randf_range(0.92, 1.08) * lerpf(1.15, 0.9, clampf(strength, 0.0, 1.0))
	p.play()

func _synth(spec: Array) -> AudioStreamWAV:
	var f0: float = spec[0]
	var f1: float = spec[1]
	var seconds: float = spec[2]
	var vib_hz: float = spec[3]
	var vib_depth: float = spec[4]
	var noise: float = spec[5]
	var square: bool = spec[6] == "square"
	var decay: float = spec[7]
	var count := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(spec)
	for i in count:
		var t := float(i) / RATE
		var k := t / seconds
		var freq := lerpf(f0, f1, k * k * (3.0 - 2.0 * k)) * (1.0 + vib_depth * sin(TAU * vib_hz * t))
		phase += TAU * freq / RATE
		var tone := sin(phase)
		if square:          # soft square: rounder than a hard one
			tone = clampf(tone * 3.0, -1.0, 1.0) * 0.7
		var sample := tone * (1.0 - noise) + rng.randf_range(-1.0, 1.0) * noise
		var envelope := minf(t / 0.005, 1.0) * exp(-decay * t) * (1.0 - k * k)
		data.encode_s16(i * 2, int(clampf(sample * envelope, -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
