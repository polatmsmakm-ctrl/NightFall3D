extends Node
func _ready():
	for seed in [123456789, 7, 1, 999999937, 42424242]:
		var r := Rules.new()
		r.setup(7, 2, 9, 5, [{"name": "A", "role": "killer"}, {"name": "B", "role": "survivor"}], seed, 12)
		print(seed, " kind=", r.ev_kind, " at=", r.ev_at, " adhan=", r.adhan_at)
	get_tree().quit()
