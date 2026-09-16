class_name SkeletonFlow
extends RefCounted

## The ugly-but-complete career spine for Skeleton Alpha.
## These are not final scenes or final writing. They are readable route cards that
## prove the whole game can travel from Darren at BOXES to the hometown special.

const EVENTS: Dictionary = {
	"lunch": {
		"title": "LUNCH BREAK",
		"description": "Ray mentions a Tuesday open mic. Darren laughs it off, but now he knows where one is.",
		"milestone": "mic_discovered",
		"next_route": "home_intro",
	},
	"home_intro": {
		"title": "AFTER WORK",
		"description": "Darren gets home with the notebook in his pocket. The idea from work is still there. Tuesday is tomorrow.",
		"next_route": "first_mic_setup",
	},
	"first_mic_setup": {
		"title": "TUESDAY NIGHT",
		"description": "Darren decides to see what an open mic actually looks like. He signs his name up for five minutes.",
		"career_phase": "FIRST_MIC",
		"gig_id": "first_mic",
		"required_milestone": "mic_discovered",
		"next_route": "venue",
	},
	"after_first_mic": {
		"title": "AFTER THE FIRST MIC",
		"description": "The set is over. Darren is not suddenly a comedian. He goes home, goes back to work, and keeps thinking about it.",
		"required_milestone": "first_mic_complete",
		"next_route": "return_choice",
	},
	"wait_week": {
		"title": "ONE WEEK LATER",
		"description": "Darren does not go back right away. Tuesday comes around again anyway.",
		"next_route": "return_choice",
	},
	"title_reveal": {
		"title": "COMEDIAN",
		"description": "WRITE. GRIND. REPEAT. Darren chooses to go back. From here, the calendar becomes the main loop.",
		"career_phase": "OPEN_MICER",
		"milestone": "comedian_begun",
		"next_route": "calendar",
	},
	"open_micer": {
		"title": "THE OPEN-MIC YEARS",
		"description": "PLACEHOLDER PHASE: work, notice things, write, test material, bomb, improve, repeat. The real game will spend many weeks here.",
		"milestone": "open_micer_phase_complete",
		"reputation_floor": 6,
		"required_milestone": "comedian_begun",
		"next_route": "local_regular",
	},
	"local_regular": {
		"title": "LOCAL REGULAR",
		"description": "Darren is no longer just another new name. Hosts know him. Better spots appear. Small opportunities start to matter.",
		"career_phase": "LOCAL_REGULAR",
		"milestone": "local_regular_reached",
		"reputation_floor": 10,
		"required_milestone": "open_micer_phase_complete",
		"next_route": "first_paid_setup",
	},
	"first_paid_setup": {
		"title": "FIRST PAID SPOT",
		"description": "Someone offers Darren money to do comedy for the first time. It is not much. It still changes the way the night feels.",
		"gig_id": "first_paid_gig",
		"required_milestone": "local_regular_reached",
		"next_route": "venue",
	},
	"regional_comic": {
		"title": "OUTSIDE THE HOMETOWN",
		"description": "The next useful room is not down the street. Darren starts building a regional map of clubs, bars, comics, and long drives home.",
		"career_phase": "REGIONAL_COMIC",
		"milestone": "regional_comic_reached",
		"reputation_floor": 15,
		"required_milestone": "first_paid_gig_complete",
		"next_route": "regional_gig_setup",
	},
	"regional_gig_setup": {
		"title": "FIRST ROAD GIG",
		"description": "A fifteen-minute set waits in another city. Now comedy costs gas, energy, sleep, and time away from everything else.",
		"gig_id": "regional_gig",
		"required_milestone": "regional_comic_reached",
		"next_route": "travel",
	},
	"work_pressure": {
		"title": "SOMETHING HAS TO GIVE",
		"description": "Road dates are colliding with BOXES. Troy needs Darren at work. Comedy needs him somewhere else. The two lives no longer fit cleanly together.",
		"milestone": "work_comedy_pressure",
		"required_milestone": "regional_gig_complete",
		"next_route": "leave_boxes",
	},
	"leave_boxes": {
		"title": "LAST DAY AT BOXES",
		"description": "Skeleton milestone: Darren finally leaves the warehouse. The final game will make this expensive, uncertain, and earned.",
		"job_status": "LEFT_BOXES",
		"milestone": "left_boxes",
		"required_milestone": "work_comedy_pressure",
		"next_route": "working_comic",
	},
	"working_comic": {
		"title": "WORKING COMIC",
		"description": "Comedy is now the job. Features, hotels, long drives, stronger material, bad weekends, good weekends, and the need to keep producing.",
		"career_phase": "WORKING_COMIC",
		"milestone": "working_comic_reached",
		"reputation_floor": 30,
		"required_milestone": "left_boxes",
		"next_route": "feature_setup",
	},
	"feature_setup": {
		"title": "FEATURE WEEKEND",
		"description": "Darren has thirty minutes and a real club weekend. This is the bridge between getting spots and carrying a show.",
		"gig_id": "feature_gig",
		"required_milestone": "working_comic_reached",
		"next_route": "travel",
	},
	"first_headline_setup": {
		"title": "FIRST HEADLINE",
		"description": "The room is finally asking Darren to be the reason people bought tickets. Forty-five minutes. No hiding in a short set.",
		"career_phase": "HEADLINER",
		"gig_id": "first_headline",
		"reputation_floor": 45,
		"required_milestone": "feature_gig_complete",
		"next_route": "venue",
	},
	"build_45": {
		"title": "BUILD THE HOUR",
		"description": "PLACEHOLDER PHASE: Darren turns years of tested material into a dependable headline act and starts shaping it into one coherent special.",
		"milestone": "forty_five_ready",
		"reputation_floor": 60,
		"required_milestone": "first_headline_complete",
		"next_route": "special_setup",
	},
	"special_setup": {
		"title": "THE HOMETOWN SPECIAL",
		"description": "A room in the city where this started. Cameras. People who knew Darren before comedy. One final set built from everything the player made.",
		"career_phase": "SPECIAL",
		"gig_id": "hometown_special",
		"required_milestone": "forty_five_ready",
		"next_route": "venue",
	},
}


static func has_event(route_id: String) -> bool:
	return EVENTS.has(route_id)


static func get_event(route_id: String) -> Dictionary:
	return EVENTS.get(route_id, {}).duplicate(true)
