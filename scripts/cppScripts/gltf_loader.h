#ifndef GLTF_LOADER_H
#define GLTF_LOADER_H

#include "core/io/resource_loader.h"

// All custom loaders must inherit from ResourceFormatLoader.
class GltfLoader : public ResourceFormatLoader {
	GDCLASS(GltfLoader, ResourceFormatLoader);

public:
	// This function returns the file extensions this loader can handle.
	virtual PackedStringArray _get_recognized_extensions() const override;

	// This function tells Godot which resource type the loader produces.
	virtual bool _handles_type(const String &p_type) const override;

	// This is the core loading function. It will use Godot's built-in loader.
	virtual Variant _load(const String &p_path, const String &p_original_path, bool p_use_sub_threads, int32_t p_cache_mode) const override;
};

#endif // GLTF_LOADER_H
