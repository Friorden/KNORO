extends Node
## Global access to the running campaign. Screens read Game.state and call
## Game.changed.emit() after they change it so the HUD refreshes.

signal changed
signal quest_done(info: Dictionary)     # {id, title, kind, changes}

var state: GameState
var seed := 0
var chosen_kingdom := "red"
var demo_end_shown := false


func _ready() -> void:
	randomize()
	seed = randi() % 100000


func start_campaign(kid: String, champ: Champion) -> void:
	state = GameState.new()
	state.new_game(seed, kid, champ)
	demo_end_shown = false
	changed.emit()


func touch() -> void:
	if state != null and state.alive:
		for q in state.check_quests():
			quest_done.emit(q)
	changed.emit()
