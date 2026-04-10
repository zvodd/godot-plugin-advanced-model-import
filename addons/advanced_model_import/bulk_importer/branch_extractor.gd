@tool
class_name BranchExtractor
extends RefCounted

static func extract_branches_from_file(
	file_path: String,
	destination_dir: String,
	target_node_name: String,
	apply_parent_scale: bool = true,
	zero_position: bool = true
) -> Error:

	# 1. Load the source file
	var packed_scene: PackedScene = ResourceLoader.load(
		file_path,
		"",
		ResourceLoader.CacheMode.CACHE_MODE_IGNORE_DEEP
	) as PackedScene

	if !is_instance_valid(packed_scene):
		printerr("BranchExtractor: Could not load file %s" % file_path)
		return Error.ERR_FILE_CANT_OPEN

	var original_root: Node = packed_scene.instantiate()
	if !is_instance_valid(original_root):
		return Error.ERR_FILE_CANT_OPEN

	# 2. Identify the node containing the branches to be extracted
	var target_node: Node = original_root
	if !target_node_name.is_empty():
		target_node = original_root.find_child(target_node_name, true, false)
		if !is_instance_valid(target_node):
			printerr("BranchExtractor: Node '%s' not found." % target_node_name)
			original_root.free()
			return Error.ERR_DOES_NOT_EXIST

	print("BranchExtractor: Processing children of '%s'" % target_node.name)


	# 3. Iterate through all children, extracting each into its own PackedScene
	while target_node.get_child_count() > 0:
		var child = target_node.get_child(0)
		var child_name = child.name

		# Capture the state before detachment
		var saved_global_transform = Transform3D()
		if child is Node3D:
			saved_global_transform = child.global_transform

		if child is Node3D:
			# Restore world transformation state
			child.transform = saved_global_transform

			# OPTIONAL: Apply Scale
			if apply_parent_scale:
				# Apply the accumulated scale from the hierarchy we just left
				child.scale *= saved_global_transform.basis.get_scale()

			# OPTIONAL: Zero Position
			if zero_position:
				# Reset global position to origin (0,0,0) while preserving rotation/scale
				child.position = Vector3.ZERO

		# Detach from the original scene tree
		target_node.remove_child(child)

		# Recursively set the owner of the child and its descendants to the child itself.
		# This is required for PackedScene.pack() to recognize and save the internal hierarchy.
		_set_owner_recursive(child, child)

		# 4. Pack the individual branch
		var branch_scene: PackedScene = PackedScene.new()
		var pack_result: Error = branch_scene.pack(child)

		if pack_result != Error.OK:
			printerr("BranchExtractor: Failed to pack branch '%s': %s" % [child_name, error_string(pack_result)])
			child.free()
			continue

		# 5. Save the new PackedScene to disk
		var filename = child_name.validate_filename()
		var save_path: String = destination_dir + "/" + filename + ".tscn"

		var save_result: Error = ResourceSaver.save(branch_scene, save_path)

		if save_result != Error.OK:
			printerr("BranchExtractor: Failed to save '%s': %s" % [save_path, error_string(save_result)])
		else:
			print("BranchExtractor: Successfully saved %s" % save_path)

		# Free the child node now that it is saved and detached from the original root
		child.free()

	# Clean up the original instantiated scene
	original_root.free()
	return Error.OK

static func _set_owner_recursive(node: Node, new_owner: Node) -> void:
	# The root of a PackedScene cannot be its own owner.
	# Only descendants need the owner set to the root.
	if node != new_owner:
		node.owner = new_owner
	else:
		node.owner = null

	for child: Node in node.get_children():
		_set_owner_recursive(child, new_owner)
