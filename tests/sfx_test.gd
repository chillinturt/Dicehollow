extends Node
## Headless check that every named sound synthesizes, is a sensible length, and has a loudness level.
## Run: Godot --headless --path . res://tests/sfx_test.tscn

func _ready() -> void:
	var errors := 0
	for n in Sfx.names():
		var s: AudioStreamWAV = Sfx._stream(n)
		if s == null:
			print("FAIL: no sound for ", n)
			errors += 1
			continue
		var secs: float = s.data.size() / 2.0 / Sfx.RATE
		var lvl: float = float(Sfx.LEVEL.get(n, Sfx.DEFAULT_LEVEL))
		print("  %-13s %.2fs  level %.2f" % [n, secs, lvl])
		if secs < 0.03 or secs > 2.5:
			print("FAIL: odd length for ", n)
			errors += 1
	# Interface ticks must sit under the combat sounds.
	for quiet in ["click", "select", "cancel", "step"]:
		if float(Sfx.LEVEL[quiet]) >= Sfx.DEFAULT_LEVEL * 0.6:
			print("FAIL: %s is too loud next to combat sounds" % quiet)
			errors += 1
	var bi := AudioServer.get_bus_index(Sfx.BUS)
	if bi == -1 or AudioServer.get_bus_effect_count(bi) < 1 or not AudioServer.get_bus_effect(bi, 0) is AudioEffectHardLimiter:
		print("FAIL: no limiter on the SFX bus")
		errors += 1
	print("SFX DONE errors=%d" % errors)
	get_tree().quit()
