// Pixel stars for sky shaders, like the classic game's: small square
// points of light (not cells of a grid), a few per thousand directions,
// each with its own size and brightness, softly twinkling.
//
// Directions are mapped onto the faces of a cube; every face is a grid of
// cells, and a few random cells hold one star: a small square at a random
// spot inside the cell. On a cube face a square stays a square on screen.

const float STAR_CELLS = 110.0;     // cells across one cube face
const float STAR_DENSITY = 0.014;   // share of cells with a star
const float STAR_MIN_SIZE = 0.10;   // star size, in cells
const float STAR_MAX_SIZE = 0.19;

float star_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Brightness of the star at this direction (0 = none).
float stars(vec3 dir, float time) {
	vec3 a = abs(dir);
	// Cube face (axis and sign) and the position on it, -1..1.
	vec2 uv;
	float face;
	if (a.x >= a.y && a.x >= a.z) {
		uv = dir.zy / a.x;
		face = dir.x > 0.0 ? 0.0 : 1.0;
	} else if (a.y >= a.z) {
		uv = dir.xz / a.y;
		face = dir.y > 0.0 ? 2.0 : 3.0;
	} else {
		uv = dir.xy / a.z;
		face = dir.z > 0.0 ? 4.0 : 5.0;
	}
	vec2 grid = (uv * 0.5 + 0.5) * STAR_CELLS;
	vec2 cell = floor(grid);
	vec3 id = vec3(cell, face * 131.0);
	if (star_hash(id) >= STAR_DENSITY) {
		return 0.0;
	}
	float size = mix(STAR_MIN_SIZE, STAR_MAX_SIZE, star_hash(id + 3.0));
	vec2 center = 0.2 + 0.6 * vec2(star_hash(id + 7.0), star_hash(id + 11.0));
	vec2 d = abs(fract(grid) - center);
	if (max(d.x, d.y) > size * 0.5) {
		return 0.0;
	}
	float brightness = 0.45 + 0.55 * star_hash(id + 17.0);
	// Twinkle: each star at its own speed and phase.
	float speed = 1.5 + 2.5 * star_hash(id + 23.0);
	float twinkle = 0.65 + 0.35 * sin(time * speed + star_hash(id + 29.0) * 6.2832);
	return brightness * twinkle;
}
