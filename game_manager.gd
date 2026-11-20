extends Node

@export var trainer_scene: PackedScene

var trainer: Node

@onready var main_menu: Control = $MainMenu


func _ready() -> void:
	main_menu.model_selected.connect(start_quiz)


func start_quiz(model_scene: PackedScene) -> void:

	clear_trainer()
	trainer = trainer_scene.instantiate()
	trainer.name = "Trainer"
	trainer.set("selected_model", model_scene)
	trainer.connect("back_requested", show_menu)
	main_menu.hide()
	add_child(trainer)


func show_menu() -> void:
	clear_trainer()
	main_menu.show()


func clear_trainer() -> void:
	if is_instance_valid(trainer):
		remove_child(trainer)
		trainer.queue_free()
	trainer = null


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(trainer) and event.is_action_pressed("ui_cancel"):
		show_menu()
		get_viewport().set_input_as_handled()
