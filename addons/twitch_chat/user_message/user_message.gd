tool
extends HBoxContainer
class_name UserMessage

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func load_message(user : String, message : String, color : Color):
	$Name.set_text(user)
	$Message.set_text(message)
	$Name.set("custom_colors/font_color", color)
