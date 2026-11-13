extends Node
func _ready():
	var tree := get_tree()
	var m = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child.call_deferred(m)
	for i in 5: await tree.process_frame
	Net.username = "Rashid"; Net.friends = ["Ali", "Fahad"]; Net.online = {"ali": true}; Net.state = "online"
	Net.room = {"code": "4979", "host": "Rashid", "map": "forest", "state": "lobby", "players": [
		{"name": "Rashid", "role": "killer", "char": "killer"}, {"name": "Ali", "role": "survivor", "char": "survivor2"}]}
	m.menu.open("lobby")
	for i in 5: await tree.process_frame
	tree.root.get_texture().get_image().save_png("/tmp/ui_lobby.png")
	m.menu.open("friends")
	for i in 5: await tree.process_frame
	tree.root.get_texture().get_image().save_png("/tmp/ui_friends.png")
	Net.room = {}
	m._start({"map": "village", "me": "Rashid", "offline": true, "players": [{"name": "Rashid", "role": "killer", "char": "killer", "slot": 0}]})
	for i in 150: await tree.process_frame
	tree.root.get_texture().get_image().save_png("/tmp/ui_game.png")
	print("SHOTS DONE")
	tree.quit()
