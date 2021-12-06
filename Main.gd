extends MarginContainer

onready var peers: OptionButton = get_node(_peers)
onready var textbox: LineEdit = get_node(_textbox)
onready var sendbutton: Button = get_node(_sendbutton)
onready var output: TextEdit = get_node(_output)
onready var udpclient: UdpClient = get_node(_udpclient)
onready var udpserver: UdpServer = get_node(_udpserver)

export var _peers: NodePath
export var _textbox: NodePath
export var _sendbutton: NodePath
export var _output: NodePath
export var _udpclient: NodePath
export var _udpserver: NodePath
export var _server := false

var roster := []
var connected := false

func _ready() -> void:
	if _server:
		udpserver.start()
		roster = udpserver.roster
	else:
		udpclient.start()

func _process(delta: float) -> void:
	if _server and connected:
		peers.clear()
		for i in roster:
			if i != null and i._connected:
				peers.add_item("%s:%s" % [i._peer.get_packet_ip(), i._peer.get_packet_port()], i._id)	

func submit():
	if textbox != null:
		var txt := textbox.text
		output.text += ">> %s\n" % txt
		if _server:
			udpserver.queue_packet(txt.to_ascii())
		else:
			udpclient.queue_packet(txt.to_ascii())
	else:
		print("pressed")

func _on_Button_pressed() -> void:
	submit()

func _on_LineEdit_text_entered(new_text: String) -> void:
	submit()

func _on_UdpClient_connected() -> void:
	print("Connection established")
	connected = true
	textbox.editable = true
	textbox.text = ""
	sendbutton.disabled = false

func _on_UdpClient_disconnected() -> void:
	print("Disconnected")
	connected = false
	textbox.editable = false
	textbox.text = "DISCONNECTED"
	sendbutton.disabled = true

func _on_Udp_packet_received(udp, message: UdpServer.Message) -> void:
	var packet := message._packet.data_array
	print("Message from %s:%s => '%s'" % [udp.get_packet_ip(), udp.get_packet_port(), packet.get_string_from_utf8().strip_edges()])
	output.text += "<%s, %s>> %s\n" % [udp.get_packet_ip(), udp.get_packet_port(), packet.get_string_from_utf8()]


func _on_UdpServer_peer_change(peer) -> void:
	roster = udpserver.roster
	if roster.count(null) == udpserver._max_connections:
		peers.clear()
		peers.add_item("No Connections", -1)
		peers.disabled = true
		_on_UdpClient_disconnected()
	else:
		peers.disabled = false
		_on_UdpClient_connected()
