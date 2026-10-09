function data()
return {
	inputs = {
		{ key = "boundsMin", type = "Point", displayName = "Bounds Min", desc = "Minimum Values of the Points" },
		{ key = "boundsMax", type = "Point", displayName = "Bounds Max", desc = "Maximum values of the Points" },
		{ key = "baseProbability", type = "Float", displayName = "Tributary Prob.", desc = "Multiplier for the probability of tributaries (streams)", optional = true },
		{ key = "baseCurvature", type = "Float", displayName = "Base Curvature", desc = "Random direction change per coarse segment (radians / 15)", optional = true },
		{ key = "riverAmountFactor", type = "Float", displayName = "River Amount Factor", desc = "Multiplier Factor for Amount of River Spawns", optional = true },
		{ key = "minLength", type = "Float", displayName = "Min Length", desc = "Minimal Length of Rivers for it not being Rejected", optional = true },
		{ key = "trunkWidth", type = "Float", displayName = "Trunk Width", desc = "Width multiplier for large rivers (small streams keep their natural width)", optional = true },
		{ key = "meander", type = "Float", displayName = "Meander", desc = "Meander strength (0 straight .. ~1.2 looping)", optional = true },
		{ key = "greatRiver", type = "Float", displayName = "Great River", desc = "1 = grow one river across the whole map from the coast side", optional = true },
		{ key = "deltas", type = "Float", displayName = "Delta Chance", desc = "Chance [0,1] that a large river reaching water splits into a delta", optional = true },
		{ key = "riverWeight", type = "Map", displayName = "River Weight", desc = "Vanilla semantics: starts where < 0, prefers higher values, impassable >= 1.2", optional = true },
		{ key = "riverWidth", type = "Map", displayName = "River Width", desc = "Spatial width multiplier", optional = true },
		{ key = "coastT", type = "Map", displayName = "Coast Coordinate", desc = "0 at the coast edge .. 1 at the far edge (great river direction)", optional = true },
		{ key = "water", type = "Map", displayName = "Water Mask", desc = "1 in standing water (ocean/lakes): estuaries and deltas", optional = true },
		{ key = "flatness", type = "Map", displayName = "Flatness", desc = "1 in flat lowland, 0 in rough terrain (meander strength)", optional = true },
	},
	outputs = {
		{ key = "points", type = "PointCloud", displayName = "Points", desc = "Coordinates of the River" },
		{ key = "widths", type = "PointCloud", displayName = "Widths", desc = "Left/right Width of the River Relative to the Center" },
		{ key = "depthsTangent", type = "PointCloud", displayName = "Depth & Slope", desc = "Depth of the River and Slope of the river Bed" },
		{ key = "tangents", type = "PointCloud", displayName = "Direction", desc = "Tangents of the River at the Point" },
		{ key = "widthTangents", type = "PointCloud", displayName = "Width tangen", desc = "Tangent of the river Shore" },
	},
	params = {
		{ key = "maxOrder", name = "Max Order", config = { min = 1, max = 10, defaultValue = 6, step = 1 }, type = "Float" },
		{ key = "segmentLength", name = "Segment Length", config = { min = 500, max = 5000, defaultValue = 1000, step = 100 }, type = "Float" },
		{ key = "minDist", name = "Min Distance", config = { min = 1, max = 10, defaultValue = 2, step = 1 }, type = "Float" },
	},
	def = {
		displayName = "Natural River Network (Custom Terrain)",
		category = "map_ridge_river",
		description = "River network with natural meanders, discharge-based widths, estuaries, deltas and an optional great river. Outputs feed the native River Map node.",
		order = 1531,
	},
	applyScript = {
		fileName = "custom_terrain_experimental::/gui/node_editor/custom_terrain_rivers.script@riverPoints.applyFn",
		params = {}
	},
}
end
