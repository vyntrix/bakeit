@tool
extends EditorPlugin

const BUTTON_NAME = "🍞"
const COMPILED_MESH_NAME = "CompiledMesh"

var button_bake_it: Button
var toolbar_container: HBoxContainer

func find_node_by_name(base_node: Node, name = "Node3DEditor") -> Node:
	if base_node.name.contains(name):
		return base_node

	for child in base_node.get_children():
		var result = find_node_by_name(child, name)
		if result:
			return result

	return null

func _enter_tree() -> void:
	toolbar_container = find_node_by_name(find_node_by_name(get_editor_interface().get_base_control(), "Node3DEditor"), "HBoxContainer")
	if (!toolbar_container):
		return

	button_bake_it = Button.new()
	button_bake_it.text = BUTTON_NAME
	button_bake_it.tooltip_text = "Build CSG Meshes, Unwrap Model, Build Occluder"
	button_bake_it.pressed.connect(_on_button_pressed)
	toolbar_container.add_child(button_bake_it)

func _exit_tree() -> void:
	if button_bake_it:
		button_bake_it.queue_free()

func _on_button_pressed() -> void:
	print_rich("[BakeIt] [color=green]Started - Ensure game is closed when baking![/color]")
	var node_root = get_editor_interface().get_edited_scene_root()

	var node_csg: CSGCombiner3D
	var node_occluder: OccluderInstance3D

	for child in node_root.get_children():
		if (child is CSGCombiner3D):
			node_csg = child
			continue

		if (child is OccluderInstance3D):
			node_occluder = child
			continue

		if (child.name.contains(COMPILED_MESH_NAME)): \
			child.queue_free()

	if (!node_csg):
		print_rich("[BakeIt] [color=red]Failed to find CSG Combiner for Baking[/color]")
		return

	if (node_occluder):
		node_occluder.queue_free()
		print_rich("[BakeIt] [color=yellow]Removed old NodeOccluder3D[/color]")

	if (node_csg.use_collision):
		node_csg.use_collision = false
		print_rich("[BakeIt] [color=yellow]Turned off Collision for CSG Mesh, not necessary.[/color]")

	var meshes = node_csg.bake_static_mesh()
	var instance = MeshInstance3D.new()
	node_root.add_child(instance)
	instance.mesh = meshes

	var old_mesh = instance.mesh
	var new_mesh = ArrayMesh.new()
	for surface_id in range(old_mesh.get_surface_count()):
		new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, old_mesh.surface_get_arrays(surface_id))
		var old_mat = old_mesh.surface_get_material(surface_id)
		new_mesh.surface_set_material(surface_id, old_mat)
	new_mesh.lightmap_unwrap(instance.global_transform, 0.4)

	instance.create_trimesh_collision()
	instance.mesh = new_mesh
	instance.owner = node_root
	instance.name = COMPILED_MESH_NAME

	var static_body = StaticBody3D.new()
	node_root.add_child(static_body)
	static_body.owner = node_root
	static_body.name = "StaticBody3D"
	static_body.reparent(instance)
	static_body.collision_layer = 3

	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = instance.mesh.create_trimesh_shape()
	collision_shape.name = "CollisionShape3D"

	node_root.add_child(collision_shape)
	collision_shape.owner = node_root
	collision_shape.reparent(static_body)

	get_editor_interface().mark_scene_as_unsaved()

	node_occluder = OccluderInstance3D.new()
	node_root.add_child(node_occluder)
	node_occluder.owner = node_root
	node_occluder.name = "OccluderInstance3D"

	if (!node_occluder):
		print_rich("[BakeIt] [color=red]Failed to find Occluder for BakeIt[/color]")
		return

	var occluder = create_occluder_from_mesh(instance.mesh)
	var occ_path = node_root.scene_file_path.replace(".tscn", ".occ")
	if (FileAccess.file_exists(occ_path)):
		DirAccess.remove_absolute(occ_path)

	var result = ResourceSaver.save(occluder, occ_path)
	if result == OK:
		print_rich("[BakeIt] [color=green]Occluder saved at: [/color][color=yellow]" + occ_path + "[/color]")
		node_occluder.occluder = load(occ_path)
	else:
		print_rich("[BakeIt] [color=red]Failed to save occluder![/color]")

	get_editor_interface().mark_scene_as_unsaved()
	print_rich("[BakeIt] [color=green]Complete[/color]")

func create_occluder_from_mesh(mesh: Mesh) -> ArrayOccluder3D:
	var occluder = ArrayOccluder3D.new()
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()
	var vertex_offset = 0

	for surface_index in range(mesh.get_surface_count()):
		var arrays = mesh.surface_get_arrays(surface_index)
		var surface_vertices = arrays[Mesh.ARRAY_VERTEX]
		var surface_indices = arrays[Mesh.ARRAY_INDEX]

		vertices.append_array(surface_vertices)
		for index in surface_indices:
			indices.append(index + vertex_offset)

		vertex_offset += surface_vertices.size()

	occluder.set_arrays(vertices, indices)
	return occluder
