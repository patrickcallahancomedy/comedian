class_name GigDatabase
extends RefCounted

## One readable lookup table for Skeleton Alpha bookings.
## Add a new .tres file and one line here when a new gig becomes part of the game.

const GIG_PATHS: Dictionary = {
	"first_mic": "res://data/gigs/first_mic.tres",
	"first_paid_gig": "res://data/gigs/first_paid_gig.tres",
	"regional_gig": "res://data/gigs/regional_gig.tres",
	"feature_gig": "res://data/gigs/feature_gig.tres",
	"first_headline": "res://data/gigs/first_headline.tres",
	"hometown_special": "res://data/gigs/hometown_special.tres",
}


static func has_gig(gig_id: String) -> bool:
	return GIG_PATHS.has(gig_id)


static func get_gig(gig_id: String) -> GigData:
	var path := str(GIG_PATHS.get(gig_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as GigData
