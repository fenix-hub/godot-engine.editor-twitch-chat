tool
extends PanelContainer

var plugin_path : String = ProjectSettings.globalize_path("user://").replace("app_userdata/"+ProjectSettings.get_setting('application/config/name')+"/","twitch_chat")+"/"
var token_file : String = "channel.dat"

class Person:
	
	static func add_person():
		"I am a person"

onready var login_control : Control = $Login
onready var chat_container : ScrollContainer = $ChatContainer/ChatScroller
onready var chat : VBoxContainer = chat_container.get_node("Chat")
onready var fields : VBoxContainer = $Login/Fields
onready var loading : TextureRect = $Login/Loading
onready var message_box : LineEdit = $ChatContainer/MessageBox/Message
onready var menu : MenuButton = $ChatContainer/PanelContainer/MenuButton
onready var user_info : HBoxContainer = $Login/Fields/UserInfo
onready var streamer_check : CheckBox = $Login/Fields/HBoxContainer/StreamerCheck
onready var username_lbl : Label = $ChatContainer/PanelContainer/Username

var user_message_scene : PackedScene = preload("res://addons/twitch_chat/user_message/user_message.tscn")

var _client = WebSocketClient.new()
var logged : bool
var channel : String = ""
var user : String = ""
var token : String = ""
var connected_users : PoolStringArray = []
var connected_users_dn : PoolStringArray = []
var users_colors : PoolColorArray = []
var autoscroll : bool = true

# Called when the node enters the scene tree for the first time.
func _ready():
	if "name" in UserMessage:
		print("yes")
	randomize()
	_connect_signals()
	_load_icons()
	
	login_control.show()
	fields.show()
	loading.hide()
	logged = false
	set_name("Twitch Chat")
	username_lbl.set_text("")
	load_data()
	if channel!="" and token!="" : 
		connect_to_url()
		fill_fields(channel, user, token)

func fill_fields(_channel : String = "", _user : String = "", _token : String = ""):
	$Login/Fields/HBoxContainer/Name.set_text(_channel)
	$Login/Fields/UserInfo/User.set_text(_user)
	$Login/Fields/HBoxContainer2/Token.set_text(_token)

func _load_icons():
	menu.set_button_icon(get_theme().get_icon("GDScript","EditorIcons"))

func _connect_signals():
	menu.get_popup().connect("index_pressed", self , "_on_index_pressed")
	$Login/Fields/Button.connect("pressed", self, "_open_url")
	$Login/Fields/Button2.connect("pressed", self, "_on_connect_pressed")
	$ChatContainer/MessageBox/ChatBtn.connect("pressed", self, "_on_chat_pressed")
	message_box.connect("text_entered",self,"_on_text_entered")
	streamer_check.connect("toggled", self, "_on_streamer_check_toggled")
	_client.connect("connection_closed", self, "_closed")
	_client.connect("connection_error", self, "_closed")
	_client.connect("connection_established", self, "_connected")
	_client.connect("data_received", self, "_on_data")
	_client.connect("server_close_request",self, "_on_server_close_request")

func _on_streamer_check_toggled(toggled : bool):
	user_info.set_visible(not toggled)

func _on_index_pressed(index : int):
	match index:
		0: disconnect_from_channel()
		1: delete_data()

func _open_url():
	OS.shell_open("https://www.twitchapps.com/tmi/")

func _on_connect_pressed():
	set_process(true)
	channel = $Login/Fields/HBoxContainer/Name.get_text()
	user = $Login/Fields/UserInfo/User.get_text()
	token = $Login/Fields/HBoxContainer2/Token.get_text()
	assert(not channel in [""," "],"Invalid channel name, must be non-empty.")
	assert(not user in [""," "],"Invalid user name, must be non-empty.")
	assert(not token in [""," "],"Invalid token, must be non-empty.")
	connect_to_url()

func connect_to_url():
	loading.show()
	fields.hide()
	print("Connecting to Twitch WebSocket...")
	var err = _client.connect_to_url("wss://irc-ws.chat.twitch.tv:443")
	if err != OK:
		print("Unable to connect")
		set_process(false)

func _closed(was_clean = false):
	print("Connection closed.")
	for message in chat.get_children():
		message.queue_free()
	set_process(false)
	login_control.show()
	loading.hide()
	fields.show()

func _connected(proto = ""):
	login_control.hide()
	if streamer_check.is_pressed() : user = channel
	save_data(channel, user, token)
	_client.get_peer(1).set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	_client.get_peer(1).put_packet(("PASS %s\n"%token).to_utf8())
	_client.get_peer(1).put_packet(("NICK %s\n"%user.to_lower()).to_utf8())
	_client.get_peer(1).put_packet(("JOIN #%s\n"%channel.to_lower()).to_utf8())
	send_request("twitch.tv/membership")
	send_request("twitch.tv/tags")
	print("Connecting to channel %s as %s..."%[channel, user])
	username_lbl.set_text(user)

func _on_data():
	var data_received : String = _client.get_peer(1).get_packet().get_string_from_utf8()
	if ping_received(data_received) : 
		send_pong()
		return
	if JOIN_message(data_received):
		logged = true
		login_control.hide()
		
		set_name("Twitch Chat #%s"%channel)
		
		var welcome_label : Label = Label.new()
		chat.add_child(welcome_label)
		welcome_label.align = Label.ALIGN_CENTER
		welcome_label.set("custom_colors/font_color", Color.dimgray)
		welcome_label.set_text("Welcome to Godot Engine's Twitch Chat!")
	elif PART_message(data_received):
		_client.disconnect_from_host()
		return
	if CAP_ACK_message(data_received): 
		if not logged: 
			_client.disconnect_from_host()
			printerr("Something went wrong: wrong channel name.")
	if PRIVMSG_message(data_received): deserialize_message(data_received)

func CAP_ACK_message(data_received : String) -> bool:
	return ("CAP * ACK" in data_received)

func deserialize_message(data : String):
	var data_separated : Array = data.split("PRIVMSG")
	var sender_info : Array = data_separated[0].split(":")
	var sender : String = sender_info[1].split("!")[0].lstrip(":")
	var sender_idx : int = check_sender(sender)
	var sender_display_name : String 
	if sender_idx == -1 : sender_display_name = add_user(sender, deserialize_sender_metadata(sender_info))
	else : sender_display_name = connected_users_dn[sender_idx]
	var message : String = data_separated[1].split("#%s :"%channel)[1]
	append_chat_message(sender_display_name, message)

func deserialize_sender_metadata(sender_info : Array) -> Dictionary:
	return JSON.parse(sender_info[0].replace("@","{\"").replace(";","\",\"").replace("=","\":\"")+"\"}").result

func check_sender(sender : String) -> int:
	return (Array(connected_users).find(sender))

func add_user(sender : String, sender_metadata : Dictionary = {}) -> String:
	var color : Color = Color(sender_metadata.color) if Color(sender_metadata.color) != Color.black else Color.from_hsv(max(0.25, randf()),max(0.4,randf()),max(0.4,randf())).lightened(0.3)
	connected_users.append(sender)
	connected_users_dn.append(sender_metadata["display-name"])
	users_colors.append(color)
	return sender_metadata["display-name"]

func append_chat_message(sender : String, message : String):
	var user_message : UserMessage = user_message_scene.instance()
	chat.add_child(user_message)
	message.erase(message.length()-1,1)
	user_message.load_message(sender, message, users_colors[Array(connected_users_dn).find(sender)])
	yield(get_tree(), "idle_frame")
	if autoscroll : chat_container.set_v_scroll(chat_container.get_v_scrollbar().max_value)

func _on_server_close_request(code: int, reason: String):
	print(str(code)," ",reason)

func _process(delta):
	_client.poll()

func ping_received(data : String):
	return ("PING :tmi.twitch.tv" in data)

func print_message(user : String, message : String):
	pass

func log_successful(data : String):
	return data.begins_with("%s:tmi.twitch.tv JOIN"%user)

func JOIN_message(data : String):
	return ("tmi.twitch.tv JOIN" in data)

func PRIVMSG_message(data : String) -> bool:
	return ("tmi.twitch.tv PRIVMSG " in data)

func PART_message(data : String) -> bool:
	return ("tmi.twitch.tv PART " in data)

func send_pong():
	_client.get_peer(1).put_packet("PONG :tmi.twitch.tv".to_utf8())

func load_data():
	var directory : Directory = Directory.new()
	var file : File = File.new()
	if not directory.dir_exists(plugin_path):
		directory.make_dir_recursive(plugin_path)
	else:
		if directory.file_exists(plugin_path+token_file):
			file.open_encrypted_with_pass(plugin_path+token_file, File.READ, OS.get_unique_id())
			var content : PoolStringArray = file.get_as_text().split(";")
			channel = content[0]
			user = content[1]
			token = content[2]
		else:
			save_data("","","")

func save_data(_channel : String, _user : String, _token : String):
	var file : File = File.new()
	file.open_encrypted_with_pass(plugin_path+token_file, File.WRITE, OS.get_unique_id())
	file.store_line(_channel+";"+_user+";"+_token)

func delete_data():
	var directory : Directory = Directory.new()
	var file : File = File.new()
	if directory.dir_exists(plugin_path):
		if directory.file_exists(plugin_path+token_file):
			directory.remove(plugin_path+token_file)
	disconnect_from_channel()
	_client.disconnect_from_host()
	_closed()
	fill_fields()

func _on_chat_pressed():
	send_message(message_box.get_text()+"\r\n")

func _on_text_entered(message : String):
	send_message(message+"\r\n")

func send_message(message : String = ""):
	_client.get_peer(1).put_packet(("PRIVMSG #%s :%s"%[channel.to_lower(), message]).to_utf8())
	append_chat_message(user, message)
	message_box.clear()

func send_request(request : String):
	_client.get_peer(1).put_packet(("CAP REQ :%s"%request).to_utf8())

func send_part():
	return _client.get_peer(1).put_packet(("PART #%s"%channel).to_utf8())

func disconnect_from_channel():
	logged = false
	return send_part()
