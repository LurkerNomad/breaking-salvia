extends Control

@onready var your_id_label  = $"TabContainer/Noray(Internet)/NorayContainer/YourIDLabel"
@onready var join_id_input  = $"TabContainer/Noray(Internet)/NorayContainer/JoinIDInput"
@onready var lan_ip_input   = $TabContainer/LAN/LANContainer/LANIPInput
@onready var lan_port_input = $TabContainer/LAN/LANContainer/LANPortInput
@onready var status_label   = $VBoxContainer/StatusLabel
@onready var password_input = $VBoxContainer/HBoxContainer/PasswordInput
@onready var char_label     = $VBoxContainer/HBoxContainer/CharLabel

const PASSWORDS = {
	"edi":     "themanager",
	"denis": "theworker",
	"matias": "thejake"
}

func _ready():
	lan_ip_input.text   = NetworkManager.get_local_ip()
	lan_port_input.text = "7777"
	NetworkManager.status_changed.connect(_on_status_changed)
	NetworkManager.noray_id_ready.connect(_on_noray_id_ready)
	NetworkManager.init_noray()

func _on_status_changed(msg: String):
	status_label.text = msg

func _on_noray_id_ready(oid: String):
	your_id_label.text = oid
	status_label.text  = "Noray ready."

# live password feedback
func _on_password_input_text_changed(new_text: String):
	var t = new_text.strip_edges().to_lower()
	if PASSWORDS.has(t):
		var c = PASSWORDS[t]
		char_label.text = "Walter Edi" if c == "themanager" else "Denis the Worker"
	else:
		char_label.text = "—"

func _get_character() -> String:
	var t = password_input.text.strip_edges().to_lower()
	return PASSWORDS.get(t, "")

func _validate_and(action: Callable) -> void:
	var c = _get_character()
	if c.is_empty():
		status_label.text = "Enter a valid character password first."
		return
	NetworkManager.chosen_character = c
	action.call()

# ── Noray ─────────────────────────────────────────────────────────────────
func _on_host_button_pressed():
	_validate_and(NetworkManager.host_noray)

func _on_join_button_pressed():
	_validate_and(func(): NetworkManager.join_noray(join_id_input.text.strip_edges()))

func _on_copy_id_button_pressed():
	DisplayServer.clipboard_set(your_id_label.text)

# ── LAN ───────────────────────────────────────────────────────────────────
func _on_lan_host_button_pressed():
	_validate_and(func(): NetworkManager.host_lan(int(lan_port_input.text)))

func _on_lan_join_button_pressed():
	_validate_and(func(): NetworkManager.join_lan(
		lan_ip_input.text.strip_edges(), int(lan_port_input.text)))
