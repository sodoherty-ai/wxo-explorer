extends Camera3D

signal mode_changed(mode_name: String, help_text: String)

enum Mode { ORBIT, FREE_FLY }

var mode: Mode = Mode.ORBIT

# Orbit state
var orbit_target: Vector3 = Vector3.ZERO
var orbit_distance: float = 20.0
var orbit_yaw: float = 30.0
var orbit_pitch: float = 30.0

# Free-fly state
var fly_speed: float = 10.0

# Shared settings
var mouse_sensitivity: float = 0.3
var keyboard_speed: float = 10.0
var joy_look_sensitivity: float = 2.0
var joy_deadzone: float = 0.2

# Internal mouse state
var _left_dragging: bool = false
var _right_dragging: bool = false
var _middle_dragging: bool = false

const HELP_ORBIT = "Left/Mid-drag: Orbit | Right-drag: Pan | WASD/Arrows: Pan | Scroll: Zoom | Tab: Free-fly"
const HELP_FLY = "WASD/Arrows: Move | Right-click+Mouse: Look | Space/Shift: Up/Down | Scroll: Speed | Tab: Orbit"
const HELP_ORBIT_PAD = "Left Stick: Pan | Right Stick: Orbit | Triggers: Zoom | Triangle: Free-fly"
const HELP_FLY_PAD = "Left Stick: Move | Right Stick: Look | Triggers: Up/Down | Triangle: Orbit"


func _ready():
	_update_orbit_transform()
	mode_changed.emit("Orbit", HELP_ORBIT)


func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		# Don't capture keys when a GUI control (e.g. chat input) has focus
		var gui_has_focus = get_viewport().gui_get_focus_owner() != null
		if gui_has_focus:
			return
		if event.keycode == KEY_TAB:
			_toggle_mode()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return

	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_Y:
			_toggle_mode()
			get_viewport().set_input_as_handled()
			return

	match mode:
		Mode.ORBIT:
			_handle_orbit_mouse(event)
		Mode.FREE_FLY:
			_handle_fly_mouse(event)


func _process(delta: float):
	var gui_has_focus = get_viewport().gui_get_focus_owner() != null
	match mode:
		Mode.ORBIT:
			if not gui_has_focus:
				_process_orbit_keyboard(delta)
			_process_orbit_gamepad(delta)
		Mode.FREE_FLY:
			if not gui_has_focus:
				_process_fly_keyboard(delta)
			_process_fly_gamepad(delta)


func _toggle_mode():
	if mode == Mode.ORBIT:
		mode = Mode.FREE_FLY
		mode_changed.emit("Free-fly", HELP_FLY)
	else:
		mode = Mode.ORBIT
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_recalculate_orbit_from_transform()
		_update_orbit_transform()
		mode_changed.emit("Orbit", HELP_ORBIT)


# ---- Orbit mode ----

func _handle_orbit_mouse(event: InputEvent):
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_left_dragging = event.pressed
			MOUSE_BUTTON_MIDDLE:
				_middle_dragging = event.pressed
			MOUSE_BUTTON_RIGHT:
				_right_dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				orbit_distance = maxf(2.0, orbit_distance * 0.9)
				_update_orbit_transform()
			MOUSE_BUTTON_WHEEL_DOWN:
				orbit_distance = minf(100.0, orbit_distance * 1.1)
				_update_orbit_transform()

	elif event is InputEventMouseMotion:
		if _left_dragging or _middle_dragging:
			orbit_yaw -= event.relative.x * mouse_sensitivity
			orbit_pitch = clampf(orbit_pitch + event.relative.y * mouse_sensitivity, -89.0, 89.0)
			_update_orbit_transform()
		elif _right_dragging:
			var pan_speed = orbit_distance * 0.002
			orbit_target += transform.basis.x * (-event.relative.x * pan_speed)
			orbit_target += transform.basis.y * (event.relative.y * pan_speed)
			_update_orbit_transform()


func _process_orbit_keyboard(delta: float):
	var pan_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan_dir -= transform.basis.z
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan_dir += transform.basis.z
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan_dir -= transform.basis.x
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan_dir += transform.basis.x

	if pan_dir.length_squared() > 0:
		orbit_target += pan_dir.normalized() * keyboard_speed * delta
		_update_orbit_transform()


func _process_orbit_gamepad(delta: float):
	var left_x = Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var left_y = Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if absf(left_x) > joy_deadzone or absf(left_y) > joy_deadzone:
		var pan_dir = transform.basis.x * left_x - transform.basis.z * left_y
		orbit_target += pan_dir * keyboard_speed * delta
		_update_orbit_transform()

	var right_x = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var right_y = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(right_x) > joy_deadzone or absf(right_y) > joy_deadzone:
		orbit_yaw -= right_x * joy_look_sensitivity
		orbit_pitch = clampf(orbit_pitch + right_y * joy_look_sensitivity, -89.0, 89.0)
		_update_orbit_transform()

	var lt = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	var rt = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	if lt > joy_deadzone:
		orbit_distance = minf(100.0, orbit_distance * (1.0 + lt * delta))
		_update_orbit_transform()
	if rt > joy_deadzone:
		orbit_distance = maxf(2.0, orbit_distance * (1.0 - rt * delta))
		_update_orbit_transform()


func _update_orbit_transform():
	var yaw_rad = deg_to_rad(orbit_yaw)
	var pitch_rad = deg_to_rad(orbit_pitch)
	var offset = Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad)
	) * orbit_distance
	position = orbit_target + offset
	look_at(orbit_target, Vector3.UP)


func _recalculate_orbit_from_transform():
	var forward = -transform.basis.z
	orbit_target = position + forward * orbit_distance
	var dir = (position - orbit_target).normalized()
	orbit_yaw = rad_to_deg(atan2(dir.x, dir.z))
	orbit_pitch = rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))


# ---- Free-fly mode ----

func _handle_fly_mouse(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			fly_speed = minf(50.0, fly_speed * 1.2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fly_speed = maxf(1.0, fly_speed * 0.8)

	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		rotate_object_local(Vector3.RIGHT, deg_to_rad(-event.relative.y * mouse_sensitivity))


func _process_fly_keyboard(delta: float):
	var velocity = Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		velocity -= transform.basis.z
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		velocity += transform.basis.z
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		velocity -= transform.basis.x
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		velocity += transform.basis.x
	if Input.is_key_pressed(KEY_SPACE):
		velocity += Vector3.UP
	if Input.is_key_pressed(KEY_SHIFT):
		velocity -= Vector3.UP

	if velocity.length_squared() > 0:
		position += velocity.normalized() * fly_speed * delta


func _process_fly_gamepad(delta: float):
	var left_x = Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var left_y = Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if absf(left_x) > joy_deadzone or absf(left_y) > joy_deadzone:
		var velocity = transform.basis.x * left_x - transform.basis.z * left_y
		position += velocity * fly_speed * delta

	var right_x = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var right_y = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(right_x) > joy_deadzone or absf(right_y) > joy_deadzone:
		rotate_y(deg_to_rad(-right_x * joy_look_sensitivity))
		rotate_object_local(Vector3.RIGHT, deg_to_rad(-right_y * joy_look_sensitivity))

	var lt = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	var rt = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	if lt > joy_deadzone:
		position -= Vector3.UP * fly_speed * lt * delta
	if rt > joy_deadzone:
		position += Vector3.UP * fly_speed * rt * delta
