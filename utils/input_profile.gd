extends Resource
class_name InputProfile

@export var sens: float = 5.
@export var scope_factor: float = 1.
@export var csens: float = 5.
@export var cscope_factor: float = 1.
@export var actions: Dictionary[StringName,InputAction]
