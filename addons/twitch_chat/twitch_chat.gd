tool
extends EditorPlugin

var dock : Control

func _enter_tree():
	dock = preload("res://addons/twitch_chat/twitch_dock/twitch_chat_dock.tscn").instance()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, dock)


func _exit_tree():
	remove_control_from_docks(dock)
	dock.queue_free()
