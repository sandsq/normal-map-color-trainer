extends Node3D
class_name QuizModel

@export var mesh_instances: Array[MeshInstance3D] = []
# Keep existing single-mesh wrapper scenes compatible.
@export var mesh_instance: MeshInstance3D


func get_mesh_instances() -> Array[MeshInstance3D]:
	var candidates: Array[MeshInstance3D] = mesh_instances.duplicate()
	if candidates.is_empty():
		if mesh_instance != null:
			candidates.append(mesh_instance)
		else:
			for node in find_children("*", "MeshInstance3D", true, false):
				candidates.append(node as MeshInstance3D)

	var result: Array[MeshInstance3D] = []
	for candidate in candidates:
		if (
			is_instance_valid(candidate)
			and is_ancestor_of(candidate)
			and candidate.mesh != null
			and candidate.is_visible_in_tree()
			and not candidate.mesh.get_faces().is_empty()
			and not result.has(candidate)
		):
			result.append(candidate)

	return result


func ensure_mesh_collisions(meshes: Array[MeshInstance3D]) -> void:
	for instance in meshes:
		var has_trimesh := false
		for child in instance.get_children():
			if not child is StaticBody3D:
				continue

			for shape_node in child.get_children():
				if (
					shape_node is CollisionShape3D
					and shape_node.shape is ConcavePolygonShape3D
					and not shape_node.disabled
				):
					has_trimesh = true
					break

			if has_trimesh:
				break

		if not has_trimesh:
			instance.create_trimesh_collision()
