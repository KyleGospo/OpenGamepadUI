extends Control

var BoxArtManager := load("res://core/global/boxart_manager.tres") as BoxArtManager
var LibraryManager := load("res://core/global/library_manager.tres") as LibraryManager
var state_machine := preload("res://assets/state/state_machines/global_state_machine.tres") as StateMachine
var library_state := preload("res://assets/state/states/library.tres") as State
var launcher_state := preload("res://assets/state/states/game_launcher.tres") as State
var osk_state := preload("res://assets/state/states/osk.tres") as State
var poster_scene: PackedScene = preload("res://core/ui/components/poster.tscn")
var _library := {}
var _current_selection := {}

@onready var global_search: SearchBar = get_tree().get_first_node_in_group("global_search_bar")
@onready var tab_container: TabContainer = $%TabContainer
@onready var all_games_grid: HFlowContainer = $%AllGamesGrid
@onready var installed_games_grid: HFlowContainer = $%InstalledGrid


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	tab_container.tab_changed.connect(_on_tab_container_tab_changed)
	library_state.state_entered.connect(_on_state_entered)
	LibraryManager.library_reloaded.connect(_on_library_reloaded)
	LibraryManager.library_registered.connect(_on_library_registered)
	LibraryManager.library_unregistered.connect(_on_library_unregistered)
	if global_search != null:
		global_search.search_submitted.connect(_on_search)


func _on_state_entered(_from: State):
	# Focus the first entry on state change
	_on_tab_container_tab_changed(tab_container.current_tab)


func _on_library_unregistered(_library_id: String) -> void:
	_on_library_reloaded(false)


func _on_library_registered(_library: Library) -> void:
	if not LibraryManager.is_initialized():
		return
	_on_library_reloaded(false)


# Handle searches
func _on_search(text: String):
	if not state_machine.current_state() in [library_state, osk_state]:
		return
	text = text.to_lower()
	
	# If the text is empty, set all items to visible
	if text == "":
		for tab_num in _library:
			for item_name in _library[tab_num]:
				var item: Control = _library[tab_num][item_name]
				item.visible = true
		return
		
	# TODO: Fuzzy searching?
	for tab_num in _library:
		for item_name in _library[tab_num]:
			var item: Control = _library[tab_num][item_name]
			if (item_name as String).to_lower().contains(text):
				item.visible = true
				continue
			item.visible = false


func _on_library_reloaded(_first_load: bool) -> void:
	# Clear our old library entries
	# TODO: Make this better
	for child in all_games_grid.get_children():
		#all_games_grid.remove_child(child)
		child.queue_free()
	for child in installed_games_grid.get_children():
		#all_games_grid.remove_child(child)
		child.queue_free()
	
	# Load our library entries and add them to all games
	var available := LibraryManager.get_library_items()
	_populate_grid(all_games_grid, available, 1)

	var modifiers: Array[Callable] = [
		LibraryManager.filter_installed,
		LibraryManager.sort_by_name,
	]
	var installed := LibraryManager.get_library_items(modifiers)
	_populate_grid(installed_games_grid, installed, 0)


# Populates the given grid with library items
func _populate_grid(grid: HFlowContainer, library_items: Array, tab_num: int):
	for i in library_items:
		var item: LibraryItem = i
		
		# Build a poster for each library item
		var poster: TextureButton = poster_scene.instantiate()
		poster.library_item = item # Do we need this?
		poster.layout = poster.LAYOUT_MODE.PORTRAIT
		poster.text = item.name
		
		# Get the box art for the library item
		poster.texture_normal = await BoxArtManager.get_boxart_or_placeholder(
			item, 
			BoxArtProvider.LAYOUT.GRID_PORTRAIT, 
		)
		
		# Listen for button presses and pass the library item with the state
		var on_button_up := func():
			launcher_state.data = {"item": item}
			state_machine.push_state(launcher_state)
		poster.button_up.connect(on_button_up)
		
		# Listen for focus changes to keep track of our current selection
		# between state changes.
		poster.focus_entered.connect(_on_focus_updated.bind(poster, tab_num))
		
		# Listen for library item removed events
		var on_removed := func():
			if tab_num in _current_selection and _current_selection[tab_num] == poster:
				_current_selection.erase(tab_num)
			poster.queue_free()
			_library[tab_num].erase(item.name)
		item.removed_from_library.connect(on_removed)
		
		# Add the poster to the grid
		grid.add_child(poster)
		
		# Keep track of all the library items so we can search them.
		if not tab_num in _library:
			_library[tab_num] = {}
		_library[tab_num][item.name] = poster


func _on_focus_updated(poster: TextureButton, tab: int) -> void:
	_current_selection[tab] = poster


func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	var num_tabs: int = tab_container.get_tab_count()
	var next_tab: int = tab_container.current_tab
	if event.is_action_pressed("ogui_tab_right"):
		next_tab += 1
	if event.is_action_pressed("ogui_tab_left"):
		next_tab -= 1
	
	if next_tab < 0:
		next_tab = num_tabs - 1
	if next_tab + 1 > num_tabs:
		next_tab = 0
	tab_container.current_tab = next_tab


func _on_tab_container_tab_changed(tab: int) -> void:
	# Get the child container to grab focus
	var container: ScrollContainer = tab_container.get_child(tab)
	var grid: HFlowContainer = container.get_child(0).get_child(0)
	
	# If we had a previous selection, grab focus on that.
	if tab in _current_selection:
		var poster: TextureButton = _current_selection[tab]
		if poster.visible:
			poster.grab_focus.call_deferred()
			return
		# If the selection is no longer visible, clear it from our current selection
		_current_selection.erase(tab)
	
	# Otherwise, focus the first entry on tab change
	for child in grid.get_children():
		if child.visible:
			child.grab_focus.call_deferred()
			break
