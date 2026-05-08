extends Node

var items: Inventory
var cards: Inventory

# Remplace ce chemin par TON ItemData (.tres) à démarrer
const START_ITEM: ItemData = preload("res://ui/interactable/item/resource/grimoire.tres")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# IMPORTANT: on configure start_items AVANT d'ajouter au tree
	items = Inventory.new()
	items.name = "Items"
	items.size = 99
	items.start_items = { START_ITEM: 1 }  # 1 seul item au démarrage
	add_child(items)

	cards = Inventory.new()
	cards.name = "Cards"
	cards.size = 99
	cards.start_items = {}                 # 0 item
	add_child(cards)
