extends Node

# ─────────────────────────────────────────────────────────────────────────────
# Signals
# ─────────────────────────────────────────────────────────────────────────────
signal status_changed(msg: String)
signal noray_id_ready(oid: String)

# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────
const NORAY_HOST  = "tomfol.io"
const NORAY_PORT  = 8890
const WORLD_SCENE = "res://Scenes/World.tscn"

# ─────────────────────────────────────────────────────────────────────────────
# Internal state
# ─────────────────────────────────────────────────────────────────────────────
var _lan_peer: ENetMultiplayerPeer
var chosen_character := ""   # set by MainMenu before connecting

# ─────────────────────────────────────────────────────────────────────────────
# Utility: get the local LAN IP (192.168.x.x or 10.x.x.x)
# Called by MainMenu to pre-fill the IP field.
# ─────────────────────────────────────────────────────────────────────────────
func get_local_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			return addr
	return "127.0.0.1"


# ─────────────────────────────────────────────────────────────────────────────
# NORAY — connect to relay server and get an OID
# Call this once when the menu opens.
# ─────────────────────────────────────────────────────────────────────────────
func init_noray() -> void:
	status_changed.emit("Connecting to Noray…")

	var err: int = await Noray.connect_to_host(NORAY_HOST, NORAY_PORT)
	if err != OK:
		status_changed.emit("Noray unreachable (err %d). Check internet." % err)
		return

	# Request IDs from the relay server
	Noray.register_host()
	await Noray.on_pid  # wait until PrivateID is received

	# Register our external UDP address with noray
	err = await Noray.register_remote()
	if err != OK:
		status_changed.emit("Noray remote registration failed (err %d)" % err)
		return

	noray_id_ready.emit(Noray.oid)
	status_changed.emit("Ready. Your ID: %s" % Noray.oid)


# ─────────────────────────────────────────────────────────────────────────────
# NORAY — host a game
# ─────────────────────────────────────────────────────────────────────────────
func host_noray() -> void:
	status_changed.emit("Hosting via Noray…")

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(Noray.local_port)
	if err != OK:
		status_changed.emit("Failed to open port %d" % Noray.local_port)
		return

	multiplayer.multiplayer_peer = peer

	# When a client tries to connect, noray fires these signals
	if not Noray.on_connect_nat.is_connected(_noray_host_handshake):
		Noray.on_connect_nat.connect(_noray_host_handshake)
	if not Noray.on_connect_relay.is_connected(_noray_host_handshake):
		Noray.on_connect_relay.connect(_noray_host_handshake)

	_on_hosted()


func _noray_host_handshake(address: String, port: int) -> void:
	var enet_peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet_peer == null:
		return
	await PacketHandshake.over_enet(enet_peer.host, address, port)


# ─────────────────────────────────────────────────────────────────────────────
# NORAY — join a game by the host's OID
# ─────────────────────────────────────────────────────────────────────────────
func join_noray(host_oid: String) -> void:
	if host_oid.is_empty():
		status_changed.emit("Paste the host's ID first.")
		return

	status_changed.emit("Connecting via Noray…")

	# Wire handlers before sending the request
	if not Noray.on_connect_nat.is_connected(_noray_client_handshake):
		Noray.on_connect_nat.connect(_noray_client_handshake)
	if not Noray.on_connect_relay.is_connected(_noray_client_handshake):
		Noray.on_connect_relay.connect(_noray_client_handshake)

	# Try NAT punchthrough first; relay is the fallback inside the handler
	Noray.connect_nat(host_oid)


func _noray_client_handshake(address: String, port: int) -> void:
	# Do the UDP handshake so noray knows the connection is alive
	var udp := PacketPeerUDP.new()
	udp.bind(Noray.local_port)
	udp.set_dest_address(address, port)

	var err: int = await PacketHandshake.over_packet_peer(udp)
	udp.close()

	if err != OK:
		status_changed.emit("NAT punchthrough failed — trying relay…")
		# Ask noray to relay instead; this will re-fire on_connect_relay
		Noray.connect_relay(Noray.oid)
		return

	var peer := ENetMultiplayerPeer.new()
	# IMPORTANT: always pass Noray.local_port as the local port here
	err = peer.create_client(address, port, 0, 0, 0, Noray.local_port)
	if err != OK:
		status_changed.emit("Failed to create client (err %d)" % err)
		return

	multiplayer.multiplayer_peer = peer
	_on_joined()


# ─────────────────────────────────────────────────────────────────────────────
# LAN — host
# ─────────────────────────────────────────────────────────────────────────────
func host_lan(port: int = 7777) -> void:
	_lan_peer = ENetMultiplayerPeer.new()
	var err := _lan_peer.create_server(port)
	if err != OK:
		status_changed.emit("LAN host failed — port %d in use?" % port)
		return

	multiplayer.multiplayer_peer = _lan_peer
	status_changed.emit("Hosting on LAN :%d" % port)
	_on_hosted()


# ─────────────────────────────────────────────────────────────────────────────
# LAN — join
# ip   = the HOST's IP address (not your own)
# port = must match whatever the host entered
# ─────────────────────────────────────────────────────────────────────────────
func join_lan(ip: String, port: int = 7777) -> void:
	if ip.is_empty():
		status_changed.emit("Enter the host's IP address.")
		return

	_lan_peer = ENetMultiplayerPeer.new()
	var err := _lan_peer.create_client(ip, port)
	if err != OK:
		status_changed.emit("LAN join failed (err %d)" % err)
		return

	multiplayer.multiplayer_peer = _lan_peer
	status_changed.emit("Connecting to %s:%d…" % [ip, port])
	_on_joined()


# ─────────────────────────────────────────────────────────────────────────────
# Shared post-connection logic
# ─────────────────────────────────────────────────────────────────────────────
func _on_hosted() -> void:
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_joined() -> void:
	multiplayer.connected_to_server.connect(func():
		status_changed.emit("Connected!")
		get_tree().change_scene_to_file(WORLD_SCENE)
	)
	multiplayer.connection_failed.connect(func():
		status_changed.emit("Connection failed — wrong IP or host not running?")
	)


func _peer_connected(id: int) -> void:
	print("[NetworkManager] Peer connected: ", id)


func _peer_disconnected(id: int) -> void:
	print("[NetworkManager] Peer disconnected: ", id)
