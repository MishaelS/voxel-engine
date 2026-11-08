class_name Crosshair
extends TextureRect
## Crosshair in the center of the screen (cursor.png, color inverted
## against the background).
##
## The inversion reads the screen behind the crosshair. A BackBufferCopy
## limited to the crosshair's rectangle copies only those few pixels, not
## the whole (Retina-sized) frame every frame.

var _back_buffer := BackBufferCopy.new()


func _ready() -> void:
	texture = UiTheme.gui_texture("cursor.png")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var half := texture.get_size() / 2.0
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -half.x
	offset_right = half.x
	offset_top = -half.y
	offset_bottom = half.y
	var shader_material := ShaderMaterial.new()
	shader_material.shader = preload("res://shaders/crosshair.gdshader")
	material = shader_material
	_back_buffer.copy_mode = BackBufferCopy.COPY_MODE_RECT
	add_sibling.call_deferred(_back_buffer)
	(func() -> void: get_parent().move_child(_back_buffer, get_index())).call_deferred()
	resized.connect(_update_back_buffer)
	item_rect_changed.connect(_update_back_buffer)
	_update_back_buffer.call_deferred()


func _update_back_buffer() -> void:
	# The copy rectangle is in screen pixels: apply the GUI scale (content
	# scale) that controls are laid out with.
	var rect := get_viewport().get_final_transform() * get_global_rect()
	_back_buffer.rect = rect.grow(2.0)
