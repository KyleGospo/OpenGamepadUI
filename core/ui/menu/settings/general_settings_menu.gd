extends Control

@onready var max_recent_slider := $%MaxRecentAppsSlider


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var max_recent := SettingsManager.get_value("general.home", "max_home_items", 10)
	max_recent_slider.value = max_recent
