extends RefCounted
class_name SurfaceCatalog

static var ASPHALT: SurfaceProfile = SurfaceProfile.new(
	"asphalt",
	1.00,	# grip_mul
	1.00,	# rolling_mul
	1.00,	# engine_mul
	1.00,	# brake_mul
	Color(0, 0, 0, 0.8),		# skid_color
	Color(0.8, 0.8, 0.8),		# smoke_color
	-5.0,						# sound_volume
	0.4							# sound_scale
)


static var GRAVEL: SurfaceProfile = SurfaceProfile.new(
	"gravel",
	0.05,
	3.50,
	0.60,
	0.80,
	Color(0.4, 0.3, 0.2, 0.6),
	Color(0.445, 0.317, 0.211, 1.0),
	-9.0,
	0.1
)


static var GRASS: SurfaceProfile = SurfaceProfile.new(
	"grass",
	0.10,
	1.60,
	0.85,
	0.20,
	Color(0.2, 0.5, 0.2, 0.5),
	Color(0.275, 0.431, 0.275, 1.0),
	-8.0,
	0.15
)


static var MUD: SurfaceProfile = SurfaceProfile.new(
	"mud",
	0.50,
	1.75,
	0.72,
	0.82,
	Color(0.3, 0.2, 0.1, 0.8),
	Color(0.8, 0.8, 0.8),
	0.0,
	1.0
)


static var ICE: SurfaceProfile = SurfaceProfile.new(
	"ice",
	0.02,
	0.85,
	0.95,
	0.55,
	Color(0.005, 0.186, 0.824, 0.502),
	Color(0.664, 0.642, 1.0, 1.0),
	-6.0,
	0.3
)


static var DEFAULT: SurfaceProfile = SurfaceProfile.new(
	"default",
	0.70,
	1.20,
	0.80,
	0.80,
	Color(0, 0, 0, 0.5),
	Color(0.721, 0.151, 0.467, 1.0),
	-6.0,
	0.4
)
