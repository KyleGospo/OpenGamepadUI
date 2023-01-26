@tool
extends VBoxContainer

signal drag_ended(value_changed: bool)
signal drag_started()
signal changed()
signal value_changed(value: float)

@export var text: String = "Setting"

@export var value: float = 0:
	set(v):
		value = v
		if label_value:
			label_value.text = str(v)
		if slider:
			slider.value = v
		notify_property_list_changed()
	
@export var min_value: float = 0
@export var max_value: float = 100
@export var step: float = 1
@export var tick_count := 0

@onready var label := $%Label as Label
@onready var label_value := $%LabelValue as Label
@onready var slider := $%HSlider as HSlider

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	label.text = text
	label_value.text = str(slider.value)
	slider.value_changed.connect(_on_value_changed)
	slider.value = value
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.tick_count = tick_count
	
	# Wire up all slider signals
	var on_drag_ended := func(changed: bool):
		drag_ended.emit(changed)
	slider.drag_ended.connect(on_drag_ended)
	var on_drag_started := func():
		drag_started.emit()
	slider.drag_ended.connect(on_drag_started)
	var on_changed := func():
		changed.emit()
	slider.changed.connect(on_changed)


func _on_value_changed(v: float) -> void:
	label_value.text = str(v)
	value_changed.emit(v)
