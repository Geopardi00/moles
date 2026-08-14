class_name KillZone
extends Area2D

signal creature_killed(creature: Creature)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	var creature := body as Creature
	if creature != null and creature.die():
		creature_killed.emit(creature)
