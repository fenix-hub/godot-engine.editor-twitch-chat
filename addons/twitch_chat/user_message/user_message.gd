tool
extends HBoxContainer
class_name UserMessage

onready var message_box : RichTextLabel = $Message

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func load_message(user : String, message : String, color : Color):
	message_box.append_bbcode("[b][color=#{color}]{user}[/color][/b]: {message}".format([["color",color.to_html()],["user",user],["message",message]]))
