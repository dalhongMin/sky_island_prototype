extends CanvasLayer

## Restrained 2D HUD: growth stage, the care button, the demo time-of-day
## buttons, the Reset view control and one line of guidance. Two slim bars at
## the top and bottom of the portrait viewport, so the island silhouette and
## the whale stay clear.
##
## The HUD keeps no state of its own; it reads GameState every frame, and asks
## the camera for nothing — pressing Reset view only emits a signal.
##
## It also answers blocks_point(), which is how main.gd keeps a finger on a bar
## out of the world. Control nodes consume mouse presses themselves, but a real
## touch is not routed through the GUI the same way, so the exclusion has to be
## something the world can ask about directly.
##
## Text is English: no Korean font is bundled with the prototype (see README).

signal reset_view_requested()

const State := preload("res://scripts/state/sky_island_state.gd")

const PHASE_NAMES := ["Day", "Sunset", "Night"]

@onready var _top: Control = $Top
@onready var _bottom: Control = $Bottom
@onready var _stage_label: Label = $Top/Box/StageLabel
@onready var _progress: ProgressBar = $Top/Box/Progress
@onready var _hint: Label = $Top/Box/Hint
@onready var _tend_button: Button = $Bottom/Box/TendButton
@onready var _reset_view_button: Button = $Bottom/Box/ViewRow/ResetViewButton
@onready var _day_button: Button = $Bottom/Box/TimeRow/DayButton
@onready var _sunset_button: Button = $Bottom/Box/TimeRow/SunsetButton
@onready var _night_button: Button = $Bottom/Box/TimeRow/NightButton
@onready var _auto_button: Button = $Bottom/Box/TimeRow/AutoButton


func _ready() -> void:
	_tend_button.pressed.connect(_on_tend_pressed)
	_reset_view_button.pressed.connect(func() -> void: reset_view_requested.emit())
	_day_button.pressed.connect(_on_phase_pressed.bind(State.TimePhase.DAY))
	_sunset_button.pressed.connect(_on_phase_pressed.bind(State.TimePhase.SUNSET))
	_night_button.pressed.connect(_on_phase_pressed.bind(State.TimePhase.NIGHT))
	_auto_button.pressed.connect(_on_auto_pressed)
	_refresh()


## True when a viewport point belongs to the HUD. Everything on either bar is
## the HUD's, including its background: nothing there may orbit the camera or
## tend the island.
func blocks_point(point: Vector2) -> bool:
	return _top.get_global_rect().has_point(point) \
		or _bottom.get_global_rect().has_point(point)


func _process(_delta: float) -> void:
	_refresh()


func _on_tend_pressed() -> void:
	GameState.add_care(1.0)


func _on_phase_pressed(phase: int) -> void:
	GameState.set_time_phase(phase, true)


func _on_auto_pressed() -> void:
	GameState.auto_cycle = not GameState.auto_cycle


func _refresh() -> void:
	_stage_label.text = "ISLAND STAGE %d / %d  ·  %s" % [
		GameState.stage, State.MAX_STAGE, PHASE_NAMES[GameState.time_phase],
	]
	_progress.value = GameState.care_ratio()
	_hint.text = _hint_text()
	_tend_button.disabled = GameState.is_fully_grown() or GameState.is_growing()
	_tend_button.text = "FULLY GROWN" if GameState.is_fully_grown() else "TEND THE ISLAND"
	_auto_button.text = "Auto: on" if GameState.auto_cycle else "Auto: off"
	_day_button.button_pressed = GameState.time_phase == State.TimePhase.DAY
	_sunset_button.button_pressed = GameState.time_phase == State.TimePhase.SUNSET
	_night_button.button_pressed = GameState.time_phase == State.TimePhase.NIGHT


func _hint_text() -> String:
	if GameState.whale_active:
		return "A sky whale is passing by."
	if GameState.is_growing():
		return "The island is growing..."
	if not GameState.is_fully_grown():
		return "Tap the island to tend it, or use the button below."
	if not GameState.is_night():
		return "The island is grown. Switch to Night and watch the sky."
	if not GameState.first_whale_seen:
		return "Grown, and the sky is dark. Keep watching..."
	return "Quiet night. The whale may come around again."
