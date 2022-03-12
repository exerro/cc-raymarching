
local abs = math.abs
local max = math.max
local min = math.min
local sqrt = math.sqrt

-- see: https://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm

local df = {}

-- primitives --------------------------------------------------

function df.sphere(radius)
	return function(x, y, z)
		return sqrt(x * x + y * y + z * z) - radius
	end
end

function df.box(w, h, d)
	return function(x, y, z)
		local qx = abs(x) - w
		local qy = abs(y) - h
		local qz = abs(z) - d

		local qx0 = max(qx, 0)
		local qy0 = max(qy, 0)
		local qz0 = max(qz, 0)

		return sqrt(qx0 * qx0 + qy0 * qy0 + qz0 * qz0) + min(max(qx, max(qy, qz)), 0)
	end
end

-- geometric operators -----------------------------------------

function df.union(a, b, ...)
	if ... then
		return df.union(a, df.union(b, ...))
	end

	return function(x, y, z)
		return min(a(x, y, z), b(x, y, z))
	end
end

function df.intersection(a, b, ...)
	if ... then
		return df.intersection(a, df.intersection(b, ...))
	end

	return function(x, y, z)
		return max(a(x, y, z), b(x, y, z))
	end
end

function df.smooth_union(k, a, b)
	return function(x, y, z)
		local ad = a(x, y, z)
		local bd = b(x, y, z)
		local h = max(0, min(1, 0.5 + 0.5 * (bd - ad) / k))
    	return bd * (1 - h) + ad * h - k * h * (1 - h)
	end
end

function df.inf_repeat(s, wx, wy, wz)
	return function(x, y, z)
		local qx = (x + 0.5 * wx) % wx - 0.5 * wx
		local qy = (y + 0.5 * wy) % wy - 0.5 * wy
		local qz = (z + 0.5 * wz) % wz - 0.5 * wz
    	return s(qx, qy, qz);
	end
end

-- transformative operators ------------------------------------

function df.translate(s, dx, dy, dz)
	return function(x, y, z)
		return s(x - dx, y - dy, z - dz)
	end
end

return df
