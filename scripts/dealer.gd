extends Control

class_name Dealer

signal send_playable_piles
signal send_target_piles
signal shared_piles_changed
signal move_made
signal card_animation_complete
signal game_winnable

const card_scene := preload("res://Scenes/card.tscn")
const pile_scene := preload("res://Scenes/play_pile.tscn")

var cards:Array
var play_piles:Dictionary

var target_pile:PlayPile
var held_card:Card
var holding_card:bool = false
var stuck:bool = false

var opponent_is_stuck:bool = false
var win_state:bool = false
var round_win_recorded:bool = false

var card_half_size:Vector2
var card_scaler:float = 1
var play_area_req_dims:Vector2 = Vector2(6,5.5)

var ordering_temp:int = 0
var difficulty_scalar:float = 0
var difficutly_scalar_bounds:Vector2 = Vector2(0,3)

func _ready() -> void:
	create_deck()
	card_half_size = cards[0].card_size()/2
	create_play_piles()
	set_play_area()
	set_up_game(26,26)

func _process(delta: float) -> void:
	move_card()

func create_deck() -> void:
	var card_values:Array = ['A'] + range(2,11) + ['J', 'Q', 'K']
	var card_suits:Array = ['♤', '♡', '♧', '♢']
	cards = []

	for suit in card_suits:
		for val in card_values:
			#instatitaet w/ params https://ask.godotengine.org/4786/how-to-pass-parameters-when-instantiating-a-node?show=84889#c84889
			var card:Card = card_scene.instantiate().populate_card(str(val), suit)
			cards.append(card)
			$Deck.add_child(card)

func create_play_piles() -> void:
	play_piles = {
		'opponent_deck' : pile_scene.instantiate().init("Opp\nDeck", "clean", true),
		'opponent_pile' : pile_scene.instantiate().init("Opp\nPile", "messy", true),
		'opponent_sol_one' : pile_scene.instantiate().init("Opp\nSol\nFive", "stacked", true),
		'opponent_sol_two' : pile_scene.instantiate().init("Opp\nSol\nFour", "stacked", true),
		'opponent_sol_three' : pile_scene.instantiate().init("Opp\nSol\nThree", "stacked", true),
		'opponent_sol_four' : pile_scene.instantiate().init("Opp\nSol\nTwo", "stacked", true),
		'opponent_sol_five' : pile_scene.instantiate().init("Opp\nSol\nOne", "stacked", true),

		'player_deck' : pile_scene.instantiate().init("Player\nDeck", "clean", false),
		'player_pile' : pile_scene.instantiate().init("player\nPile", "messy", false),
		'player_sol_one' : pile_scene.instantiate().init("player\nSol\nOne", "stacked", false),
		'player_sol_two' : pile_scene.instantiate().init("player\nSol\nTwo", "stacked", false),
		'player_sol_three' : pile_scene.instantiate().init("player\nSol\nThree", "stacked", false),
		'player_sol_four' : pile_scene.instantiate().init("player\nSol\nFour", "stacked", false),
		'player_sol_five' : pile_scene.instantiate().init("player\nSol\nFive", "stacked", false),
		}

	for pile in play_piles.values():
		# how to do this in signal manager?? https://ask.godotengine.org/73872/how-to-connect-a-signal-from-an-instanced-node
		pile.mouse_over.connect(self.set_target_pile)
		pile.mouse_off.connect(self.release_target_pile)
		$Deck.add_child(pile)

func card_interact(mouse_position:Vector2) -> void:
	if target_pile:
		if !holding_card:
			#added additional if statemtn to idicate game rules vs game lagic, could find a better way to decouple this
			match target_pile.stack_type:
				'stacked':
					if  !target_pile.opponent_pile and target_pile.has_cards():
						held_card = target_pile.pop_card()
						held_card.reveale_card()
						ordering_temp += 1
						held_card.z_index = ordering_temp
						holding_card = true
				'clean':
					if  !target_pile.opponent_pile:
						stuck = true
						unstick_game()
				'messy':
					print('slapped when win state ' + str(win_state))
					if win_state:
						round_won('PLAYER', target_pile)

		elif holding_card:
			match target_pile.stack_type:
				'clean':
					pass
				'messy':
					if target_pile.has_cards() and (abs(held_card.value_to_int() - target_pile.top_card.value_to_int()) == 1 or abs(held_card.value_to_int() - target_pile.top_card.value_to_int()) >= 12 or stuck):
						target_pile.add_card(held_card)
						holding_card = false
						held_card = null
						if stuck:
							stuck = false
						shared_piles_changed.emit()
						round_win_recorded = false
						win_state = in_win_state()
						if win_state:
							game_winnable.emit()
				'stacked':
					if !target_pile.has_cards() or (held_card.value_to_int() == target_pile.top_card.value_to_int() and !stuck):
						target_pile.add_card(held_card)
						holding_card = false
						held_card = null

func manuel_move_card(from_pile:PlayPile, to_pile:PlayPile):
	var in_flight_card:Card = from_pile.pop_card()
	var from_position:Vector2 = in_flight_card.position
	to_pile.add_card(in_flight_card)
	animate_card(in_flight_card, from_position, in_flight_card.position)
	if from_pile.has_cards() and from_pile.stack_type != 'clean':
		from_pile.stack.front().reveale_card()
	#negative feedback loop
	difficulty_scalar = 0.1 * (tally_cards(false, play_piles['player_pile']) - tally_cards(true, play_piles['player_pile']))
	difficulty_scalar = clamp(difficulty_scalar, difficutly_scalar_bounds.x, difficutly_scalar_bounds.y)
	var rng:RandomNumberGenerator = RandomNumberGenerator.new()
	await get_tree().create_timer(rng.randf_range(0 + difficulty_scalar,3.2 +  difficulty_scalar)).timeout# opponents "think time"
	to_pile.set_card_display_order()
	move_made.emit()
	win_state = in_win_state()

func move_card() -> void:
	if held_card and holding_card:
		var screen_size:Vector2 = get_viewport().get_visible_rect().size
		var card_center:Vector2 = get_global_mouse_position() - card_half_size * card_scaler

		if card_center.x >= screen_size.x - card_half_size.x * 2 * card_scaler:
			card_center.x = screen_size.x - card_half_size.x * 2 * card_scaler
		elif card_center.x < 0:
			card_center.x = 0
		if card_center.y >= screen_size.y - card_half_size.y * 2 * card_scaler:
			card_center.y = screen_size.y - card_half_size.y * 2 * card_scaler
		elif card_center.y < 0:
			card_center.y = 0

		held_card.position = card_center

#window resize https://www.reddit.com/r/godot/comments/10pw2sy/how_to_call_a_function_when_window_resized_in/
func set_play_area() -> void:
	var screen_size:Vector2 = get_viewport().get_visible_rect().size
	var card_to_play_area_ratio:float = play_area_req_dims.y * card_half_size.y * 2 / (play_area_req_dims.x * card_half_size.x * 2)

	if screen_size.y < card_to_play_area_ratio * screen_size.x:
		var desired_size:float = screen_size.y / play_area_req_dims.y
		card_scaler =  desired_size / (card_half_size.y * 2)
	else:
		var desired_size:float = screen_size.x / play_area_req_dims.x
		card_scaler =  desired_size / (card_half_size.x * 2)

	for card in cards:
		card.scale = Vector2.ONE * card_scaler
		card.position = screen_size/2 - card_half_size * card_scaler #may become a remnent and will not need to set posiiont here

	for pile in play_piles.values():
		pile.scale = Vector2.ONE * card_scaler

	#could avoid all this (- card_half_size * card_scaler) by setting card anchor point to the center instead of the upper left corner... but lets pretend we didn't figure that out
	var offset:Vector2 = - card_half_size * card_scaler
	play_piles['opponent_deck'].position = Vector2(screen_size.x * .1,screen_size.y * .45) + offset
	play_piles['player_deck'].position = Vector2(screen_size.x * .9,screen_size.y * .45) + offset

	play_piles['opponent_pile'].position = Vector2(screen_size.x * .4,screen_size.y * .45) + offset
	play_piles['player_pile'].position = Vector2(screen_size.x * .6,screen_size.y *.45) + offset

	play_piles['opponent_sol_one'].position = Vector2(screen_size.x * .3,screen_size.y * .1) + offset
	play_piles['opponent_sol_two'].position = Vector2(screen_size.x * .4,screen_size.y * .1) + offset
	play_piles['opponent_sol_three'].position = Vector2(screen_size.x * .5,screen_size.y * .1) + offset
	play_piles['opponent_sol_four'].position = Vector2(screen_size.x * .6,screen_size.y * .1) + offset
	play_piles['opponent_sol_five'].position = Vector2(screen_size.x * .7,screen_size.y * .1) + offset

	play_piles['player_sol_one'].position = Vector2(screen_size.x * .3,screen_size.y * .7) + offset
	play_piles['player_sol_two'].position = Vector2(screen_size.x * .4,screen_size.y * .7) + offset
	play_piles['player_sol_three'].position = Vector2(screen_size.x * .5,screen_size.y * .7) + offset
	play_piles['player_sol_four'].position = Vector2(screen_size.x * .6,screen_size.y * .7) + offset
	play_piles['player_sol_five'].position = Vector2(screen_size.x * .7,screen_size.y * .7) + offset

	for pile in play_piles.values():
		pile.reposition_cards()

func shuffle_deck(deck:Array) -> Array:
	var rng:RandomNumberGenerator = RandomNumberGenerator.new()
	for i in range(deck.size()-1,0,-1):
		var j:int = rng.randf_range(0,i+1)
		var temp = deck[i]
		deck[i] = deck[j]
		deck[j] = temp
	return deck

#todo ajsut set_up_game for varying card numbers
func set_up_game(player_card_count:int, opponent_card_count:int) -> void:
	assert(player_card_count + opponent_card_count == 52, 'player and opponent cards do not add up to 52')
	clear_game()
	held_card = null
	holding_card = false
	#positive feed back loop to counter
	if player_card_count <= 19:
		difficutly_scalar_bounds = Vector2(2,2)
	elif opponent_card_count <= 14:
		difficutly_scalar_bounds = Vector2(0,1)
	else:
		difficutly_scalar_bounds = Vector2(0,3)
	var temp_cards:Array = [] + shuffle_deck(cards)
	for card in temp_cards:
		card.hide_card()

	var opponent_solatare = [play_piles['opponent_sol_one'],play_piles['opponent_sol_two'],play_piles['opponent_sol_three'],play_piles['opponent_sol_four'],play_piles['opponent_sol_five']]
	while opponent_solatare.size() > 0:
		for pile in opponent_solatare:
				if opponent_card_count > 0:
					pile.add_card(temp_cards.pop_front())
					opponent_card_count -= 1
		var complete_pile:PlayPile = opponent_solatare.pop_front()
		complete_pile.top_card.reveale_card()

	var player_solatare = [play_piles['player_sol_one'],play_piles['player_sol_two'],play_piles['player_sol_three'],play_piles['player_sol_four'],play_piles['player_sol_five']]
	while player_solatare.size() > 0:
		for pile in player_solatare:
				if player_card_count > 0:
					pile.add_card(temp_cards.pop_front())
					player_card_count -= 1
		var complete_pile:PlayPile = player_solatare.pop_front()
		complete_pile.top_card.reveale_card()

	if opponent_card_count >= 1:
		play_piles['opponent_pile'].add_card(temp_cards.pop_front())
		play_piles['opponent_pile'].top_card.reveale_card()
		opponent_card_count -= 1

	if player_card_count >= 1:
		play_piles['player_pile'].add_card(temp_cards.pop_front())
		play_piles['player_pile'].top_card.reveale_card()
		player_card_count -= 1

	while opponent_card_count > 0:
		play_piles['opponent_deck'].add_card(temp_cards.pop_front())
		opponent_card_count -= 1

	while player_card_count > 0:
		play_piles['player_deck'].add_card(temp_cards.pop_front())
		player_card_count -= 1

	assert(temp_cards.size() == 0, 'none 0 number of card remaining. Remaining cards ' + str(temp_cards.size()))

func unstick_game():
	stuck = false
	if opponent_is_stuck:
		if play_piles['opponent_deck'].has_cards():
			play_piles['opponent_deck'].stack.front().reveale_card()
			manuel_move_card(play_piles['opponent_deck'], play_piles['opponent_pile'],)
		if play_piles['player_deck'].has_cards():
			play_piles['player_deck'].stack.front().reveale_card()
			manuel_move_card(play_piles['player_deck'], play_piles['player_pile'],)
		#todo animate_card()

func set_target_pile(target:PlayPile) -> void:
	target_pile = target

func release_target_pile() -> void:
	target_pile = null

func clear_game() -> void:
	for pile in play_piles.values():
		pile.empty()

func show_playable_piles() -> void:
	var playble_piles:Array = [play_piles['opponent_sol_one'],play_piles['opponent_sol_two'],play_piles['opponent_sol_three'],play_piles['opponent_sol_four'],play_piles['opponent_sol_five']]
	send_playable_piles.emit(playble_piles)

func show_target_piles() -> void:
	var target_piles:Array = [play_piles['opponent_pile'],play_piles['player_pile']]
	send_target_piles.emit(target_piles)

func animate_card(card:Card, from:Vector2, destination:Vector2) -> float:
	card.z_index = ordering_temp
	card.position = from
	var animation_time:float = .34
	var tween:Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position",destination, animation_time)
	#await tween.finished
	return animation_time

func opponent_stuck(stuck:bool) -> void:
	opponent_is_stuck = stuck

func in_win_state() -> bool:
	var player_in_win_state:bool = true
	var player_solatare = [play_piles['player_sol_one'],play_piles['player_sol_two'],play_piles['player_sol_three'],play_piles['player_sol_four'],play_piles['player_sol_five']]
	for pile in player_solatare:
		if pile.has_cards():
			player_in_win_state = false

	var opponent_in_win_state:bool = true
	var opponent_solatare = [play_piles['opponent_sol_one'],play_piles['opponent_sol_two'],play_piles['opponent_sol_three'],play_piles['opponent_sol_four'],play_piles['opponent_sol_five']]
	for pile in opponent_solatare:
		if pile.has_cards():
			opponent_in_win_state = false

	return player_in_win_state or opponent_in_win_state

func round_won(winner:String, slapped_pile:PlayPile) -> void:
	if !round_win_recorded:
		round_win_recorded = true
		win_state = false
		print(winner +' WON')
		var opp_pile:PlayPile
		var plr_pile:PlayPile
		var remaining_pile = play_piles['opponent_pile'] if slapped_pile == play_piles['player_pile'] else play_piles['player_pile']
		print('slapped pile size ' + str(slapped_pile.stack.size()) + ' vs ' + str(remaining_pile.stack.size()))
		if winner == 'OPPONENT':
			opp_pile = slapped_pile
			plr_pile = remaining_pile
		else:
			plr_pile = slapped_pile
			opp_pile = remaining_pile

		set_up_game(tally_cards(false, plr_pile), tally_cards(true, opp_pile))

func tally_cards(is_opponent_pile:bool, result_pile:PlayPile) -> int:
	var card_tally:int = 0
	for pile in play_piles.values():
		if pile.opponent_pile == is_opponent_pile:
			card_tally += pile.stack.size()

	if is_opponent_pile:
		card_tally -= play_piles['opponent_pile'].stack.size()
	else:
		card_tally -= play_piles['player_pile'].stack.size()

	card_tally += result_pile.stack.size()

	return card_tally

func opponent_trigger_win_state():
	win_state = true
