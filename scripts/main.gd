extends Node

var intro_screen_scene: PackedScene = preload("res://scenes/screens/intro_screen.tscn")
var graph_screen_scene: PackedScene = preload("res://scenes/screens/graph_screen.tscn")

var current_screen: Node = null


func _ready():
	_show_intro()


func _show_intro():
	_clear_screen()
	var intro = intro_screen_scene.instantiate()
	intro.data_ready.connect(_on_data_ready)
	add_child(intro)
	current_screen = intro


func _show_graph(graph_data: WxODataModel.GraphData, config: ConfigData = null):
	_clear_screen()
	var graph = graph_screen_scene.instantiate()
	graph.graph_data = graph_data
	graph.config = config
	graph.back_pressed.connect(_on_back_pressed)
	add_child(graph)
	current_screen = graph


func _clear_screen():
	if current_screen:
		current_screen.queue_free()
		current_screen = null


func _on_data_ready(graph_data: WxODataModel.GraphData):
	var intro = current_screen as Control
	var config = intro.config if intro else ConfigData.load_config()
	_show_graph(graph_data, config)


func _on_back_pressed():
	_show_intro()
