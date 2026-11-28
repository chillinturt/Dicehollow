extends Node
## Sound effects. Every sound is synthesized in code the first time it's played (no audio files),
## then cached. Volume and mute are saved to user://settings.cfg.
##
##   Sfx.play("sword")        # plays a named sound on the SFX bus
##   Sfx.set_volume(0.6)      # 0..1
##   Sfx.set_muted(true)

signal settings_changed

const RATE := 22050
const BUS := "SFX"
const SETTINGS := "user://settings.cfg"
const POOL_SIZE := 14
## Damage type -> sound name. Weapon damage types fall back to "hit" sounds.
const DAMAGE_SFX := {"fire": "fire", "cold": "cold", "lightning": "lightning", "thunder": "thunder", "acid": "acid",
	"poison": "poison", "necrotic": "necrotic", "radiant": "radiant", "psychic": "psychic", "force": "force"}
## How loud each sound plays relative to the rest (every sound is normalised to the same peak first).
## Interface ticks and footsteps sit well under the combat sounds; big moments sit on top.
const LEVEL := {"click": 0.3, "select": 0.38, "cancel": 0.34, "error": 0.45, "step": 0.38, "dice": 0.5,
	"condition": 0.55, "miss": 0.65, "turn": 0.7, "hit": 0.85, "danger": 0.8,
	"combat_start": 0.9, "victory": 0.85, "defeat": 0.85, "levelup": 0.8, "nat20": 0.8}
const DEFAULT_LEVEL := 0.9

var volume := 0.7
var muted := false

var _cache := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played := {}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	# A limiter keeps a pile of sounds at once (a fireball over six goblins) from clipping.
	var bi := AudioServer.get_bus_index(BUS)
	if AudioServer.get_bus_effect_count(bi) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		lim.pre_gain_db = 0.0
		AudioServer.add_bus_effect(bi, lim)
	for i in POOL_SIZE:
		var p = AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_players.append(p)
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		volume = clampf(float(cfg.get_value("audio", "sfx_volume", volume)), 0.0, 1.0)
		muted = bool(cfg.get_value("audio", "sfx_muted", muted))
	_apply()

# ================================================================ public API

func play(sound_name: String, pitch_jitter := 0.06) -> void:
	if sound_name == "" or muted or volume <= 0.0:
		return
	# Don't stack the same sound many times in one instant (e.g. a fireball hitting six goblins).
	var now = Time.get_ticks_msec()
	if now - int(_last_played.get(sound_name, -1000)) < 45:
		return
	_last_played[sound_name] = now
	var stream = _stream(sound_name)
	if stream == null:
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	p.volume_db = linear_to_db(float(LEVEL.get(sound_name, DEFAULT_LEVEL)))
	p.play()

func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply()
	_save()

func set_muted(m: bool) -> void:
	muted = m
	_apply()
	_save()

func toggle_muted() -> void:
	set_muted(not muted)

## The sound for a damage type ("fire" -> "fire", "slashing" -> "").
func for_damage(dtype: String) -> String:
	return DAMAGE_SFX.get(dtype, "")

func names() -> Array:
	return ["sword", "blunt", "punch", "claw", "bite", "bow", "crossbow", "throw",
		"fire", "cold", "lightning", "thunder", "acid", "poison", "necrotic", "radiant", "psychic", "force",
		"cast", "heal", "buff", "rage", "teleport", "hit", "crit", "miss", "down", "death", "nat20",
		"condition", "turn", "step", "click", "dice", "select", "cancel", "error", "danger",
		"combat_start", "victory", "defeat", "levelup",
		"smash", "pickup", "chest", "potion", "glass", "unlock"]

# ================================================================ internals

func _apply() -> void:
	var idx = AudioServer.get_bus_index(BUS)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, muted or volume <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volume, 0.0001)))
	settings_changed.emit()

func _save() -> void:
	var cfg = ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "sfx_volume", volume)
	cfg.set_value("audio", "sfx_muted", muted)
	cfg.save(SETTINGS)

func _stream(sound_name: String) -> AudioStreamWAV:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var method = "_s_" + sound_name
	if not has_method(method):
		push_warning("Sfx: unknown sound '%s'" % sound_name)
		_cache[sound_name] = null
		return null
	var buf: PackedFloat32Array = call(method)
	var stream = _to_wav(buf)
	_cache[sound_name] = stream
	return stream

func _to_wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	# Normalise to a consistent peak so every sound sits at a similar loudness.
	var peak = 0.0001
	for v in buf:
		peak = maxf(peak, absf(v))
	var gain = 0.8 / peak
	var bytes = PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		var s = int(clampf(buf[i] * gain, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, s)
	var w = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w

# ---------------------------------------------------------------- synthesis helpers

func _buf(seconds: float) -> PackedFloat32Array:
	var b = PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b

## Adds b into a starting at `at` seconds, scaled by `gain`.
func _mix(a: PackedFloat32Array, b: PackedFloat32Array, at := 0.0, gain := 1.0) -> PackedFloat32Array:
	var off = int(at * RATE)
	if off + b.size() > a.size():
		a.resize(off + b.size())
	for i in b.size():
		a[off + i] += b[i] * gain
	return a

## Exponential decay envelope with a short attack.
func _env(t: float, attack: float, decay: float) -> float:
	if t < attack:
		return t / maxf(attack, 0.0001)
	return exp(-(t - attack) / maxf(decay, 0.0001))

## Tone whose frequency glides from f0 to f1. wave: "sine", "saw", "square", "tri".
func _tone(seconds: float, f0: float, f1: float, attack: float, decay: float, wave := "sine", vibrato := 0.0, vib_rate := 6.0) -> PackedFloat32Array:
	var b = _buf(seconds)
	var phase = 0.0
	var n = b.size()
	for i in n:
		var t = float(i) / RATE
		var k = float(i) / maxf(n - 1, 1)
		var f = lerpf(f0, f1, k) * (1.0 + vibrato * sin(TAU * vib_rate * t))
		phase = fmod(phase + f / RATE, 1.0)
		var v: float
		match wave:
			"saw": v = 2.0 * phase - 1.0
			"square": v = 1.0 if phase < 0.5 else -1.0
			"tri": v = 4.0 * absf(phase - 0.5) - 1.0
			_: v = sin(TAU * phase)
		b[i] = v * _env(t, attack, decay)
	return b

## Noise through a one-pole low-pass whose cutoff glides c0 -> c1 (Hz). hp > 0 also removes lows.
func _noise(seconds: float, c0: float, c1: float, attack: float, decay: float, hp := 0.0) -> PackedFloat32Array:
	var b = _buf(seconds)
	var lp = 0.0
	var lp2 = 0.0
	var n = b.size()
	for i in n:
		var t = float(i) / RATE
		var k = float(i) / maxf(n - 1, 1)
		var cut = lerpf(c0, c1, k)
		var a = 1.0 - exp(-TAU * cut / RATE)
		lp += a * (_rng.randf_range(-1.0, 1.0) - lp)
		var v = lp
		if hp > 0.0:
			var ah = 1.0 - exp(-TAU * hp / RATE)
			lp2 += ah * (lp - lp2)
			v = lp - lp2
		b[i] = v * _env(t, attack, decay)
	return b

## Struck-metal ring: a few inharmonic partials.
func _ring(seconds: float, base: float, decay: float) -> PackedFloat32Array:
	var b = _buf(seconds)
	for ratio in [1.0, 2.76, 5.4, 8.93]:
		b = _mix(b, _tone(seconds, base * ratio, base * ratio * 0.995, 0.001, decay / (1.0 + ratio * 0.3)), 0.0, 1.0 / ratio)
	return b

## Random sharp crackles (fire, sizzle).
func _crackle(seconds: float, density: float, cutoff: float) -> PackedFloat32Array:
	var b = _buf(seconds)
	var count = int(seconds * density)
	for c in count:
		var pop = _noise(0.012, cutoff, cutoff * 0.5, 0.0005, 0.003, 400.0)
		b = _mix(b, pop, _rng.randf_range(0.0, seconds - 0.015), _rng.randf_range(0.3, 1.0))
	b.resize(int(seconds * RATE))
	return b

func _arpeggio(freqs: Array, step: float, note_len: float, wave := "sine", decay := 0.25) -> PackedFloat32Array:
	var b = _buf(step * freqs.size() + note_len)
	for i in freqs.size():
		var f: float = freqs[i]
		b = _mix(b, _tone(note_len, f, f, 0.004, decay, wave), step * i, 0.6)
		b = _mix(b, _tone(note_len, f * 2.0, f * 2.0, 0.004, decay * 0.6), step * i, 0.15)
	return b

# ---------------------------------------------------------------- weapons

func _s_sword() -> PackedFloat32Array:
	var b = _noise(0.22, 900.0, 4500.0, 0.06, 0.05, 500.0)  # whoosh
	b = _mix(b, _ring(0.4, 1250.0, 0.12), 0.07, 0.35)          # blade "shing"
	b = _mix(b, _noise(0.05, 5000.0, 2000.0, 0.001, 0.015, 1500.0), 0.07, 0.6)
	return b

# ---------------------------------------------------------------- objects (MapObjects)

## Something breaking: a splintering crack and a few falling bits.
func _s_smash() -> PackedFloat32Array:
	var b = _noise(0.08, 2500.0, 900.0, 0.001, 0.025, 300.0)
	b = _mix(b, _tone(0.3, 120.0, 50.0, 0.002, 0.08), 0.0, 1.0)
	b = _mix(b, _crackle(0.35, 40.0, 3000.0), 0.03, 0.7)
	for i in 4:
		b = _mix(b, _noise(0.05, 1800.0, 600.0, 0.001, 0.015, 400.0), 0.12 + i * 0.07 + _rng.randf_range(0.0, 0.03), 0.5 - i * 0.08)
	return b

## Picking something up: a soft scrape and a thump.
func _s_pickup() -> PackedFloat32Array:
	var b = _noise(0.12, 800.0, 2200.0, 0.03, 0.04, 300.0)
	b = _mix(b, _tone(0.12, 220.0, 160.0, 0.003, 0.04, "tri"), 0.06, 0.6)
	return b

## A lid creaking open, then coins.
func _s_chest() -> PackedFloat32Array:
	var b = _tone(0.32, 260.0, 340.0, 0.03, 0.18, "saw", 0.04, 22.0)
	b = _mix(_buf(0.7), b, 0.0, 0.25)
	for i in 6:
		b = _mix(b, _ring(0.18, _rng.randf_range(2400.0, 3400.0), 0.05), 0.3 + i * 0.05 + _rng.randf_range(0.0, 0.02), 0.25)
	return b

## A bottle unstoppered and drunk: a pop and a few bubbles.
func _s_potion() -> PackedFloat32Array:
	var b = _noise(0.03, 3000.0, 1200.0, 0.001, 0.008, 800.0)
	for i in 5:
		var f = _rng.randf_range(500.0, 900.0)
		b = _mix(b, _tone(0.07, f, f * 1.6, 0.004, 0.025), 0.06 + i * 0.06, 0.45)
	b = _mix(b, _arpeggio([660.0, 880.0], 0.06, 0.2), 0.36, 0.5)
	return b

## Glass shattering.
func _s_glass() -> PackedFloat32Array:
	var b = _noise(0.05, 6000.0, 3000.0, 0.001, 0.02, 2000.0)
	for i in 8:
		b = _mix(b, _ring(0.2, _rng.randf_range(2800.0, 5200.0), 0.04), _rng.randf_range(0.0, 0.18), 0.22)
	return b

## A lock giving way: two metal clicks.
func _s_unlock() -> PackedFloat32Array:
	var b = _ring(0.08, 1800.0, 0.02)
	b = _mix(b, _ring(0.12, 1300.0, 0.03), 0.09, 1.0)
	return b

func _s_blunt() -> PackedFloat32Array:
	var b = _noise(0.15, 500.0, 1500.0, 0.05, 0.04, 200.0)
	b = _mix(b, _tone(0.25, 140.0, 55.0, 0.002, 0.07), 0.08, 1.2)
	b = _mix(b, _noise(0.12, 1200.0, 300.0, 0.001, 0.03), 0.08, 0.9)
	return b

func _s_punch() -> PackedFloat32Array:
	var b = _noise(0.08, 600.0, 1800.0, 0.03, 0.03, 300.0)
	b = _mix(b, _tone(0.16, 180.0, 70.0, 0.001, 0.04), 0.04, 1.0)
	b = _mix(b, _noise(0.06, 2000.0, 500.0, 0.001, 0.015), 0.04, 0.7)
	return b

func _s_claw() -> PackedFloat32Array:
	var b = _buf(0.3)
	for i in 3:
		b = _mix(b, _noise(0.07, 6000.0, 1800.0, 0.004, 0.02, 1200.0), i * 0.055, 1.0 - i * 0.15)
	return b

func _s_bite() -> PackedFloat32Array:
	var b = _tone(0.3, 110.0, 70.0, 0.02, 0.12, "saw", 0.08, 25.0)  # growl
	b = _mix(b, _noise(0.06, 3500.0, 900.0, 0.001, 0.015, 300.0), 0.1, 1.4)  # crunch
	b = _mix(b, _noise(0.05, 3000.0, 800.0, 0.001, 0.012, 300.0), 0.16, 1.0)
	return b

func _s_bow() -> PackedFloat32Array:
	# String twang: plucked tone with a quick pitch drop and harmonics.
	var b = _tone(0.35, 260.0, 210.0, 0.001, 0.09, "tri")
	b = _mix(b, _tone(0.25, 520.0, 420.0, 0.001, 0.05), 0.0, 0.4)
	b = _mix(b, _noise(0.02, 4000.0, 2000.0, 0.0005, 0.005), 0.0, 0.7)  # release click
	# Arrow flight whoosh.
	b = _mix(b, _noise(0.25, 1500.0, 4000.0, 0.08, 0.06, 900.0), 0.04, 0.5)
	return b

func _s_crossbow() -> PackedFloat32Array:
	var b = _noise(0.03, 6000.0, 2500.0, 0.0005, 0.006, 800.0)  # trigger clack
	b = _mix(b, _tone(0.2, 340.0, 250.0, 0.001, 0.05, "square"), 0.01, 0.25)
	b = _mix(b, _tone(0.25, 180.0, 140.0, 0.001, 0.06, "tri"), 0.01, 0.6)
	b = _mix(b, _noise(0.18, 2500.0, 5000.0, 0.03, 0.04, 1200.0), 0.03, 0.45)
	return b

func _s_throw() -> PackedFloat32Array:
	return _noise(0.28, 700.0, 3200.0, 0.1, 0.06, 500.0)

func _s_miss() -> PackedFloat32Array:
	var b = _noise(0.25, 2500.0, 800.0, 0.04, 0.07, 400.0)
	return b

func _s_hit() -> PackedFloat32Array:
	var b = _tone(0.2, 120.0, 50.0, 0.001, 0.05)
	b = _mix(b, _noise(0.08, 2500.0, 400.0, 0.001, 0.02), 0.0, 0.8)
	return b

func _s_crit() -> PackedFloat32Array:
	var b = _tone(0.35, 100.0, 40.0, 0.001, 0.09)
	b = _mix(b, _noise(0.12, 4000.0, 400.0, 0.001, 0.03), 0.0, 1.0)
	b = _mix(b, _ring(0.5, 900.0, 0.15), 0.0, 0.3)
	return b

# ---------------------------------------------------------------- magic

func _s_cast() -> PackedFloat32Array:
	var b = _tone(0.4, 500.0, 900.0, 0.12, 0.12, "sine", 0.02, 9.0)
	b = _mix(b, _tone(0.4, 750.0, 1350.0, 0.12, 0.1), 0.0, 0.4)
	b = _mix(b, _noise(0.35, 2500.0, 6000.0, 0.15, 0.08, 2000.0), 0.0, 0.25)
	return b

func _s_fire() -> PackedFloat32Array:
	var b = _noise(0.75, 300.0, 1400.0, 0.08, 0.25, 60.0)  # roar
	b = _mix(b, _noise(0.5, 120.0, 60.0, 0.02, 0.2), 0.0, 1.2)  # low body
	b = _mix(b, _crackle(0.75, 40.0, 5000.0), 0.0, 0.5)
	return b

func _s_cold() -> PackedFloat32Array:
	var b = _noise(0.6, 4000.0, 7000.0, 0.03, 0.2, 2500.0)  # icy hiss
	for f in [1760.0, 2349.0, 3136.0, 3951.0]:
		b = _mix(b, _tone(0.6, f, f * 1.01, 0.002, 0.18), _rng.randf_range(0.0, 0.12), 0.25)
	return b

func _s_lightning() -> PackedFloat32Array:
	var b = _buf(0.5)
	var lp = 0.0
	for i in b.size():
		var t = float(i) / RATE
		# Harsh, jittery buzz.
		if _rng.randf() < 0.08:
			lp = _rng.randf_range(-1.0, 1.0)
		b[i] = lp * _env(t, 0.002, 0.12)
	b = _mix(b, _tone(0.4, 220.0, 80.0, 0.001, 0.1, "saw", 0.3, 47.0), 0.0, 0.5)
	b = _mix(b, _noise(0.4, 2000.0, 300.0, 0.001, 0.12), 0.0, 0.6)  # crack
	return b

func _s_thunder() -> PackedFloat32Array:
	var b = _noise(1.0, 250.0, 60.0, 0.005, 0.35)  # rumble
	b = _mix(b, _tone(0.6, 70.0, 35.0, 0.002, 0.2), 0.0, 1.2)
	b = _mix(b, _noise(0.08, 3000.0, 800.0, 0.001, 0.02), 0.0, 0.8)
	return b

func _s_acid() -> PackedFloat32Array:
	var b = _noise(0.6, 5000.0, 3000.0, 0.02, 0.2, 1500.0)  # sizzle
	for i in 7:
		var f = _rng.randf_range(300.0, 700.0)
		b = _mix(b, _tone(0.06, f, f * 2.2, 0.002, 0.02), _rng.randf_range(0.0, 0.5), 0.4)
	return b

func _s_poison() -> PackedFloat32Array:
	var b = _noise(0.6, 400.0, 250.0, 0.05, 0.2, 80.0)
	for i in 6:
		var f = _rng.randf_range(120.0, 260.0)
		b = _mix(b, _tone(0.09, f, f * 1.8, 0.005, 0.03), 0.04 + i * 0.08, 0.6)  # gurgle
	return b

func _s_necrotic() -> PackedFloat32Array:
	var b = _tone(0.8, 220.0, 90.0, 0.08, 0.3, "saw")
	b = _mix(b, _tone(0.8, 226.0, 93.0, 0.08, 0.3, "saw"), 0.0, 1.0)  # detuned
	b = _mix(b, _noise(0.7, 900.0, 200.0, 0.1, 0.25, 100.0), 0.0, 0.8)
	return b

func _s_radiant() -> PackedFloat32Array:
	var b = _arpeggio([784.0, 988.0, 1175.0, 1568.0], 0.04, 0.7, "sine", 0.3)
	b = _mix(b, _noise(0.6, 6000.0, 8000.0, 0.05, 0.2, 4000.0), 0.0, 0.15)
	return b

func _s_psychic() -> PackedFloat32Array:
	var b = _tone(0.7, 600.0, 300.0, 0.03, 0.25, "sine", 0.15, 11.0)
	b = _mix(b, _tone(0.7, 905.0, 455.0, 0.03, 0.25, "tri", 0.12, 7.0), 0.0, 0.5)
	return b

func _s_force() -> PackedFloat32Array:
	var b = _tone(0.35, 1400.0, 300.0, 0.002, 0.1)
	b = _mix(b, _tone(0.35, 700.0, 150.0, 0.002, 0.1, "tri"), 0.0, 0.6)
	b = _mix(b, _noise(0.15, 4000.0, 1000.0, 0.001, 0.04, 800.0), 0.0, 0.3)
	return b

func _s_heal() -> PackedFloat32Array:
	return _arpeggio([523.0, 659.0, 784.0, 1047.0], 0.07, 0.6, "sine", 0.25)

func _s_buff() -> PackedFloat32Array:
	var b = _buf(0.7)
	for i in 8:
		var f = _rng.randf_range(1800.0, 4200.0)
		b = _mix(b, _tone(0.25, f, f, 0.002, 0.07), i * 0.06, 0.4)
	b = _mix(b, _tone(0.6, 440.0, 660.0, 0.1, 0.2), 0.0, 0.4)
	return b

func _s_rage() -> PackedFloat32Array:
	var b = _tone(0.6, 90.0, 140.0, 0.05, 0.25, "saw", 0.06, 18.0)
	b = _mix(b, _tone(0.6, 135.0, 210.0, 0.05, 0.25, "square", 0.05, 15.0), 0.0, 0.3)
	b = _mix(b, _noise(0.5, 600.0, 1200.0, 0.05, 0.2, 100.0), 0.0, 0.5)
	return b

func _s_teleport() -> PackedFloat32Array:
	var b = _tone(0.45, 300.0, 1800.0, 0.02, 0.15, "sine", 0.05, 20.0)
	b = _mix(b, _noise(0.4, 1500.0, 7000.0, 0.05, 0.12, 1000.0), 0.0, 0.4)
	return b

# ---------------------------------------------------------------- states & UI

func _s_down() -> PackedFloat32Array:
	var b = _tone(0.6, 330.0, 150.0, 0.005, 0.2, "tri")
	b = _mix(b, _tone(0.6, 262.0, 110.0, 0.005, 0.2), 0.12, 0.8)
	return b

func _s_death() -> PackedFloat32Array:
	var b = _tone(1.0, 196.0, 98.0, 0.01, 0.35, "saw")
	b = _mix(b, _tone(1.0, 233.0, 110.0, 0.01, 0.35, "saw"), 0.0, 0.7)
	b = _mix(b, _noise(0.5, 400.0, 100.0, 0.01, 0.2), 0.0, 0.6)
	return b

func _s_nat20() -> PackedFloat32Array:
	return _arpeggio([523.0, 784.0, 1047.0, 1319.0, 1568.0], 0.06, 0.5, "tri", 0.22)

func _s_condition() -> PackedFloat32Array:
	return _tone(0.25, 400.0, 250.0, 0.005, 0.08, "tri")

func _s_turn() -> PackedFloat32Array:
	var b = _tone(0.9, 880.0, 880.0, 0.002, 0.35)
	b = _mix(b, _tone(0.9, 1320.0, 1320.0, 0.002, 0.25), 0.0, 0.35)
	b = _mix(b, _tone(0.9, 2213.0, 2213.0, 0.002, 0.12), 0.0, 0.15)
	return b

func _s_step() -> PackedFloat32Array:
	var b = _noise(0.06, 900.0, 300.0, 0.002, 0.015, 120.0)
	b = _mix(b, _tone(0.05, 110.0, 70.0, 0.001, 0.012), 0.0, 0.6)
	return b

func _s_click() -> PackedFloat32Array:
	return _tone(0.05, 1500.0, 1200.0, 0.001, 0.01, "tri")

## Dice rattling: a handful of short wooden clacks.
func _s_dice() -> PackedFloat32Array:
	var b = _buf(0.34)
	for i in 7:
		var at = 0.02 + i * 0.04 + _rng.randf_range(-0.012, 0.012)
		var click = _noise(0.03, 3200.0, 1400.0, 0.001, 0.006, 600.0)
		click = _mix(click, _tone(0.025, _rng.randf_range(900.0, 1500.0), 700.0, 0.001, 0.005, "tri"), 0.0, 0.5)
		b = _mix(b, click, at, 1.0 - i * 0.09)
	return b

## Picking an action from the hotbar: a soft, rising two-note blip.
func _s_select() -> PackedFloat32Array:
	var b = _tone(0.09, 880.0, 990.0, 0.002, 0.03, "tri")
	b = _mix(b, _tone(0.12, 1320.0, 1480.0, 0.002, 0.04, "sine"), 0.045, 0.7)
	return b

## Backing out of targeting: the same blip, falling.
func _s_cancel() -> PackedFloat32Array:
	var b = _tone(0.09, 990.0, 880.0, 0.002, 0.03, "tri")
	b = _mix(b, _tone(0.12, 740.0, 620.0, 0.002, 0.04, "sine"), 0.045, 0.7)
	return b

## Not allowed (not a valid target, not your turn): a short, low double buzz.
func _s_error() -> PackedFloat32Array:
	var b = _tone(0.08, 180.0, 170.0, 0.002, 0.03, "square")
	b = _mix(b, _tone(0.1, 150.0, 140.0, 0.002, 0.04, "square"), 0.09, 1.0)
	return b

## One of your characters is badly hurt: two heartbeat thumps.
func _s_danger() -> PackedFloat32Array:
	var b = _buf(0.6)
	for at in [0.0, 0.2]:
		b = _mix(b, _tone(0.22, 85.0, 45.0, 0.004, 0.06), at, 1.0 if at == 0.0 else 0.8)
		b = _mix(b, _noise(0.06, 300.0, 120.0, 0.002, 0.02), at, 0.4)
	return b

## Combat begins: a war-drum hit under a short brass-like call.
func _s_combat_start() -> PackedFloat32Array:
	var b = _tone(0.6, 95.0, 50.0, 0.002, 0.16)                       # drum body
	b = _mix(b, _noise(0.2, 900.0, 200.0, 0.001, 0.05), 0.0, 0.7)    # skin
	b = _mix(b, _tone(0.5, 92.0, 52.0, 0.002, 0.14), 0.22, 0.8)       # second hit
	for f in [196.0, 294.0]:                                          # horn fifth
		b = _mix(b, _tone(0.8, f, f, 0.06, 0.3, "saw", 0.01, 5.0), 0.2, 0.18)
		b = _mix(b, _tone(0.8, f * 2.0, f * 2.0, 0.06, 0.25), 0.2, 0.08)
	return b

## Victory: a bright rising major fanfare that settles on a held chord.
func _s_victory() -> PackedFloat32Array:
	var b = _arpeggio([392.0, 523.0, 659.0, 784.0], 0.1, 0.5, "tri", 0.22)
	for f in [523.0, 659.0, 784.0, 1047.0]:
		b = _mix(b, _tone(1.1, f, f, 0.02, 0.45, "tri", 0.006, 5.0), 0.42, 0.22)
	return b

## Defeat: a slow falling minor line.
func _s_defeat() -> PackedFloat32Array:
	var b = _buf(1.6)
	var notes = [392.0, 349.0, 311.0, 262.0]
	for i in notes.size():
		var f: float = notes[i]
		b = _mix(b, _tone(0.7, f, f * 0.99, 0.03, 0.3, "saw"), i * 0.28, 0.25)
		b = _mix(b, _tone(0.7, f * 0.5, f * 0.5, 0.03, 0.3), i * 0.28, 0.5)
	return b

## A level is ready: a quick sparkle up into a chord.
func _s_levelup() -> PackedFloat32Array:
	var b = _arpeggio([523.0, 659.0, 784.0, 1047.0, 1319.0], 0.05, 0.4, "sine", 0.18)
	for f in [784.0, 1047.0, 1319.0]:
		b = _mix(b, _tone(0.9, f, f, 0.01, 0.35, "tri"), 0.26, 0.2)
	for i in 6:
		var s = _rng.randf_range(2600.0, 4800.0)
		b = _mix(b, _tone(0.18, s, s, 0.002, 0.05), 0.26 + i * 0.05, 0.12)
	return b
