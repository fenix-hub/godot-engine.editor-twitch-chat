tool
extends Panel

var plugin_path : String = ProjectSettings.globalize_path("user://").replace("app_userdata/"+ProjectSettings.get_setting('application/config/name')+"/","twitch_chat")+"/"
var token_file : String = "channel.dat"

onready var login_control : Control = $Login
onready var chat_container : ScrollContainer = $ChatContainer
onready var chat : VBoxContainer = chat_container.get_node("Chat")
onready var fields : VBoxContainer = $Login/Fields
onready var loading : TextureRect = $Login/Loading

var user_message_scene : PackedScene = preload("res://addons/twitch_chat/user_message/user_message.tscn")

var _client = WebSocketClient.new()
var logged : bool
var channel : String = ""
var token : String = ""
var connected_users : PoolStringArray = []
var users_colors : PoolColorArray = []
var autoscroll : bool = true

# Called when the node enters the scene tree for the first time.
func _ready():
	randomize()
	fields.show()
	loading.hide()
	_connect_signals()
	logged = false
	load_data()
	if channel!="" and token!="" : connect_to_url()

func _connect_signals():
	$Login/Fields/Button.connect("pressed", self, "_open_url")
	$Login/Fields/Button2.connect("pressed", self, "_on_connect_pressed")
	_client.connect("connection_closed", self, "_closed")
	_client.connect("connection_error", self, "_closed")
	_client.connect("connection_established", self, "_connected")
	_client.connect("data_received", self, "_on_data")
	_client.connect("server_close_request",self, "_on_server_close_request")

func _open_url():
	OS.shell_open("https://www.twitchapps.com/tmi/")

func _on_connect_pressed():
	channel = $Login/Fields/HBoxContainer/Name.get_text()
	token = $Login/Fields/HBoxContainer2/Token.get_text()
	assert(not channel in [""," "],"Invalid channel name, must be non-empty.")
	assert(not token in [""," "],"Invalid channel name, must be non-empty.")
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
	print("Closed, clean: ", was_clean)
	set_process(false)
	login_control.show()
	loading.hide()
	fields.show()

func _connected(proto = ""):
	save_data(channel, token)
	_client.get_peer(1).set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	_client.get_peer(1).put_packet(("PASS %s\n"%token).to_utf8())
	_client.get_peer(1).put_packet(("NICK %s\n"%channel.to_lower()).to_utf8())
	_client.get_peer(1).put_packet(("JOIN #%s\n"%channel.to_lower()).to_utf8())
	print("Connecting to channel %s..."%channel)

func _on_data():
	var data_received : String = _client.get_peer(1).get_packet().get_string_from_utf8()
	if not logged : 
		if log_successful(data_received) : 
			logged = true
			login_control.hide()
			set_name("TwitchChat #%s"%channel)
			return
	if ping_received(data_received) : 
		send_pong()
		return
	if JOIN_message(data_received):
		check_sender("[GOBOT]")
		append_chat_message("[GOBOT]","Welcome to the Godot Engine's Twitch Chat!\r\n")
	if PRIVMSG_message(data_received):
		var data_separated : Array = data_received.split("PRIVMSG")
		var sender : String = data_separated[0].split("!")[0].lstrip(":")
		check_sender(sender)
		var message : String = data_separated[1].split("#%s :"%channel)[1]
		append_chat_message(sender, message)

func check_sender(sender : String):
	if not sender in connected_users:
		connected_users.append(sender)
		users_colors.append(Color.from_hsv(max(0.25, randf()),max(0.4,randf()),max(0.4,randf())))

func append_chat_message(sender : String, message : String):
	var user_message : UserMessage = user_message_scene.instance()
	chat.add_child(user_message)
	user_message.load_message(sender, message.c_escape().replace("\\r\\n","").c_unescape(), users_colors[Array(connected_users).find(sender)])
	yield(get_tree(), "idle_frame")
	if autoscroll : chat_container.set_v_scroll(chat_container.get_v_scrollbar().max_value)

func _on_server_close_request(code: int, reason: String):
	print(str(code)," ",reason)

func _process(delta):
	_client.poll()

func ping_received(data : String):
	return (data == "PING :tmi.twitch.tv")

func print_message(user : String, message : String):
	pass

func log_successful(data : String):
	return data.begins_with(":tmi.twitch.tv 001")

func JOIN_message(data : String):
	return ("tmi.twitch.tv JOIN" in data)

func PRIVMSG_message(data : String) -> bool:
	return ("tmi.twitch.tv PRIVMSG " in data)

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
			token = content[1]
		else:
			save_data("","")

func save_data(_channel : String, _token : String):
	var file : File = File.new()
	file.open_encrypted_with_pass(plugin_path+token_file, File.WRITE, OS.get_unique_id())
	file.store_line(_channel+";"+_token)
