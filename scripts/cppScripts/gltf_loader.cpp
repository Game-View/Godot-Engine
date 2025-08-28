#include "gltf_loader.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"

PackedStringArray GltfLoader::_get_recognized_extensions() const {
	// Our loader will only recognize the glTF file extension.
	return PackedStringArray("gltf");
}

bool GltfLoader::_handles_type(const String &p_type) const {
	// This loader will return a Mesh resource.
	// We handle it this way because a glTF file can contain many resources.
	// This approach focuses on the primary Mesh.
	return p_type == "Mesh";
}

Variant GltfLoader::_load(const String &p_path, const String &p_original_path, bool p_use_sub_threads, int32_t p_cache_mode) const {
	// We use Godot's internal loader to handle the complex parsing of the glTF file.
	// This is the most efficient and robust way to load the data.
	// You could add your own pre-processing logic here before calling the loader.
	
	// A new, empty loader to prevent a recursive loop with our own loader.
	Ref<ResourceLoader> new_loader = ResourceLoader::get_singleton();
	
	// The key to loading a file created at runtime is simply to point
	// Godot's existing ResourceLoader at its file path.
	Variant loaded_resource = new_loader->load(p_path);

	// The `load()` function handles all the parsing.
	if (loaded_resource.is_null()) {
		// If loading fails for any reason, print an error and return an error code.
		ERR_PRINT("Failed to load glTF file: " + p_path);
		return ERR_FILE_CANT_OPEN;
	}
	
	// Now you can work with the loaded resource (e.g., convert to a Mesh).
	// For this simple example, we assume it's a Mesh.
	Ref<Mesh> mesh = loaded_resource;
	
	return mesh;
}