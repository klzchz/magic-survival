extends Camera3D
# Don't Starve style follow camera: orthographic, orbiting its target on Y.
# Movement is camera-relative, so the world asks it for forward() / right().

var target: Node3D
var angle := 0.0           # radians


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	size = 22.0
	far = 200.0
	current = true


func forward() -> Vector3:
	return -Vector3(sin(angle), 0, cos(angle))


func right() -> Vector3:
	return forward().cross(Vector3.UP).normalized()


func follow() -> void:
	if target == null or not is_inside_tree():
		return
	position = target.position + Vector3(sin(angle), 0, cos(angle)) * 20.0 + Vector3(0, 22, 0)
	look_at(target.position + Vector3(0, 1, 0), Vector3.UP)
