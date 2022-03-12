
require "include/default@exerro:mesh-build:main"

tasks.setup.config {
	from = MESH_ROOT_PATH / "src",
	to = MESH_ROOT_PATH / "build/src",
}

tasks.check.config {
	include = MESH_ROOT_PATH / "build/src/**.lua",
}

tasks.build.config {
	require_path = MESH_ROOT_PATH / "build/src",
	entry_path = MESH_ROOT_PATH / "build/src/main.lua",
	output_path = MESH_ROOT_PATH / "build/main.lua",
}

tasks.run.config {
	script_path = MESH_ROOT_PATH / "build/main.lua"
}

tasks.clean.config {
	path = MESH_ROOT_PATH / "build"
}
