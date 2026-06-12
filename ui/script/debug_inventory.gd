extends HBoxContainer

@onready var btn_card: Button = $AddCard
@onready var btn_item: Button = $AddItem
@onready var btn_remove_card: Button = $RemoveCard
@onready var btn_remove_item: Button = $RemoveItem
@onready var log_label: RichTextLabel = $RichTextLabel

# Références vers nos ItemData de test
const CARD_ITEM   : ItemData = preload("res://ui/interactable/item/resource/card_statue.tres")
const CLE_ITEM  : ItemData = preload("res://ui/interactable/item/resource/cle.tres")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
		# Connexions boutons
	btn_card.pressed.connect(_on_give_card_pressed)
	btn_item.pressed.connect(_on_give_item_pressed)
	btn_remove_card.pressed.connect(_on_remove_card_pressed)
	btn_remove_item.pressed.connect(_on_remove_item_pressed)

	# Écouter les signaux du manager pour auto-rafraîchir l'affichage
	InventoryManager.cards.UpdatedInventory.connect(_refresh_log)
	InventoryManager.items.UpdatedInventory.connect(_refresh_log)

	# Premier affichage
	_refresh_log()

func _on_give_card_pressed() -> void:
	InventoryManager.cards.add_item(CARD_ITEM)

func _on_give_item_pressed() -> void:
	InventoryManager.items.add_item(CLE_ITEM)

func _on_remove_card_pressed() -> void:
	InventoryManager.cards.remove_item(CARD_ITEM)

func _on_remove_item_pressed() -> void:
	InventoryManager.items.remove_item(CLE_ITEM)
	
func _refresh_log() -> void:
	var lines: Array[String] = []

	lines.append("\n[b]🃏 Cartes[/b]")
	lines.append(_format_inventory(InventoryManager.cards))

	lines.append("\n[b]🎒 Inventaire principal[/b]")
	lines.append(_format_inventory(InventoryManager.items))

	log_label.clear()
	var text := "\n".join(lines)

	log_label.append_text(text)

func _format_inventory(inv: Inventory) -> String:
	var parts: Array[String] = []
	for slot in inv.item_slots:
		if slot and slot.item:
			var display_name := slot.item.display_name
			var qty := str(slot.quantity)
			parts.append("- %s x%s" % [display_name, qty])
	if parts.is_empty():
		return "(vide)"
	return "\n".join(parts)
