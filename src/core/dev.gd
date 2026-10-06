extends RefCounted
## Dev / QA hooks. Read from command-line user args after `--` (works on the
## Windows build, where WSL env vars don't arrive) or from MAGIC_* env vars.
##   --shot=6            save a screenshot after 6 s (shot-path to choose file)
##   --quit-after-shot   close the game right after the screenshot
##   --time=58           start the day clock at 58 s (first night)
##   --char=brasa        skip menus and start as this apprentice
##   --scene=night       stage a QA scene (see world._stage_scene)
##
## Example: `godot --path . -- --char=thorne --scene=base --shot=8 --quit-after-shot`


static func arg(key: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a == "--" + key:
			return "1"
		if a.begins_with("--%s=" % key):
			return a.split("=", true, 1)[1]
	return OS.get_environment("MAGIC_" + key.to_upper().replace("-", "_"))


static func has(key: String) -> bool:
	return arg(key) != ""
