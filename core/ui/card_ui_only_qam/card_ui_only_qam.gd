extends Control

const Gamescope := preload("res://core/global/gamescope.tres")
const InputManager := preload("res://core/global/input_manager.tres")
const StateMachine := preload("res://assets/state/state_machines/global_state_machine.tres")
const SettingsManager := preload("res://core/global/settings_manager.tres")

var qam_state = load("res://assets/state/states/quick_access_menu.tres")
var settings_state = load("res://assets/state/states/settings.tres")
var home_state = load("res://assets/state/states/home.tres")
var launch_manager := load("res://core/global/launch_manager.tres") as LaunchManager

var args := OS.get_cmdline_user_args()
var cmdargs := OS.get_cmdline_args()
var display := Gamescope.XWAYLAND.OGUI
var game_running: bool = false
var qam_window_id: int
var pid: int = OS.get_process_id()
var shared_thread: SharedThread
var underlay_log: FileAccess
var underlay_process: InteractiveProcess
var underlay_window_id: int

@onready var quick_access_menu := $%QuickAccessMenu
@onready var settings_menu := $%SettingsMenu

var logger := Log.get_logger("Main-OnlyQAM", Log.LEVEL.INFO)

## Sets up PluginManager for QAM only mode.
func _init():
	# Back button wont close windows without this InputManager prevents poping the last state.
	StateMachine.push_state(home_state)
	launch_manager.should_manage_overlay = false
	var plugin_loader := load("res://core/global/plugin_loader.tres") as PluginLoader
	var filters : Array[Callable] = [plugin_loader.filter_by_tag.bind("qam")]
	plugin_loader.set_plugin_filters(filters)
	var plugin_manager_scene := load("res://core/systems/plugin/plugin_manager.tscn") as PackedScene
	var plugin_manager := plugin_manager_scene.instantiate()
	add_child(plugin_manager)


## Starts the --only-qam/--qam-only session.
func _ready() -> void:
	# Workaround old versions that don't pass launch args via update pack
	# TODO: Parse the parent PID's CLI args and use those instead.
	if "--skip-update-pack" in cmdargs and args.size() == 0:
		logger.warn("Launched via update pack without arguments! Falling back to default.")
		args = ["steam", "-gamepadui", "-steamos3", "-steampal", "-steamdeck"]

	# Set the theme if one was set
	var theme_path := SettingsManager.get_value("general", "theme", "") as String
	if theme_path == "":
		logger.debug("No theme set. Using default theme.")
	if theme_path != "":
		logger.debug("Setting theme to: " + theme_path)
		var loaded_theme = load(theme_path)
		if loaded_theme != null:
			theme = loaded_theme
		else:
			logger.debug("Unable to load theme")

	# Set window size to native resolution
	var screen_size : Vector2i = DisplayServer.screen_get_size()
	var window : Window = get_window()
	window.set_size(screen_size)

	# Set up the session
	_setup_qam_only(args)
	launch_manager.app_switched.connect(_on_app_switched)

## Finds needed PID's and global vars, Starts the user defined program in the sandbox.
func _setup_qam_only(args: Array) -> void:
	qam_window_id = Gamescope.get_window_id(pid, display)
	qam_state.state_entered.connect(_on_window_open)
	qam_state.state_exited.connect(_on_window_closed)
	settings_state.state_entered.connect(_on_window_open)
	settings_state.state_exited.connect(_on_window_closed)

	InputManager._set_intercept(ManagedGamepad.INTERCEPT_MODE.PASS_QAM)

	# Don't crash if we're not launching another program.
	if args == []:
		logger.warn("only-qam mode started with no launcher arguments.")
		return

	if "steam" in args:
		_start_steam_process(args)
	else:
		var log_path := OS.get_environment("HOME") + "/.underlay-stdout.log"
		_start_underlay_process(args, log_path)

	# Establish overlay focus in gamescope.
	Gamescope.set_overlay(qam_window_id, 1, display)

	# Remove unneeded/conflicting elements from default menues
	var qam_remove_list: PackedStringArray = ["PerformanceCard", "NotifyButton", "HelpButton", "VolumeSlider", "BrightnessSlider", "PerGameToggle"]
	_run_child_killer(qam_remove_list, quick_access_menu)
	var settings_remove_list: PackedStringArray = ["NetworkButton", "BluetoothButton", "AudioButton"]
	_run_child_killer(settings_remove_list, settings_menu)


func _run_child_killer(remove_list: PackedStringArray, parent:Node) -> void:
	var child_count := parent.get_child_count()
	var to_remove_list := []

	for child_idx in child_count:
		var child = parent.get_child(child_idx)
		logger.debug("Checking if " + child.name + " in remove list...")
		if child.name in remove_list:
			logger.debug(child.name + " queued for removal!")
			to_remove_list.append(child)
			continue

		logger.debug(child.name + " is not a node we are looking for.")
		var grandchild_count := child.get_child_count()
		if grandchild_count > 0:
			logger.debug("Checking " + child.name + "'s children...")
			_run_child_killer(remove_list, child)

	for child in to_remove_list:
		logger.debug("Removing " + child.name)
		child.queue_free()


func _start_steam_process(args: Array) -> void:
	# Setup steam
	var underlay_log_path = OS.get_environment("HOME") + "/.steam-stdout.log"
	_start_underlay_process(args, underlay_log_path)

	# Look for steam and save window ID
	while not underlay_window_id:
		# Find Steam in the display tree
		var root_win_id := Gamescope.get_root_window_id(display)
		var all_windows := Gamescope.get_all_windows(root_win_id, display)
		for window in all_windows:
			if window == qam_window_id:
				continue
			if Gamescope.has_xprop(window, "STEAM_OVERLAY", display):
				underlay_window_id = window
				logger.debug("Found steam! " + str(underlay_window_id))
				break
		# Wait a bit to reduce cpu load.
		OS.delay_msec(1000)

	# Start timer to check if steam has exited.
	var exit_timer := Timer.new()
	exit_timer.set_one_shot(false)
	exit_timer.set_timer_process_callback(Timer.TIMER_PROCESS_IDLE)
	exit_timer.timeout.connect(_check_exit)
	add_child(exit_timer)
	exit_timer.start()


func _start_underlay_process(args: Array, log_path: String) -> void:
	# Start the shared thread we use for logging.
	shared_thread = SharedThread.new()
	shared_thread.start()

	# Setup logging
	underlay_log = FileAccess.open(log_path, FileAccess.WRITE)
	var error := underlay_log.get_open_error()
	if error != OK:
		logger.warn("Got error opening log file.")
	else:
		logger.info("Started logging underlay process at " + log_path)
	var command: String = args[0]
	args.remove_at(0)
	underlay_process = InteractiveProcess.new(command, args)
	if underlay_process.start() != OK:
		logger.error("Failed to start child process.")
		return
	var logger_func := func(delta: float):
		underlay_process.output_to_log_file(underlay_log)
	shared_thread.add_process(logger_func)


## Called when "qam_state" is entered.
func _on_window_open(_from: State) -> void:
	if _from:
		logger.info("_on_qam_open state: " + _from.name)
	InputManager._set_intercept(ManagedGamepad.INTERCEPT_MODE.ALL)
	if game_running:
		Gamescope.set_overlay(qam_window_id, 1, display)
		Gamescope.set_overlay(underlay_window_id, 0, display)


## Called when "qam_state" is exited.
func _on_window_closed(_to: State) -> void:
	if _to:
		logger.info("_on_qam_closed state: " + _to.name)
	InputManager._set_intercept(ManagedGamepad.INTERCEPT_MODE.PASS_QAM)
	if game_running:
		Gamescope.set_overlay(qam_window_id, 0, display)
		Gamescope.set_overlay(underlay_window_id, 1, display)


func _on_app_switched(_from: RunningApp, to: RunningApp) -> void:
	if to == null:
		# Establish overlay focus in gamescope.
		Gamescope.set_overlay(qam_window_id, 1, display)
		Gamescope.set_overlay(underlay_window_id, 0, display)
		game_running = false
		return
	Gamescope.set_overlay(qam_window_id, 0, display)
	Gamescope.set_overlay(underlay_window_id, 1, display)
	game_running = true


## Verifies steam is still running by checking for the steam overlay, closes otherwise.
func _check_exit() -> void:
	if Gamescope.has_xprop(underlay_window_id, "STEAM_OVERLAY", display):
		return
	logger.debug("Steam closed. Shutting down.")
	get_tree().quit()
