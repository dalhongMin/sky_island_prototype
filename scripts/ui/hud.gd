extends CanvasLayer

## Restrained 2D HUD: growth stage, the care button, the demo time-of-day
## buttons and one line of guidance. Two slim bars at the top and bottom of
## the portrait viewport, so the island silhouette and the whale stay clear.
##
## The HUD keeps no state of its own; it reads GameState every frame.
##
## Text is English: no Korean font is bundled with the prototype (see README).

const State := preload("res://scripts/state/sky_island_state.gd")

const PHASE_NAMES := ["Day", "Sunset", "Night"]

@onready var _stage_label: Label = $Top/Box/StageLabel
@onready var _progress: ProgressBar = $Top/Box/Progress
@onready var _hint: Label = $Top/Box/Hint
@onready var _tend_button: Button = $Bottom/Box/TendButton
@onready var _day_button: Button = $Bottom/Box/TimeRow/DayButton
@onready var _sunset_button: Button = $Bottom/Box/TimeRow/SunsetButton
@onready var _night_button: Button = $Bottom/Box/TimeRow/NightButton
@onready var _auto_button: Button = $Bottom/Box/TimeRow/AutoButton


func _ready() -> void:
	_tend_button.pressed.connect(_on_tend_pressed)
	_day_button.pressed.connect(_on_phase_pressed.bind(State.TimePhase.DAY))
	_sunset_button.pressed.connect(_on_phase_pressed.bind(State.TimePhase.SUNSET))
	_night_button.pressed.connect(_on_phase_pressed.bind(State.TimePhase.NIGHT))
	_auto_button.pressed.connect(_on_auto_pressed)
	_refresh()


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
		return "Tend the island, or stroke it directly. Drag the sky to look around."
	if not GameState.is_night():
		return "The island is grown. Switch to Night and watch the sky."
	if not GameState.first_whale_seen:
		return "Grown, and the sky is dark. Keep watching..."
	return "Quiet night. The whale may come around again."
