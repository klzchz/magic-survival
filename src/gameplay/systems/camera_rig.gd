extends Camera3D
# Don't Starve style follow camera: narrow-FOV perspective from high up,
# orbiting its target on Y and easing after it. Movement is camera-relative,
# so the world asks it for forward() / right().

const DISTANCE := 14.0
const HEIGHT := 14.5

var target: Node3D
var angle := 0.0           # radians
var _focus := Vector3.ZERO
var _snapped := false


func _ready() -> void:
	projection = PROJECTION_PERSPECTIVE
	fov = 40.0
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
	_focus = _focus.lerp(target.position, minf(1.0, 6.0 * delta))
	position = _focus + Vector3(sin(angle), 0, cos(angle)) * DISTANCE + Vector3(0, HEIGHT, 0)
	look_at(_focus + Vector3(0, 1.2, 0), Vector3.UP)
