class_name GigData
extends Resource

## Human-editable description of one comedy booking.
## Duplicate a .tres file in data/gigs and edit these fields in the Godot Inspector.

@export_category("Identity")
@export var gig_id: String = "gig"
@export var gig_title: String = "COMEDY GIG"
@export var venue_id: String = "venue"
@export var venue_name: String = "VENUE"
@export var city: String = "Dayton, Ohio"

@export_category("Booking")
@export_range(1, 120, 1) var set_length_minutes: int = 5
@export_range(0, 10000, 1) var pay: int = 0
@export_range(0, 10000, 1) var travel_cost: int = 0
@export_range(0, 100, 1) var energy_cost: int = 5
@export_range(0, 1000, 1) var reputation_required: int = 0

@export_category("Progression")
@export var completion_milestone: String = ""
@export var next_route_id: String = "calendar"
