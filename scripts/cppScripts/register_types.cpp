#include "gltf_loader.h"
#include "core/io/resource_loader.h"

// This function is the entry point to register your custom types with Godot.
void register_my_module_types() {
	// Register the custom loader class.
	ClassDB::register_class<GltfLoader>();

	// Add the loader to the engine's list of resource format loaders.
	ResourceLoader::add_resource_format_loader(memnew(GltfLoader));
}

// This function unregisters the types when the module is unloaded.
void unregister_my_module_types() {
	ResourceLoader::remove_resource_format_loader(memnew(GltfLoader));
}