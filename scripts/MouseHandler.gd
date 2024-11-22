extends Camera3D

enum DragType { NONE, PLACEMENT, TARGET }
# Ray length
var ray_length = 1000
var current_hover = null
var is_dragging = false
var targeting = false
var drag_start_position = Vector2.ZERO
var click_threshold = 10  # Distance threshold to differentiate between click and drag
var clicked_card = null
var group_dragged_from = null
var old_drop_point = null
@export var game_logic = Node
@export var battlefield_dropzone : Node
const CardType = preload("res://scripts/CardController.gd").CardType
@export var arrow_controller : Control
@export var sound_resource : Resource

func get_drop_point(mouse_position:Vector2):
	if battlefield_dropzone.hovered:
		var space_state = get_world_3d().get_direct_space_state()
		var params = PhysicsRayQueryParameters3D.new()
		var drop_point = project_ray_origin(mouse_position) + project_ray_normal(mouse_position) * 20
		return DropPoint.new(drop_point, get_node(game_logic.my_battlefield))
	return null

func find_hovered_card(mouse_pos:Vector2):
	var space_state = get_world_3d().get_direct_space_state()
	var params = PhysicsRayQueryParameters3D.new()
	params.from = project_ray_origin(mouse_pos)
	params.to = params.from + project_ray_normal(mouse_pos) * ray_length
	params.exclude = []

	params.collision_mask = 1
	var result = space_state.intersect_ray(params)
	
	if result:
		if result.collider is CardController:
			return result.collider as CardController
		if result.collider.get_parent() is Avatar:
			return result.collider.get_parent() as Avatar
		return null
	else:
		return null
	
func hovering(card):
	# no transition if its the same
	if card == current_hover:
		return
	
	var valid_hover_cardgroups = [
		get_node(game_logic.my_hand), 
		get_node(game_logic.my_battlefield),
		get_node(game_logic.my_graveyard),
		get_node(game_logic.opponent_battlefield),
		get_node(game_logic.opponent_graveyard),
		]
	if card != null and card.card_group_controller not in valid_hover_cardgroups:
		return
		
	if current_hover != null:
		current_hover.on_hover_end()
	current_hover = card
	if current_hover != null:
		current_hover.on_hover_begin()

func handle_placement_mousemotion():
	if clicked_card == null or clicked_card.card_group_controller == null:
		print("Weird")
		clear_mouse_state()
		return
		
	if not is_dragging and drag_start_position.distance_to(battlefield_dropzone.get_global_mouse_position()) > click_threshold:
		is_dragging = true

	var mouse_pos = get_viewport().get_mouse_position()

	# Get the ray origin and direction in world space from the camera
	var ray_origin = project_ray_origin(mouse_pos)
	var ray_direction = project_ray_normal(mouse_pos)

	# Define a plane at y=0 (e.g., ground plane), or define your plane
	var plane = Plane(Vector3(0, 0, 1), 3)  # Plane facing up at y=0

	# Calculate intersection of ray with the plane
	var intersect_pos = plane.intersects_ray(ray_origin, ray_direction)
	if clicked_card.card_group_controller is HandController:
		return
	clicked_card.card_group_controller.position_override = intersect_pos
	
	var drop_point = get_drop_point(battlefield_dropzone.get_global_mouse_position())
	if drop_point != null:
		if old_drop_point != null:
			old_drop_point.unhint()
			old_drop_point = null
		drop_point.hint()
		old_drop_point = drop_point
	else:
		if old_drop_point != null:
			old_drop_point.unhint()
			old_drop_point = null

func handle_targeting_mousemotion():
	if not is_dragging and drag_start_position.distance_to(battlefield_dropzone.get_global_mouse_position()) > click_threshold:
		is_dragging = true
		arrow_controller.visible = true
	if is_dragging:
		var start = unproject_position(clicked_card.transform.origin)
		var index_of_card_in_group = clicked_card.card_group_controller.index_of_card(clicked_card)
		arrow_controller.start_point = drag_start_position
		arrow_controller.end_point = battlefield_dropzone.get_global_mouse_position()

		var target = find_hover_target()
		if target != null && target != clicked_card:
			print("could cause highlight")
		
func determine_dragtype(target):
	if target != null && target.is_in_group("avatar"):
		return DragType.TARGET
		
	var from_group = group_dragged_from
	if from_group == null and target != null:
		from_group = target.card_group_controller

	# Tapped cards should not be draggable	
	if clicked_card != null:
		if clicked_card.tapped:
			return DragType.NONE
				
	if from_group == get_node(game_logic.my_battlefield):
		return DragType.TARGET
	
	if from_group == get_node(game_logic.my_hand):
		var type = target.type
		if clicked_card != null:
			type = clicked_card.type
		if type == CardType.HACK:
			return DragType.TARGET
		else:
			return DragType.PLACEMENT

	return DragType.NONE	
		
		
func handle_mousemotion(event):
	if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		match determine_dragtype(clicked_card):
			DragType.TARGET:
				handle_targeting_mousemotion()
			DragType.PLACEMENT:
				handle_placement_mousemotion()
			DragType.NONE:
				pass
	else:
		hovering(find_hovered_card(get_viewport().get_mouse_position()))		

func start_placement_click(event, card: CardController):
	if card == null or not card.is_controlled_by_me():
		print("Clicking not allowed on " + str(card.name))
		clear_mouse_state()
		return
	clicked_card = card
	is_dragging = false
	drag_start_position = event.position
	group_dragged_from = card.card_group_controller
	var gp = card.global_position
	get_node(game_logic.dragger).insert_card(group_dragged_from.take(card), 0, gp)
	handle_placement_mousemotion()

func on_placement_dropped(event, card: CardController):
	print("Placement drop detected!")
	if card == null:
		print("weird")
		return

	if old_drop_point != null:
		old_drop_point.unhint()
		old_drop_point = null

	var gp = card.global_position
	var drop_point = get_drop_point(battlefield_dropzone.get_global_mouse_position())
	
	if drop_point != null:
		card.card_group_controller.take(card)
		var drop_index = drop_point.card_group_controller.current_drag_index
		drop_point.card_group_controller.insert_card(card, drop_index, gp)
		Audio.play(sound_resource.sounds.get("enter_play"))
	else:
		card.card_group_controller.take(card)
		group_dragged_from.insert_card(card, 0, gp)

	clear_mouse_state()

func on_placement_clicked(event, card: CardController):
	print("Click detected!")
	if card == null:
		print("weird")
		return
		
	var gp = card.global_position
	card.card_group_controller.take(card)
	group_dragged_from.insert_card(card, 0, gp)
	clicked_card.on_clicked()
	clear_mouse_state()

func clear_mouse_state():
	is_dragging = false
	clicked_card = null
	drag_start_position = Vector2.ZERO
	group_dragged_from = null
	if old_drop_point != null:
		old_drop_point.unhint()
		old_drop_point = null
	targeting = false
	arrow_controller.visible = false

func handle_left_click_placement(event, card):
	if event.pressed:
		start_placement_click(event, card)
	else:
		if is_dragging:
			on_placement_dropped(event, clicked_card)
		else:
			on_placement_clicked(event, clicked_card)
			
func start_target_click(event, target):
	if target.is_in_group("avatar"):
		clear_mouse_state()
		return
	clicked_card = target
	if target != null:
		group_dragged_from = target.card_group_controller
	drag_start_position = event.position
	targeting = true

func is_hackable(attacker, target):
	if attacker.card_group_controller == target.card_group_controller:
		return false
		
	if target.card_group_controller == get_node(game_logic.my_graveyard) or target.card_group_controller == get_node(game_logic.opponent_graveyard):
		return false
	
	return true
	
func is_attackable(attacker, target):
	if attacker.card_group_controller == target.card_group_controller:
		return false
		
	if target.card_group_controller == get_node(game_logic.my_graveyard) or target.card_group_controller == get_node(game_logic.opponent_graveyard):
		return false
		
	if target.card_group_controller == get_node(game_logic.my_hand) or target.card_group_controller == get_node(game_logic.opponent_hand):
		return false
	
	return true

func play_hack(played_card, target):
	if not is_hackable(played_card, target):
		return false

	await played_card.play(target)

	played_card.card_group_controller.take(played_card)
	# todo: this only works for protagonist, not enemy
	get_node(game_logic.my_graveyard).insert_card(played_card, 0, played_card.global_position)

func play_attack(played_card, target):
	if not is_attackable(played_card, target):
		return false
		
	played_card.play(target)
		
func on_target_dropped(event, card):
	var target = find_hover_target()
		
	if clicked_card.card_group_controller == get_node(game_logic.my_hand):
		play_hack(clicked_card, target)
	
	if clicked_card.card_group_controller == get_node(game_logic.my_battlefield):
		play_attack(clicked_card, target)
		
	clear_mouse_state()
	
func on_target_clicked(event, card):
	print("Target card clicked")
	clear_mouse_state()
	
func handle_left_click_target(event, target):
	if event.pressed:
		start_target_click(event, target)
	else:
		if is_dragging:
			on_target_dropped(event, clicked_card)

func handle_left_button(event, target):		
	var drag_type = determine_dragtype(target)
	match drag_type:
		DragType.PLACEMENT:
			return handle_left_click_placement(event, target)
		DragType.TARGET:
			return handle_left_click_target(event, target)

func find_hover_target():
	var target = find_hovered_card(get_viewport().get_mouse_position())
	
	if get_node(game_logic.my_avatar).hovered:
		target = get_node(game_logic.my_avatar)
	if get_node(game_logic.opponent_avatar).hovered:
		target = get_node(game_logic.opponent_avatar)
	
	return target
	
func handle_mousebutton(event):
	hovering(null)
	var target = find_hover_target()
	if target != null and event.button_index == MOUSE_BUTTON_LEFT:
		handle_left_button(event, target)
	else:
		clear_mouse_state()
		hovering(find_hovered_card(get_viewport().get_mouse_position()))		

# Called every frame. Detects a click and casts a ray from the camera.
func _input(event):
	if event is InputEventMouseButton:
		return handle_mousebutton(event)
	elif event is InputEventMouseMotion:	
		return handle_mousemotion(event)
	elif (not is_dragging and not targeting):
		hovering(find_hovered_card(get_viewport().get_mouse_position()))		
