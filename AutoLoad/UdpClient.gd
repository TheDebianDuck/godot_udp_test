class_name UdpClient
extends Node

signal connected
signal disconnected
signal packet_received(udp, message)

export var _ip := "127.0.0.1"
export (int, 1, 65535) var _port = 31415
export var _auto_start := true
export var _process_interval := 0.0
export var _connection_timeout := 0.0
export var _heartbeat_time := 0.0
export var _max_queue := 10
export (String, MULTILINE) var _init_message = ""

var socket := PacketPeerUDP.new()
var out_queue := []
var in_queue := []
var last_process := 0.0
var last_connect := 0.0
var heartbeat := 0.0
var started := false
var connected := false

func _ready() -> void:
	if _auto_start:
		start()

func _process(delta: float) -> void:
	if started:
		heartbeat += delta
		if heartbeat > _heartbeat_time:
			heartbeat()
		
		if connected:
			last_connect += delta
			if _connection_timeout > 0 and last_connect > _connection_timeout:
				connected = false
				emit_signal("disconnected")
		
		if socket.get_available_packet_count() > 0:
			var pkt := socket.get_packet()
			
			if not connected:
				emit_signal("connected")
				connected = true
				heartbeat = 0.0
				print("Connected: %s" % pkt.get_string_from_utf8())
			
			last_connect = 0.0
			
			var msg := UdpServer.Message.new()
			msg.init(0, false)
			msg.add_byte_packet(pkt)
			
			in_queue.push_front(pkt)
			
			emit_signal("packet_received", socket, msg)
		
		if len(in_queue) > _max_queue:
			in_queue.pop_back()
		
		last_process += delta
		
		if last_process > _process_interval:
			send_out_queue()
			last_process = 0.0

func heartbeat():
	socket.put_packet(_init_message.to_utf8())
	heartbeat = 0.0

func start():
	socket.connect_to_host(_ip, _port)
	started = true

func stop():
	socket.close()
	started = false

func read_in_queue() -> Array:
	return in_queue

func empty_in_queue():
	in_queue = []

func queue_packet(packet: PoolByteArray):
	out_queue.append(packet)

func send_out_queue():
	while len(out_queue) > 0:
		socket.put_packet(out_queue.pop_front())
		heartbeat = 0.0
