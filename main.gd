extends Node3D

signal back_requested


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

@export var square_size: float = 0.1
@export var current_pixel_size: int = 16
@export var default_model: PackedScene

var selected_model: PackedScene
var model_instance: QuizModel
var mesh_instances: Array[MeshInstance3D] = []

var triangles: Array[TriangleData] = []
var camera_rotation_center: Vector3
var original_camera_rotation_center: Vector3
var current_normal_line: MeshInstance3D
var current_square: MeshInstance3D
var current_color: Color = Color.SLATE_BLUE
var current_normal: Vector3
var overlay_dirty := false


@onready var model_anchor: Marker3D = $Marker3D
@onready var camera: Camera3D = $Camera3D
@onready var original_camera_transform: Transform3D = camera.transform
@onready var reset_camera_button: Button = $CanvasLayer/VBoxContainer/ResetCameraButton
@onready var color_picker: ColorPicker = $CanvasLayer/VBoxContainer/ColorPicker
@onready var guess_button: Button = $CanvasLayer/VBoxContainer/GuessButton
@onready var guess_vector_label: Label = %GuessVector
@onready var guess_color_rect: ColorRect = %GuessColor
@onready var true_vector_label: Label = %TrueVector
@onready var true_color_rect: ColorRect = %TrueColor
@onready var answer_container: HBoxContainer = %AnswerContainer
@onready var accuracy_label: Label = %AccuracyLabel
@onready var normal_map_toggle: CheckBox = %NormalMapToggle
@onready var pixel_size_input: LineEdit = %PixelSizeInput
@onready var overlay: Control = $CanvasLayer/Overlay
@onready var random_button: Button = %RandomButton

func _ready() -> void:
	if not load_selected_model():
		set_physics_process(false)
		set_process_unhandled_input(false)
		guess_button.disabled = true
		random_button.disabled = true
		normal_map_toggle.disabled = true
		return

	seed(5)

	reset_camera_button.pressed.connect(_on_reset_camera_button_pressed)
	color_picker.color_changed.connect(_on_color_changed)
	guess_button.pressed.connect(_on_guess_made)
	random_button.pressed.connect(_on_random_button_pressed)

	answer_container.hide()

	# color_picker.picker_shape = ColorPicker.SHAPE_VHS_CIRCLE
	color_picker.edit_alpha = false
	color_picker.color = current_color
	_on_color_changed(color_picker.color)
	
	pixel_size_input.text_changed.connect(_on_pixel_size_value_changed)
	pixel_size_input.text = "16"
	_on_pixel_size_value_changed("16")
	normal_map_toggle.toggled.connect(_on_normal_map_toggled)
	
	var bounds: AABB = mesh_instances[0].global_transform * mesh_instances[0].get_aabb()
	for mesh_instance in mesh_instances:
		var mesh_bounds: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
		bounds = bounds.merge(mesh_bounds)
	var mesh_center := bounds.get_center()

	var forward = -camera.global_basis.z
	var depth = (mesh_center - camera.global_position).dot(forward)

	camera_rotation_center = camera.global_position + forward * maxf(depth, 0.1)
	original_camera_rotation_center = camera_rotation_center

func _on_back_button_pressed() -> void:
	back_requested.emit()


func load_selected_model() -> bool:
	var scene: PackedScene = selected_model
	if scene == null:
		scene = default_model
	if scene == null:
		push_error("No quiz model selected.")
		return false

	var instance := scene.instantiate()
	if not instance is QuizModel:
		push_error("The model scene's root must use quiz_model.gd.")
		instance.free()
		return false

	model_instance = instance as QuizModel
	model_anchor.add_child(model_instance)
	mesh_instances = model_instance.get_mesh_instances()
	if mesh_instances.is_empty():
		push_error("The quiz model has no visible triangle meshes.")
		model_instance.queue_free()
		return false

	model_instance.ensure_mesh_collisions(mesh_instances)
	return true



func _physics_process(delta: float) -> void:
	if overlay_dirty:
		overlay_dirty = false
		set_physics_process(false)

		if normal_map_toggle.button_pressed:
			build_mock_overlay()

		return

	set_physics_process(false)

	collect_triangle_data()

	pick_and_draw_random_visible_triangle()

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

		if Input.is_action_pressed("left_click"):
			pick_face_at_mouse(camera.get_viewport().get_mouse_position())
			get_viewport().set_input_as_handled()


func clear_current_normal_visual():
	if current_normal_line != null:
		current_normal_line.queue_free()
	if current_square != null:
		current_square.queue_free()
	
func collect_triangle_data():
	triangles.clear()

	for mesh_instance in mesh_instances:
		var vertices := mesh_instance.mesh.get_faces()
		for i in range(0, vertices.size(), 3):
			var a := mesh_instance.to_global(vertices[i])
			var b := mesh_instance.to_global(vertices[i + 1])
			var c := mesh_instance.to_global(vertices[i + 2])

			var cross_product := (c - a).cross(b - a)
			var twice_area := cross_product.length()
			if twice_area <= 0.0000001:
				continue
			var normal := cross_product / twice_area

			triangles.append(TriangleData.new(a, b, c, normal, twice_area * 0.5))

func is_triangle_visible(triangle: TriangleData) -> bool:
	var center = (triangle.a + triangle.b + triangle.c) / 3
	var direction_toward_camera = camera.transform.origin - center

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

func draw_normal(starting_point: Vector3, normal: Vector3, length: float = 0.5):
	clear_current_normal_visual()
	answer_container.hide()
	accuracy_label.text = "Accuracy:"
		
	var direction = normal.normalized()
	current_normal = direction

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

	draw_square(starting_point, normal)

	current_normal_line = line_mesh


func pick_and_draw_random_visible_triangle():
	var visible_triangles: Array[TriangleData] = []
	for triangle in triangles:
		if is_triangle_visible(triangle):
			visible_triangles.append(triangle)

	if visible_triangles.is_empty():
		push_warning("No visible triangle centers found. Check model placement and collision.")
		return

	var selected: TriangleData = visible_triangles.pick_random()
	var point = (selected.a + selected.b + selected.c) / 3.0

	draw_normal(point, selected.normal)

func rotate_camera(mouse_delta: Vector2) -> void:
	clear_current_normal_visual()
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
	clear_current_normal_visual()
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


func pick_face_at_mouse(screen_position: Vector2):
	var start = camera.project_position(screen_position, camera.near)
	var end = camera.project_position(screen_position, camera.far)

	var query = PhysicsRayQueryParameters3D.create(start, end)
	var hit = get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		return

	if not model_instance.is_ancestor_of(hit["collider"]):
		return

	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]

	draw_normal(point, normal)

func draw_square(point: Vector3, normal: Vector3):
	var up = normal.normalized()
	var reference = Vector3.UP
	if absf(up.dot(reference)) > 0.95:
		reference = Vector3.RIGHT

	var right = reference.cross(up).normalized()
	var back = right.cross(up).normalized()
	var orientation = Basis(right, up, back)

	var plane = PlaneMesh.new()
	plane.size = Vector2(square_size, square_size)

	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(Color.YELLOW, 1.0)

	var square = MeshInstance3D.new()
	square.mesh = plane
	square.material_override = material
	add_child(square)
	square.top_level = true
	square.global_transform = Transform3D(
		orientation,
		point + up * 0.01
	)
	current_square = square


func sample_mock_pixel(rect: Rect2, samples_per: int = 2):
	var summed_normals: Vector3 = Vector3.ZERO
	var num_faces_hit: int = 0
	var space_state = get_world_3d().direct_space_state

	for y in range(samples_per):
		for x in range(samples_per):
			var sampled_center: Vector2 = Vector2((x + 0.5) / samples_per, (y + 0.5) / samples_per)
			var pixel = rect.position + rect.size * sampled_center

			var start := camera.project_position(pixel, camera.near)
			var end := camera.project_position(pixel, camera.far)
			
			var query := PhysicsRayQueryParameters3D.create(start, end)
			var hit := space_state.intersect_ray(query)
			
			if hit.is_empty():
				continue

			if not model_instance.is_ancestor_of(hit["collider"]):
				continue

			var normal = hit["normal"]
			summed_normals += normal
			num_faces_hit += 1
			
	if num_faces_hit == 0:
		return {}

	var average_normal = summed_normals.normalized()

	var camera_rotation = camera.transform.basis.orthonormalized()
	var view_normal = (camera_rotation.transposed() * average_normal).normalized()

	return {
		"color": Color(view_normal.x / 2.0 + 0.5, view_normal.y / 2.0 + 0.5, view_normal.z / 2.0 + 0.5),
		"coverage": float(num_faces_hit) / (samples_per * samples_per)
	}

func build_mock_overlay():
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()

	var screen = get_viewport().get_visible_rect()
	if current_pixel_size < 0:
		return
	var cell_size = current_pixel_size

	for y in range(0, int(screen.size.y), cell_size):
		for x in range(0, int(screen.size.x), cell_size):
			var current_position = screen.position + Vector2(x, y)
			var size = Vector2(minf(cell_size, screen.end.x - position.x), minf(cell_size, screen.end.y - position.y))
			var rect = Rect2(current_position, size)

			var result = sample_mock_pixel(rect, 2)

			if result.is_empty():
				continue

			var square := ColorRect.new()
			square.position = rect.position
			square.size = rect.size
			square.color = result["color"]
			square.mouse_filter = Control.MOUSE_FILTER_IGNORE
			overlay.add_child(square)

func _on_reset_camera_button_pressed():
	camera.global_transform = original_camera_transform
	camera_rotation_center = original_camera_rotation_center


func _on_color_changed(color: Color):
	current_color = color
	var guess_to_normalized = (Vector3(color.r, color.g, color.b) * 2.0 - Vector3.ONE).normalized()
	guess_vector_label.text = "(%.2f, %.2f, %.2f)" % [guess_to_normalized.x, guess_to_normalized.y, guess_to_normalized.z]
	guess_color_rect.color = current_color

func _on_guess_made():
	answer_container.show()
	true_vector_label.text = "(%.2f, %.2f, %.2f)" % [current_normal.x, current_normal.y, current_normal.z]
	
	var current_rgb_vector = Vector3(current_color.r, current_color.g, current_color.b)
	var current_normal_to_rgb = (current_normal + Vector3(1, 1, 1)) / 2.0
	true_color_rect.color = Color(current_normal_to_rgb.x, current_normal_to_rgb.y, current_normal_to_rgb.z)
	var accuracy = 100.0 * (1 - (current_rgb_vector.distance_to(current_normal_to_rgb) / sqrt(3.0)))
	accuracy_label.text = "%.2f" % accuracy

func _on_pixel_size_value_changed(new_text: String):
	if new_text.is_valid_int():
		current_pixel_size = new_text.to_int()
	else:
		current_pixel_size = -1

	request_overlay_rebuild()

func request_overlay_rebuild() -> void:
	if normal_map_toggle.button_pressed:
		overlay_dirty = true
		set_physics_process(true)

func _on_normal_map_toggled(toggled_on: bool):
	overlay.visible = toggled_on

	if toggled_on:
		request_overlay_rebuild()

func _on_random_button_pressed():
	pick_and_draw_random_visible_triangle()
