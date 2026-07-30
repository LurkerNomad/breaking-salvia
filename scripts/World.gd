extends Node

const PlayerScene = preload("res://Scenes/Player.tscn")

var _spawn_positions = [
	Vector3(0, 1, 0),
	Vector3(3, 1, 3),
	Vector3(-3, 1, -3),
]


func _ready():
	if multiplayer.is_server():
		# Spawn host locally — no one is connected yet, no RPC needed
		_local_spawn(multiplayer.get_unique_id(),
					 _spawn_positions[randi() % _spawn_positions.size()],
					 NetworkManager.chosen_character)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	else:
		# Client tells server it's ready and sends its character choice
		# This fires AFTER _ready() so the scene is guaranteed to exist
		client_ready.rpc_id(1, NetworkManager.chosen_character)


# ── Called by client on server when their World scene is fully loaded ────────
@rpc("any_peer", "call_remote", "reliable")
func client_ready(char_type: String):
	var client_id = multiplayer.get_remote_sender_id()
	var pos = _spawn_positions[randi() % _spawn_positions.size()]

	# Spawn the new client on EVERYONE (including server and client themselves)
	spawn_player.rpc(client_id, pos, char_type)

	# Send every already-existing player to ONLY the new client
	for child in get_children():
		if child.name.is_valid_int():
			var pid = int(child.name)
			if pid != client_id:
				spawn_player.rpc_id(client_id, pid, child.position, child.char_type)


func _on_peer_disconnected(id: int):
	remove_player.rpc(id)


# ── Spawn/remove RPCs ────────────────────────────────────────────────────────
@rpc("authority", "call_local", "reliable")
func spawn_player(id: int, pos: Vector3, char_type: String):
	if has_node(str(id)):
		return
	var player = PlayerScene.instantiate()
	player.name     = str(id)
	player.position = pos
	player.set_multiplayer_authority(id)
	add_child(player)
	player.apply_character(char_type)


@rpc("authority", "call_local", "reliable")
func remove_player(id: int):
	var p = get_node_or_null(str(id))
	if p:
		p.queue_free()


# ── Local-only spawn (used for host at startup) ──────────────────────────────
func _local_spawn(id: int, pos: Vector3, char_type: String):
	var player = PlayerScene.instantiate()
	player.name     = str(id)
	player.position = pos
	player.set_multiplayer_authority(id)
	add_child(player)
	player.apply_character(char_type)
