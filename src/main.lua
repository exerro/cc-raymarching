
local df = require "df"

local abs = math.abs
local atan = math.atan
local cos = math.cos
local floor = math.floor
local min = math.min
local sin = math.sin
local sqrt = math.sqrt

local string_char = string.char

local FB_COLOUR_COMPONENTS = 1
local MIN_DISTANCE_THRESHOLD = 0.01
local MAX_DISTANCE_THRESHOLD = 100
local MAX_ITERATIONS = 100
local NORMAL_DELTA = 0.000001
local SUBPIXEL_W = 2
local SUBPIXEL_H = 3
local MAX_QUANTIZATIONS = 16
local INDEX_LOOKUP = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F" }
local LIGHT_DIRECTION_X = -2 / 3.74165739
local LIGHT_DIRECTION_Y = -3 / 3.74165739
local LIGHT_DIRECTION_Z = -1 / 3.74165739
local COLOUR_GRANULARITY = 1 / 32

local framebuffer = {}
local fb_width = 0
local fb_height = 0

local camera_x = 0
local camera_y = 0
local camera_z = 4

local camera_rh = 0
local camera_rv = 0
local camera_fov = math.rad(70)

local function get_distance_function(t)
	local s = 1.5 + sin(t) * 0.5
	return df.union(
		df.translate(df.sphere(1), 1, 0, 0),
		df.smooth_union(
			0.5,
			df.translate(df.sphere(s), -1 - (s - 1) * 0.5, 0, 0),
			df.translate(df.box(2, 1, 1), 0, 1, -2)
		),
		df.translate(df.intersection(
			df.box(0.8, 0.8, 0.8),
			df.sphere(1)
		), 3, 0, 0)
	)
end

local function resize_framebuffer(w, h)
	framebuffer = {}

	for i = 1, w * SUBPIXEL_W * h * SUBPIXEL_H * FB_COLOUR_COMPONENTS do
		framebuffer[i] = 0
	end

	fb_width = w
	fb_height = h
end

local function px_to_ray(px, py, sV, cV, sH, cH)
	-- initialise a world-space ray direction
	local dx = px
	local dy = py
	local dz = -1

	-- normalise the ray direction length
	local ld = 1 / sqrt(dx * dx + dy * dy + dz * dz)
	dx = dx * ld
	dy = dy * ld
	dz = dz * ld

	-- rotate the ray vertically
	dy, dz = dy * cV + dz * sV, dz * cV - dy * sV

	-- rotate the ray horizontally
	dx, dz = dx * cH + dz * sH, dz * cH - dx * sH

	return dx, dy, dz
end

local function raymarch(df, rx, ry, rz, rdx, rdy, rdz)
	for i = 1, MAX_ITERATIONS do
		local distance = df(rx, ry, rz)

		if distance < MIN_DISTANCE_THRESHOLD then
			return true, rx + rdx * distance, ry + rdy * distance, rz + rdz * distance
		elseif distance > MAX_DISTANCE_THRESHOLD then
			return false
		end

		rx = rx + rdx * distance
		ry = ry + rdy * distance
		rz = rz + rdz * distance
	end

	return false
end

local function estimate_normal(df, x, y, z)
	local xda, xdb = df(x - NORMAL_DELTA, y, z), df(x + NORMAL_DELTA, y, z)
	local yda, ydb = df(x, y - NORMAL_DELTA, z), df(x, y + NORMAL_DELTA, z)
	local zda, zdb = df(x, y, z - NORMAL_DELTA), df(x, y, z + NORMAL_DELTA)

	local dx = xdb - xda
	local dy = ydb - yda
	local dz = zdb - zda

	local ld = 1 / sqrt(dx * dx + dy * dy + dz * dz)

	return dx * ld, dy * ld, dz * ld
end

local function shade_point(df, x, y, z)
	local nx, ny, nz = estimate_normal(df, x, y, z)
	local diffuse = -min(0, nx * LIGHT_DIRECTION_X + ny * LIGHT_DIRECTION_Y + nz * LIGHT_DIRECTION_Z)
	return 0.4 + 0.6 * diffuse
end

local function render_to_framebuffer(df, w, h)
	resize_framebuffer(w, h)

	local aspect = w / h * SUBPIXEL_W / SUBPIXEL_H
	local aF = atan(camera_fov)
	local fb_index = 1
	local fbw1 = fb_width * SUBPIXEL_W - 1
	local fbh1 = fb_height * SUBPIXEL_H - 1
	local y = aF
	local x0 = -aF * aspect
	local dx = 2 / fbw1 * aF * aspect
	local dy = 2 / fbh1 * aF * -1
	local sV, cV, sH, cH = sin(camera_rv), cos(camera_rv), sin(camera_rh), cos(camera_rh)

	for _ = 0, fbh1 do
		local x = x0

		for _ = 0, fbw1 do
			local rdx, rdy, rdz = px_to_ray(x, y, sV, cV, sH, cH)
			local i, ix, iy, iz = raymarch(df, camera_x, camera_y, camera_z, rdx, rdy, rdz)

			if i then
				local shading = shade_point(df, ix, iy, iz)
				framebuffer[fb_index] = floor(shading / COLOUR_GRANULARITY + 0.5) * COLOUR_GRANULARITY
			else
				framebuffer[fb_index] = 0
			end

			fb_index = fb_index + 1
			x = x + dx
		end

		y = y + dy
	end
end

local function render_framebuffer(w, h)
	local char_lines = {}
	local bg_lines = {}
	local fg_lines = {}
	local colour_set = {}
	local colour_set_index = {}
	local ci = 1
	local fb_index = 1

	for ly = 1, h do
		local char_line = {}
		local bg_line = {}
		local fg_line = {}

		for lx = 1, w do
			local framebuffer_offset = 0
			local colour_values = {}
			local colour_values_index = {}
			local vi = 1

			for _ = 1, SUBPIXEL_H do
				for _ = 1, SUBPIXEL_W do
					local fb_value = framebuffer[fb_index + framebuffer_offset]

					if colour_values_index[fb_value] then else
						colour_values[vi] = fb_value
						colour_values_index[fb_value] = true
						vi = vi + 1
					end

					framebuffer_offset = framebuffer_offset + 1
				end

				framebuffer_offset = framebuffer_offset + w * SUBPIXEL_W - SUBPIXEL_W
			end

			if vi == 2 then -- only one colour!
				local cv = colour_values[1]

				char_line[lx] = " "
				bg_line[lx] = cv
				fg_line[lx] = 0

				if not colour_set_index[cv] then
					colour_set[ci] = cv
					colour_set_index[cv] = true
					ci = ci + 1
				end
			else
				local sum = 0
				local len = vi - 1

				for i = 1, len do
					sum = sum + colour_values[i]
				end

				local avg = sum / len
				local a, an = 0, 0
				local b = 0

				for i = 1, len do
					local cv = colour_values[i]

					if cv < avg then
						a = a + cv
						an = an + 1
					else
						b = b + cv
					end
				end

				a = a / an
				b = b / (len - an)

				local toggle_bit = framebuffer[fb_index + w * SUBPIXEL_W * 2 + 1] < avg
				local spx0bit = framebuffer[fb_index] < avg == toggle_bit and 0 or 1
				local spx1bit = framebuffer[fb_index + 1] < avg == toggle_bit and 0 or 1
				local spx2bit = framebuffer[fb_index + w * SUBPIXEL_W] < avg == toggle_bit and 0 or 1
				local spx3bit = framebuffer[fb_index + w * SUBPIXEL_W + 1] < avg == toggle_bit and 0 or 1
				local spx4bit = framebuffer[fb_index + w * SUBPIXEL_W * 2] < avg == toggle_bit and 0 or 1

				if toggle_bit then
					a, b = b, a
				end

				char_line[lx] = string_char(128 + 16 * spx4bit + 8 * spx3bit + 4 * spx2bit + 2 * spx1bit + spx0bit)
				fg_line[lx] = a
				bg_line[lx] = b

				if not colour_set_index[a] then
					colour_set[ci] = a
					colour_set_index[a] = true
					ci = ci + 1
				end

				if not colour_set_index[b] then
					colour_set[ci] = b
					colour_set_index[b] = true
					ci = ci + 1
				end
			end

			fb_index = fb_index + SUBPIXEL_W
		end

		fb_index = fb_index + w * SUBPIXEL_W * (SUBPIXEL_H - 1)
		char_lines[ly] = table.concat(char_line)
		bg_lines[ly] = bg_line
		fg_lines[ly] = fg_line
	end

	table.sort(colour_set)

	local sum = 0

	for i = 1, ci - 1 do
		sum = sum + colour_set[i]
	end

	local colour_quantizations = 1
	local colour_ranges = { 1, ci - 1, 0, sum / (ci - 1) }

	while colour_quantizations < MAX_QUANTIZATIONS do
		local index = 0
		local spread = -1

		for i = 0, colour_quantizations - 1 do
			local i0 = colour_ranges[i * 4 + 1]
			local i1 = colour_ranges[i * 4 + 2]
			local av = colour_ranges[i * 4 + 4]

			local err2 = 0

			for i = i0, i1 do
				local delta = colour_set[i] - av
				err2 = err2 + delta * delta
			end

			err2 = err2 / (i1 - i0 + 1)

			if err2 > spread then
				index = i
				spread = err2
			end
		end

		if spread == 0 then
			break
		end

		-- splitting index into two ranges
		local i0 = colour_ranges[index * 4 + 1]
		local i1 = colour_ranges[index * 4 + 2]
		local av = colour_ranges[index * 4 + 4]
		local last_below_avg = i1

		for i = i0 + 1, i1 do
			if colour_set[i] > av then
				last_below_avg = i - 1
				break
			end
		end

		local below_sum = 0
		local above_sum = 0

		for i = i0, last_below_avg do
			below_sum = below_sum + colour_set[i]
		end

		for i = last_below_avg + 1, i1 do
			above_sum = above_sum + colour_set[i]
		end

		colour_ranges[index * 4 + 2] = last_below_avg
		colour_ranges[index * 4 + 4] = below_sum / (last_below_avg - i0 + 1)
		
		colour_ranges[colour_quantizations * 4 + 1] = last_below_avg + 1
		colour_ranges[colour_quantizations * 4 + 2] = i1
		colour_ranges[colour_quantizations * 4 + 4] = above_sum / (i1 - last_below_avg)

		colour_quantizations = colour_quantizations + 1
	end

	for y = 1, h do
		local bg_line = bg_lines[y]
		local fg_line = fg_lines[y]

		for x = 1, w do
			local bg = bg_line[x]
			local fg = fg_line[x]
			local bg_diff = math.huge
			local bg_index = 0
			local fg_diff = math.huge
			local fg_index = 0

			for i = 1, colour_quantizations do
				local avg = colour_ranges[i * 4]
				local this_bg_diff = abs(bg - avg)
				local this_fg_diff = abs(fg - avg)

				if this_bg_diff < bg_diff then
					bg_diff = this_bg_diff
					bg_index = i
				end

				if this_fg_diff < fg_diff then
					fg_diff = this_fg_diff
					fg_index = i
				end
			end

			bg_line[x] = INDEX_LOOKUP[bg_index]
			fg_line[x] = INDEX_LOOKUP[fg_index]
		end
	end

	for i = 1, colour_quantizations do
		local c = 0.1 + 0.9 * colour_ranges[i * 4]
		term.setPaletteColour(2 ^ (i - 1), c, c, c)
	end

	for y = 1, h do
		term.setCursorPos(1, y)
		term.blit(char_lines[y], table.concat(fg_lines[y]), table.concat(bg_lines[y]))
	end
end

local function render()
	local w, h = term.getSize()
	-- local w, h = 50, 20

	render_to_framebuffer(get_distance_function(os.clock()), w, h)
	render_framebuffer(w, h)
end

-- render_to_framebuffer(distance_function, 10, 10)

-- for y = 1, 10 do
-- 	local line = {}

-- 	for x = 1, 10 do
-- 		local px = framebuffer[(y - 1) * 10 * SUBPIXEL_H * SUBPIXEL_W + (x - 1) * SUBPIXEL_W + 1]

-- 		if px == 0 then
-- 			line[x] = " "
-- 		else
-- 			line[x] = "@"
-- 		end
-- 	end

-- 	print(table.concat(line))
-- end

while true do
	render()
	os.queueEvent "render"

	while true do
		local ev = { os.pullEvent() }

		if ev[1] == "render" then break end

		if ev[1] == "key" then
			local m, mx, mz = false, 0, 0

			if ev[2] == keys.left then
				camera_rh = camera_rh + math.pi / 18
			elseif ev[2] == keys.right then
				camera_rh = camera_rh - math.pi / 18
			elseif ev[2] == keys.up then
				camera_rv = camera_rv - math.pi / 18
			elseif ev[2] == keys.down then
				camera_rv = camera_rv + math.pi / 18
			elseif ev[2] == keys.space then
				camera_y = camera_y + 0.25
			elseif ev[2] == keys.leftShift then
				camera_y = camera_y - 0.25
			elseif ev[2] == keys.w then
				m, mx, mz = true, 0, -1
			elseif ev[2] == keys.s then
				m, mx, mz = true, 0, 1
			elseif ev[2] == keys.a then
				m, mx, mz = true, -1, 0
			elseif ev[2] == keys.d then
				m, mx, mz = true, 1, 0
			end

			if m then
				local cR, sR = cos(camera_rh), sin(camera_rh)
				mx, mz = mx * cR + mz * sR, mz * cR - mx * sR
				camera_x = camera_x + mx * 0.25
				camera_z = camera_z + mz * 0.25
			end
		end
	end
end
