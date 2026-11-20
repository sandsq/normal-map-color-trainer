@tool
extends Control

signal model_selected(model_scene: PackedScene)

@export var models: Array[PackedScene] = []

@onready var model_buttons: VBoxContainer = %ModelButtons


func _ready() -> void:
	for model_scene in models:
		if model_scene == null:
			continue

		var button := Button.new()
		button.text = model_scene.resource_path.get_file().get_basename().capitalize()
		button.pressed.connect(_select_model.bind(model_scene))
		model_buttons.add_child(button)


func _select_model(model_scene: PackedScene) -> void:
	model_selected.emit(model_scene)
