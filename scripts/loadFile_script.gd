extends Control

@warning_ignore("unused_signal")
signal fileChosen(String)
@export var ui: CanvasLayer
@onready var dialog = get_node("HBoxContainer/SubViewportContainer/SubViewport/FileDialog")
@onready var loadfile = get_node("HBoxContainer/SubViewportContainer/SubViewport/LoadFile")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	get_tree().get_root().files_dropped.connect(_on_files_dropped)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _on_load_file_pressed() -> void:
	dialog.popup()

func _on_file_dialog_file_selected(path: String) -> void:
	begin_splatview(path)

func _on_files_dropped(files):
	begin_splatview(files[0])

func begin_splatview(path: String):
	emit_signal("fileChosen", path)
	loadfile.release_focus()
	#$LoadFile.hide()
	#$ColorRect.hide()
	ui.show()
