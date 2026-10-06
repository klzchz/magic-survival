extends RefCounted
# Thin wrapper over a KayKit character's AnimationPlayer: a looping base pose
# (idle / walk / run) plus one-shot actions that blend back to the base.

const LOOPING := ["Idle", "Idle_B", "Running_A", "Walking_A", "Walking_D_Skeletons",
	"Spellcasting", "Lie_Idle", "Blocking", "Unarmed_Idle"]

var ap: AnimationPlayer
var base := ""
var busy_t := 0.0
var locked := false        # death pose holds until reset()


func _init(model: Node) -> void:
	if model == null:
		return
	ap = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		return
	for anim_name in LOOPING:
		if ap.has_animation(anim_name):
			ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR


func set_base(anim_name: String) -> void:
	if ap == null or anim_name == base or not ap.has_animation(anim_name):
		return
	base = anim_name
	if busy_t <= 0.0 and not locked:
		ap.play(anim_name, 0.2)


func action(anim_name: String, speed := 1.0) -> void:
	if ap == null or locked or not ap.has_animation(anim_name):
		return
	ap.play(anim_name, 0.1, speed)
	busy_t = ap.get_animation(anim_name).length / speed


# Plays and freezes on the last frame (death, victory pose).
func hold(anim_name: String) -> void:
	if ap == null or not ap.has_animation(anim_name):
		return
	locked = true
	ap.play(anim_name, 0.15)


func reset() -> void:
	locked = false
	busy_t = 0.0
	if ap != null and base != "":
		ap.play(base, 0.1)


func tick(delta: float) -> void:
	if busy_t > 0.0:
		busy_t -= delta
		if busy_t <= 0.0 and not locked and base != "" and ap != null:
			ap.play(base, 0.25)
