extends Node

## Authoritative prototype state (autoloaded as `GameState`).
##
## It owns the growth stage, care progress, time of day and the sky whale
## gate, and it knows nothing about nodes, meshes or UI. The 3D world and the
## HUD read these fields or listen to the signals below; they never keep their
## own copy of a value defined here.
##
## All numbers are demo pacing values for the visual prototype, not a long
## term economy.

signal stage_changed(stage: int)
signal care_progress_changed(ratio: float)
signal care_applied(accepted: bool)
signal growth_started(stage: int)
signal growth_finished(stage: int)
signal time_phase_changed(phase: int, blend_time: float)
signal whale_visit_started()
signal whale_visit_finished()

enum TimePhase { DAY, SUNSET, NIGHT }

const MAX_STAGE := 3
## Care units needed per stage; one button press / island tap is 1.0.
const CARE_PER_STAGE := 3.0
## How long the growth reveal animation owns the island (care is paused).
const GROWTH_TIME := 1.5
const PHASE_BLEND_TIME := 2.5
## Seconds spent in DAY / SUNSET / NIGHT before the automatic cycle moves on.
const PHASE_HOLD := [26.0, 9.0, 32.0]
## The first visit must be unmissable: at most a couple of seconds after the
## island is fully grown and the sky is dark.
const WHALE_FIRST_DELAY := 2.0
const WHALE_REPEAT_DELAY := 24.0
const WHALE_VISIT_TIME := 16.0

var stage: int = 0
var care_progress: float = 0.0
var growth_time_left: float = 0.0

## Time of day is stored as "blending from previous_phase to time_phase".
var time_phase: int = TimePhase.DAY
var previous_phase: int = TimePhase.DAY
var phase_blend: float = 1.0
var phase_blend_time: float = PHASE_BLEND_TIME
var auto_cycle: bool = true

var whale_active: bool = false
var whale_time_left: float = 0.0
var first_whale_seen: bool = false

var _hold_timer: float = 0.0
var _whale_wait: float = -1.0


func _process(delta: float) -> void:
	advance(delta)


## Single entry point for time, so tests can step the state deterministically.
func advance(delta: float) -> void:
	_advance_growth(delta)
	_advance_time(delta)
	_advance_whale(delta)


func reset() -> void:
	stage = 0
	care_progress = 0.0
	growth_time_left = 0.0
	time_phase = TimePhase.DAY
	previous_phase = TimePhase.DAY
	phase_blend = 1.0
	phase_blend_time = PHASE_BLEND_TIME
	auto_cycle = true
	whale_active = false
	whale_time_left = 0.0
	first_whale_seen = false
	_hold_timer = 0.0
	_whale_wait = -1.0


# --- care and growth -------------------------------------------------------

func care_ratio() -> float:
	if stage >= MAX_STAGE:
		return 1.0
	return clampf(care_progress / CARE_PER_STAGE, 0.0, 1.0)


func is_growing() -> bool:
	return growth_time_left > 0.0


func is_fully_grown() -> bool:
	return stage >= MAX_STAGE


## Adds care. Returns true when the input moved the progress forward, false
## when it was ignored (mid growth animation, or already fully grown).
func add_care(amount: float) -> bool:
	if amount <= 0.0 or is_growing() or is_fully_grown():
		care_applied.emit(false)
		return false
	care_progress += amount
	if care_progress >= CARE_PER_STAGE:
		care_progress = 0.0
		stage += 1
		growth_time_left = GROWTH_TIME
		care_applied.emit(true)
		care_progress_changed.emit(care_ratio())
		stage_changed.emit(stage)
		growth_started.emit(stage)
	else:
		care_applied.emit(true)
		care_progress_changed.emit(care_ratio())
	return true


## Jumps straight to a stage (demo / capture tooling), replaying the reveal.
func force_stage(target: int) -> void:
	target = clampi(target, 0, MAX_STAGE)
	while stage < target:
		stage += 1
		stage_changed.emit(stage)
		growth_started.emit(stage)
	care_progress = 0.0
	growth_time_left = GROWTH_TIME if stage > 0 else 0.0
	care_progress_changed.emit(care_ratio())


func _advance_growth(delta: float) -> void:
	if growth_time_left <= 0.0:
		return
	growth_time_left -= delta
	if growth_time_left <= 0.0:
		growth_time_left = 0.0
		growth_finished.emit(stage)


# --- time of day -----------------------------------------------------------

func is_night() -> bool:
	return time_phase == TimePhase.NIGHT


func set_time_phase(phase: int, manual: bool = false) -> void:
	phase = clampi(phase, 0, TimePhase.size() - 1)
	if manual:
		auto_cycle = false
	_hold_timer = 0.0
	if phase == time_phase and phase_blend >= 1.0:
		return
	previous_phase = time_phase
	time_phase = phase
	phase_blend = 0.0
	phase_blend_time = PHASE_BLEND_TIME
	time_phase_changed.emit(time_phase, phase_blend_time)


func next_phase() -> int:
	return (time_phase + 1) % TimePhase.size()


func _advance_time(delta: float) -> void:
	if phase_blend < 1.0:
		phase_blend = clampf(phase_blend + delta / maxf(phase_blend_time, 0.001), 0.0, 1.0)
		return
	if not auto_cycle:
		return
	_hold_timer += delta
	if _hold_timer >= float(PHASE_HOLD[time_phase]):
		var keep_auto := auto_cycle
		set_time_phase(next_phase())
		auto_cycle = keep_auto


# --- sky whale -------------------------------------------------------------

## The gate: a grown island, a dark sky, and no visit already in the air.
func can_whale_visit() -> bool:
	return stage >= MAX_STAGE and is_night() and not whale_active


## Seconds left before the next visit starts, or -1 when the gate is closed.
func whale_wait_left() -> float:
	return _whale_wait


func start_whale_visit() -> void:
	whale_active = true
	whale_time_left = WHALE_VISIT_TIME
	first_whale_seen = true
	_whale_wait = -1.0
	whale_visit_started.emit()


func _advance_whale(delta: float) -> void:
	if whale_active:
		whale_time_left -= delta
		if whale_time_left <= 0.0:
			whale_time_left = 0.0
			whale_active = false
			whale_visit_finished.emit()
		return
	if not can_whale_visit():
		_whale_wait = -1.0
		return
	if _whale_wait < 0.0:
		_whale_wait = WHALE_REPEAT_DELAY if first_whale_seen else WHALE_FIRST_DELAY
	_whale_wait -= delta
	if _whale_wait <= 0.0:
		start_whale_visit()


## 0 -> 1 progress of the current visit, used by the whale node to place itself
## on its flight path without keeping a second timer.
func whale_progress() -> float:
	if not whale_active:
		return 0.0
	return clampf(1.0 - whale_time_left / WHALE_VISIT_TIME, 0.0, 1.0)
