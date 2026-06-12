extends CanvasLayer

# --- Préchargement des scènes (performant) ---
const PopupScene    := preload("res://ui/scene/popup_message.tscn")

# --- Instances poolées ---
var _popup: PopupMessage

func _ready() -> void:
	# Instanciation unique (pooling)
	_popup  = PopupScene.instantiate() as PopupMessage
	
	# Ajouter comme enfants du CanvasLayer (au-dessus du jeu)
	add_child(_popup)
	
	# Masquer par défaut
	_popup.visible = false
	
	#Exemple of usage :
	# Popup centrée + typewriter
	#UIManager.show_popup("Nouvel Objet", "Tu as trouvé une clé ancienne ✨", PopupMessage.PositionMode.CENTER, PopupMessage.TextMode.TYPEWRITER)

	# Bandeau bas (avec marges), affichage instantané
	#UIManager.show_popup("", "Astuce : les torches peuvent cacher des passages.", PopupMessage.PositionMode.BOTTOM, PopupMessage.TextMode.INSTANT)


# --- API publique ---
func show_popup(title: String, text: String, pos_mode: int = PopupMessage.PositionMode.CENTER, text_mode: int = PopupMessage.TextMode.TYPEWRITER) -> void:
	if _popup:
		_popup.show_message(title, text, pos_mode, text_mode)

func hide_popup() -> void:
	if _popup:
		_popup.hide_message()
