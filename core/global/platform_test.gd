extends GutTest


# Test detecting overlay mode from the given command-line arguments
func test_is_overlay_mode() -> void:
	var args := PackedStringArray(["opengamepadui", "--accessibility", "disabled"])
	assert_false(Platform.is_overlay_mode(args), "should not detect overlay mode")

	args = PackedStringArray(["opengamepadui", "--overlay-mode", "--", "steam"])
	assert_true(Platform.is_overlay_mode(args), "should detect overlay mode")


# Test detecting overlay mode from the deprecated command-line arguments
func test_is_overlay_mode_deprecated() -> void:
	var args := PackedStringArray(["opengamepadui", "--only-qam"])
	assert_true(Platform.is_overlay_mode(args), "should detect overlay mode from --only-qam")

	args = PackedStringArray(["opengamepadui", "--qam-only"])
	assert_true(Platform.is_overlay_mode(args), "should detect overlay mode from --qam-only")
