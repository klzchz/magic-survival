extends Camera3D
# Don't Starve style follow camera: narrow-FOV perspective from high up,
# orbiting its target on Y and easing after it. Movement is camera-relative,
# so the world asks it for forward() / right().

const DISTANCE := 11.5
const HEIGHT := 9.5          # ~40 degree pitch: depth and a hint of horizon
const LOOK_AHEAD := 2.2

var target: Node3D
var angle := 0.0           # radians
var _focus := Vector3.ZERO
var _snapped := false
var zoom := 1.0              # mouse wheel: 0.7 (close) .. 1.45 (far)


func _ready() -> void:
	projection = PROJECTION_PERSPECTIVE
	fov = 48.0
	near = 0.5
	far = 260.0
	current = true


func forward() -> Vector3:
	return -Vector3(sin(angle), 0, cos(angle))


func right() -> Vector3:
	return forward().cross(Vector3.UP).normalized()


## Main-menu backdrop: a slow, wide orbit over the island.
func orbit(delta: float) -> void:
	if not is_inside_tree():
		return
	angle += 0.06 * delta
	_snapped = false
	position = Vector3(sin(angle), 0, cos(angle)) * 34.0 + Vector3(0, 26, 0)
	look_at(Vector3(0, 2, 0), Vector3.UP)


func follow(delta := 1.0) -> void:
	if target == null or not is_inside_tree():
		return
	if not _snapped:
		_focus = target.position
		_snapped = true
	var ahead := Vector3.ZERO
	if "velocity" in target:
		ahead = target.velocity * (LOOK_AHEAD / 10.0)
	_focus = _focus.lerp(target.position + ahead, minf(1.0, 5.0 * delta))
	position = _focus + (Vector3(sin(angle), 0, cos(angle)) * DISTANCE + Vector3(0, HEIGHT, 0)) * zoom
	look_at(_focus + Vector3(0, 1.4, 0), Vector3.UP)


func zoom_by(step: float) -> void:
	zoom = clampf(zoom + step, 0.7, 1.45)
