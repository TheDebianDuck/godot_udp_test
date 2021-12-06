class_name UdpServer
extends Node

signal peer_connected(peer)
signal peer_denied(peer)
signal peer_disconnected(peer)
signal peer_dropped(peer)
signal packet_received(udp, message)

export var _ip := "127.0.0.1"
export (int, 1, 65535) var _port = 31415
export var _confirm_flag := 0x42
export var _decline_flag := 0x24
export var _auto_start := true
export var _send_interval := 0.0
export var _disconnect_interval := 0.0
export var _drop_interval := 0.0
export var _max_connections := 16
export var _reopen_lost_roster := false
export var _prepend_timestamp := false

var server := UDPServer.new()
var roster := []
var out_queue := []
var in_queue := []
var last_process := 0.0
var last_connect := 0.0
var last_heartbeat := 0.0
var started := false
var connected := false

func _ready() -> void:
	server.max_pending_connections = _max_connections
	for i in range(_max_connections):
		roster.append(null)

	if _auto_start:
		start()

func _process(delta: float) -> void:
	if server.is_listening():
		server.poll()
		if server.is_connection_available():
			var peer := server.take_connection()
			var pkt := peer.get_packet()
			update_peers(peer)
			
		heartbeat(delta)
	
	last_process += delta
	if last_process > _send_interval:
		send_out_queue()
		last_process = 0.0

func accept_connections():
	if server.is_connection_available():
		var peer := server.take_connection()
		var pkt := peer.get_packet()
		peer.put_packet(PoolByteArray([_confirm_flag]))
		var id = update_peers(peer)

func update_peers(peer: PacketPeerUDP):	
	if not peer in roster:
		var fnd = roster.find(null)
		if fnd >= 0:
			var tmp := Connection.new()
			tmp.init(fnd, peer)
			roster[fnd] = tmp
			queue_packet(PoolByteArray([_confirm_flag]))
			emit_signal("peer_connected", peer)
		else:
			server.max_pending_connections = 0
			queue_packet(PoolByteArray([_decline_flag]))
			emit_signal("peer_denied", peer)

func heartbeat(delta: float):
	server.poll()
	for i in roster:
		if i != null:
			var peer: PacketPeerUDP = i._peer
			if peer.get_available_packet_count() > 0:
				var msg := Message.new()
				msg.init(len(in_queue), i._id, true, _prepend_timestamp)
				msg.add_byte_packet(peer.get_packet())
				in_queue.append(msg)
				var stream := StreamPeerBuffer.new()
				stream.put_64(_confirm_flag)
				queue_stream(stream)
				i.reset_ping()
				emit_signal("packet_received", peer, msg)
				
			elif i._connected:
				if _disconnect_interval > 0 and i.increase_ping(delta) >= _disconnect_interval:
					i.reset_disconnected()
					emit_signal("peer_disconnected", i)

			else:
				if _drop_interval > 0 and i.increase_disconnected(delta) >= _drop_interval:
					roster[i._id] = null
					i._packet.close()
					if _reopen_lost_roster:
						open()
					emit_signal("peer_dropped", i)

func start():
	var res: int
	var sp_ip := len(_ip.strip_edges()) > 0
	if sp_ip:
		res = server.listen(_port, _ip)
	else:
		res = server.listen(_port)
		
	if res != OK:
		print("Error listening on " + _ip + ":" + str(_port))
		return
	
	if sp_ip:
		print("Listening on " + _ip + ":" + str(_port))
	else:
		print("Listening on port " + str(_port))

func stop():
	if server.is_listening():
		server.stop()

func get_in_queue() -> Array:
	return in_queue

func pop_in_queue() -> PoolByteArray:
	return in_queue.pop_back()

func empty_in_queue():
	in_queue = []

func empty_out_queue():
	out_queue = []

func queue_packet(packet: PoolByteArray):
	var msg = Message.new()
	msg.add_byte_packet(packet)
	out_queue.append(msg)
	
func queue_stream(stream: StreamPeerBuffer):
	var msg = Message.new()
	msg.add_stream(stream)
	out_queue.append(msg)

func send_out_queue():
	while len(out_queue) > 0:
		var tmp: Message = out_queue.pop_front()
		var conn = roster[tmp._target_id]
		if conn != null:
			var peer: PacketPeerUDP = conn._peer
			peer.put_packet(tmp.get_packet())

func open():
	server.max_pending_connections = _max_connections

func close():
	server.max_pending_connections = 0


class Connection:	
	var _id: int
	var _last_ping := 0.0
	var _disconnected := 0.0
	var _connected := true
	var _peer: PacketPeerUDP
	
	func init(id: int, peer: PacketPeerUDP):
		_id = id
		_peer = peer
	
	func reset_ping():
		_last_ping = 0.0
		_connected = true
	
	func increase_ping(delta: float) -> float:
		_last_ping += delta
		return _last_ping
		
	func reset_disconnected():
		_disconnected = 0.0
		_connected = false
	
	func increase_disconnected(delta: float) -> float:
		_disconnected += delta
		return _disconnected


class Message:
	var _id: int
	var _packet := StreamPeerBuffer.new()
	var _out := true
	var _timestamp := false
	var _target_id: int
	
	func init(id: int, target: int, out := true, timestamp := false):
		_id = id
		_target_id = target
		_out = out
		_timestamp = timestamp
	
	func add_byte_packet(packet: PoolByteArray):
		_packet.put_data(packet)
	
	func add_stream(stream: StreamPeerBuffer):
		add_byte_packet(stream.data_array)
	
	func get_packet() -> PoolByteArray:
		var tmp = StreamPeerBuffer.new()
		if _timestamp:
			tmp.put_64(OS.get_ticks_msec())
		tmp.put_data(_packet.data_array)
		return tmp.data_array
