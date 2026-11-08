class_name Crosshair
extends TextureRect
## Crosshair in the center of the screen (cursor.png, color inverted
## against the background).


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
