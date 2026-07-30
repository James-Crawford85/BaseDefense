class_name Targeting
## Shared auto-targeting used by the player and turrets.

static func nearest_enemy(tree: SceneTree, from: Vector2, max_range: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_range * max_range
	for e in tree.get_nodes_in_group("enemies"):
		var n := e as Node2D
		if n == null:
			continue
		var d := n.global_position.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = n
	return best
