class_name MovementTest
extends Node2D

@onready var spawner: CreatureSpawner = $World/CreatureSpawner
@onready var exit_zone: ExitZone = $World/ExitZone
@onready var kill_zone: KillZone = $World/KillZone
@onready var hud: SimulationHUD = $HUD

var saved_count: int = 0
var lost_count: int = 0


func _ready() -> void:
	spawner.creature_spawned.connect(_on_creature_spawned)
	exit_zone.creature_saved.connect(_on_creature_saved)
	kill_zone.creature_killed.connect(_on_creature_killed)
	hud.set_expected_total(spawner.spawn_count)
	_update_hud()


func _on_creature_spawned(_creature: Creature, _spawned_count: int) -> void:
	_update_hud()


func _on_creature_saved(_creature: Creature) -> void:
	saved_count += 1
	_update_hud()


func _on_creature_killed(_creature: Creature) -> void:
	lost_count += 1
	_update_hud()


func _update_hud() -> void:
	hud.set_population(spawner.spawned_count, saved_count, lost_count)
