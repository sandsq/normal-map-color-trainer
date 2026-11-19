extends Node3D


class TriangleData:
	var a: Vector3
	var b: Vector3
	var c: Vector3
	var normal: Vector3
	var area: float

	func _init(_a: Vector3, _b: Vector3, _c: Vector3, _normal: Vector3, _area: float):
		a = _a
		b = _b
		c = _c
		normal = _normal
		area = _area
	

const EPS: float = 0.0001
const ROTATE_SPEED: float = 0.005
const ZOOM_SPEED: float = 0.1

var triangles: Array[TriangleData] = []
var camera_rotation_center: Vector3
var original_camera_rotation_center: Vector3

@onready var tree_model: Node3D = $Tree
@onready var mesh_instance: MeshInstance3D = tree_model.get_node("Tree_1_A_Color1")
@onready var camera: Camera3D = $Camera3D
@onready var original_camera_transform: Transform3D = camera.transform
@onready var reset_camera_button: Button = $CanvasLayer/Button

func _ready() -> void:
	seed(5)

	reset_camera_button.pressed.connect(_on_reset_camera_button_pressed)
	
	var mesh_center = mesh_instance.to_global(mesh_instance.get_aabb().get_center())

	var forward = -camera.global_basis.z
	var depth = (mesh_center - camera.global_position).dot(forward)

	camera_rotation_center = camera.global_position + forward * maxf(depth, 0.1)
	original_camera_rotation_center = camera_rotation_center

func _physics_process(delta: float) -> void:
	set_physics_process(false)

	collect_triangle_data()

	var visible_triangles: Array[TriangleData] = []
	for triangle in triangles:
		if is_triangle_visible(triangle):
			visible_triangles.append(triangle)

	var selected: TriangleData = visible_triangles.pick_random()
	var point = (selected.a + selected.b + selected.c) / 3.0

	draw_normal(point, selected.normal)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.is_action_pressed("rotate_camera"):
			rotate_camera(event.relative)
			get_viewport().set_input_as_handled()
		elif Input.is_action_pressed("pan_camera"):
			pan_camera(event.relative)
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton:
		if Input.is_action_pressed("camera_zoom_in"):
			zoom_camera(&"in")
			get_viewport().set_input_as_handled()
		elif Input.is_action_pressed("camera_zoom_out"):
			zoom_camera(&"out")			
			get_viewport().set_input_as_handled()
			
func collect_triangle_data():
	triangles.clear()
	
	var vertices: PackedVector3Array = mesh_instance.mesh.get_faces()
	for i in range(0, vertices.size(), 3):
		var a = mesh_instance.to_global(vertices[i])
		var b = mesh_instance.to_global(vertices[i + 1])
		var c = mesh_instance.to_global(vertices[i + 2])

		var cross_product = (c - a).cross(b - a)
		var area = cross_product.length()
		var normal = cross_product / area

		triangles.append(TriangleData.new(a, b, c, normal, area * 0.5))

func is_triangle_visible(triangle: TriangleData) -> bool:
	var center = (triangle.a + triangle.b + triangle.c) / 3
	var direction_toward_camera = original_camera_transform.origin - center

	if triangle.normal.dot(direction_toward_camera) <= 0.0:
		return false

	if not camera.is_position_in_frustum(center):
		return false

	var query_direction = (center - camera.global_position).normalized()
	var query = PhysicsRayQueryParameters3D.create(camera.global_position, center + query_direction * 0.01)

	var hit = get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		return false

	var hit_position: Vector3 = hit["position"]

	return hit_position.distance_to(center) < EPS

func draw_normal(starting_point: Vector3, normal: Vector3, length: float = 1.0):
	var direction = normal.normalized()

	var start = starting_point + direction * 0.01
	var end = start + direction * length

	var lines = ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	lines.surface_add_vertex(start)
	lines.surface_add_vertex(end)
	lines.surface_end()

	var material = StandardMaterial3D.new()
	material.albedo_color = Color.YELLOW

	var line_mesh = MeshInstance3D.new()
	line_mesh.mesh = lines
	line_mesh.material_override = material
	add_child(line_mesh)


func rotate_camera(mouse_delta: Vector2) -> void:
	var distance := camera.global_position.distance_to(camera_rotation_center)
	var angles := camera.global_rotation

	angles.y -= mouse_delta.x * ROTATE_SPEED
	angles.x = clampf(
		angles.x - mouse_delta.y * ROTATE_SPEED,
		deg_to_rad(-89.0),
		deg_to_rad(89.0)
	)

	camera.global_rotation = angles

	camera.global_position = (
		camera_rotation_center + camera.global_basis.z * distance
	)

func pan_camera(mouse_delta: Vector2) -> void:
	var distance := camera.global_position.distance_to(camera_rotation_center)
	var viewport_height := camera.get_viewport().get_visible_rect().size.y

	var visible_height := (
		2.0 * distance * tan(deg_to_rad(camera.fov) * 0.5)
	)
	var units_per_pixel := visible_height / viewport_height

	var movement := (
		-camera.global_basis.x * mouse_delta.x
		+ camera.global_basis.y * mouse_delta.y
	) * units_per_pixel

	camera.global_position += movement
	camera_rotation_center += movement

func zoom_camera(direction: StringName):
	var camera_facing_direction = camera.get_global_transform().basis.z.normalized()
	if direction == &'in':
		camera.global_position -= ZOOM_SPEED * camera_facing_direction
	elif direction == &'out':
		camera.global_position += ZOOM_SPEED * camera_facing_direction

func _on_reset_camera_button_pressed():
	camera.global_transform = original_camera_transform
	camera_rotation_center = original_camera_rotation_center
