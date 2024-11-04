extends Panel

@export var current_turn_indicator : Node
@export var title_text : Node
@export var toughness_text : Node
@export var dropzone : Node
var toughness : int = 20
var power : int = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	current_turn_indicator.hide()
	refresh()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func damage(amount: int) -> void:
	print(str(self.name) + " got damaged for " + str(amount))
	toughness -= amount
	refresh()

func refresh():
	toughness_text.text = "[center]%d[/center]" % (toughness)
	
