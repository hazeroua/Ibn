class_name InputDeviceTracker
extends RefCounted
## Dernier périphérique utilisé par le joueur : clavier et souris, ou une manette (par son numéro).
##
## observe() est appelé pour chaque événement d'entrée : temps constant, aucune allocation, signal
## émis seulement quand le périphérique change (y compris à chaque image si le joueur alterne).
## Les relâchements, les légers mouvements de souris et les axes au repos (dérive d'un stick usé)
## ne font jamais basculer.

## Émis quand le dernier périphérique utilisé change ; device = numéro de la manette, ou -1.
signal device_changed(kind: Kind, device: int)

enum Kind { KEYBOARD_MOUSE, GAMEPAD }

## Événements fabriqués par le moteur lui-même (InputEvent::DEVICE_ID_INTERNAL, non exposé au GDScript).
const DEVICE_ID_INTERNAL: int = -2

var kind: Kind = Kind.KEYBOARD_MOUSE
## Numéro de la dernière manette utilisée, -1 au clavier et à la souris.
var gamepad_device: int = -1

var _axis_activation: float = 0.5
var _mouse_activation_squared: float = 9.0


## axis_activation : inclinaison minimale d'un axe ; mouse_activation_px : déplacement minimal de la
## souris (en pixels, par événement).
func configure(axis_activation: float, mouse_activation_px: float) -> void:
	_axis_activation = axis_activation
	_mouse_activation_squared = mouse_activation_px * mouse_activation_px


## Prend en compte un événement ; émet device_changed si le dernier périphérique utilisé change.
func observe(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION or event.device == DEVICE_ID_INTERNAL:
		return
	if event is InputEventJoypadButton:
		if event.is_pressed():
			_switch(Kind.GAMEPAD, event.device)
	elif event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event
		if absf(motion.axis_value) >= _axis_activation:
			_switch(Kind.GAMEPAD, event.device)
	elif event is InputEventMouseMotion:
		var mouse_motion: InputEventMouseMotion = event
		if mouse_motion.relative.length_squared() >= _mouse_activation_squared:
			_switch(Kind.KEYBOARD_MOUSE, -1)
	elif event is InputEventKey or event is InputEventMouseButton:
		if event.is_pressed() and not event.is_echo():
			_switch(Kind.KEYBOARD_MOUSE, -1)


## Manette débranchée : si c'était la dernière utilisée, bascule sur une autre manette encore
## branchée (la première de connected), sinon sur le clavier et la souris.
func on_gamepad_disconnected(device: int, connected: Array[int]) -> void:
	if kind != Kind.GAMEPAD or gamepad_device != device:
		return
	for other: int in connected:
		if other != device:
			_switch(Kind.GAMEPAD, other)
			return
	_switch(Kind.KEYBOARD_MOUSE, -1)


## Relâche ce que la manette device maintenait encore (boutons et axes) en injectant les
## événements de relâchement correspondants. Godot efface déjà l'état d'une
## manette débranchée avant d'émettre Input.joy_connection_changed : cette fonction garantit le
## même résultat dans tous les cas (événement simulé, pilote qui ne prévient pas), et ne touche
## jamais aux actions maintenues au clavier, à la souris ou par une autre manette.
static func release_gamepad(device: int) -> void:
	for button: int in int(JOY_BUTTON_SDL_MAX):
		if Input.is_joy_button_pressed(device, button as JoyButton):
			var release := InputEventJoypadButton.new()
			release.device = device
			release.button_index = button as JoyButton
			release.pressed = false
			Input.parse_input_event(release)
	for axis: int in int(JOY_AXIS_SDL_MAX):
		if Input.get_joy_axis(device, axis as JoyAxis) != 0.0:
			var rest := InputEventJoypadMotion.new()
			rest.device = device
			rest.axis = axis as JoyAxis
			rest.axis_value = 0.0
			Input.parse_input_event(rest)


func _switch(new_kind: Kind, device: int) -> void:
	if new_kind == kind and device == gamepad_device:
		return
	kind = new_kind
	gamepad_device = device
	device_changed.emit(kind, gamepad_device)
