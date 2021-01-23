
local braille_chars = {}
local braille_char_offset = 0x2800

for i = 0, 255 do braille_chars[i] = utf8.char(braille_char_offset + i) end

local space_char = braille_chars[1]
local blank_color = color_black
local min_color_val = 10

local function create_pixel(str, braille, color) --Pixel class
    local tbl = {}

    str = str or space_char

    braille = braille or 0
    function tbl:get_braille() return braille end
    function tbl:set_braille(char_code)
        braille = char_code
        str = braille_chars[char_code] or space_char
    end

    color = color or blank_color
    function tbl:get_color() return color end
    function tbl:add_color(col) 
        if color == blank_color then
            color = col
            return
        end

        color.r = (color.r + col.r) * .5
        color.g = (color.g + col.g) * .5
        color.b = (color.b + col.b) * .5
    end

    return tbl
end

local pixel_map = { --2 wide, 4 tall in subpixels
    {0x01, 0x08},
    {0x02, 0x10},
    {0x04, 0x20},
    {0x40, 0x80}
}

local function create_canvas() --Canvas class
    local tbl = {}

    local width, height
    local min_row, max_row
    local min_col, max_col
    function tbl:get_size() return width, height end
    function tbl:get_bounds() return min_row, max_row, min_col, max_col end

    local pixel_matrix
    function tbl:empty()
        pixel_matrix = {}
        width, height = 0, 0
        min_row, max_row = 0, 0
        min_col, max_col = 0, 0
    end

    local function update_canvas_size(row, col)
        if row < min_row then min_row = row end
        if row > max_row then max_row = row end
        if col < min_col then min_col = col end
        if col > max_col then max_col = col end

        width = -min_row + max_row
        height = -min_col + max_col
    end

    local floor = math.floor
    local band, bor = bit.band, bit.bor
    function tbl:set_pixel(x, y, color)
        local row, col = floor(y * .25), floor(x * .5)

        if color.a < min_color_val then return end
        if color.r < min_color_val and color.g < min_color_val and color.b < min_color_val then return end

        if not pixel_matrix[row] then pixel_matrix[row] = {} end

        local pixel = pixel_matrix[row][col]
        if not pixel then
            pixel = create_pixel(nil, nil, color)
            pixel_matrix[row][col] = pixel
        end

        pixel:set_braille(bor(pixel:get_braille(), pixel_map[band(y, 3) + 1][band(x, 1) + 1]))
        pixel:add_color(color)

        update_canvas_size(col, row)
    end

    function tbl:get_draw_data()
        local output = {}
        local matrix = pixel_matrix

        for row = 1, height do
            local row_data = {}
            output[row] = row_data

            for col = 1, width do
                if matrix[row] and matrix[row][col] then
                    local pixel = matrix[row][col]
                    table.insert(row_data, pixel:get_color())
                    table.insert(row_data, pixel:get_str())
                else
                    table.insert(row_data, blank_color)
                    table.insert(row_data, space_char)
                end
            end
        end

        return output
    end

    tbl:empty()

    return tbl
end


dumb_idea_html_panel = dumb_idea_html_panel or vgui.Create("DHTML") --Build the HTML panel to read from

local video_size = 200
local video_frame_rate = 30

local html = dumb_idea_html_panel
html:SetSize(video_size, video_size)
--html:SetAlpha(0)
--html:SetMouseInputEnabled(false)
html:OpenURL("https://tomdotbat.dev/video.html")

local canvas = create_canvas()

local update_rt
timer.Create("DumbIdea.WaitForHTMLMat", .5, 10, function() --HTML mat isn't ready right away
    if not html:GetHTMLMaterial() then return end

    local html_mat = html:GetHTMLMaterial()
    local mat_name = "DumbIdea_" .. string.Replace(html_mat:GetName(), "__vgui_texture_", "")

    html:QueueJavascript([[document.querySelector("video").volume = .025;]])

    local render_target = GetRenderTarget("DumbIdeaRT_" .. string.Replace(mat_name, "__vgui_texture_", ""), video_size, video_size)
    function update_rt()
        render.PushRenderTarget(render_target)
        cam.Start2D()
            render.Clear(0, 0, 0, 255)

            if not html_mat then
                cam.End2D()
                render.PopRenderTarget()
                return
            end

            surface.SetMaterial(html_mat)
            surface.SetDrawColor(255, 255, 255)
            surface.DrawTexturedRect(0, 0, video_size, video_size)

            canvas:empty()

            render.CapturePixels()
            for x = 1, video_size do
                for y = 1, video_size do
                    local r, g, b = render.ReadPixel(x, y)
                    canvas:set_pixel(x, y, Color(r, g, b))
                end
            end
        cam.End2D()
        render.PopRenderTarget()
    end

    timer.Remove("DumbIdea.WaitForHTMLMat")
end)


do --Draw stuff
    local font = "DermaLarge"

    local frame_time = 1 / video_frame_rate
    local frame_progress = 0

    local draw_data = {}

    local is_string = isstring
    local get_frame_time = FrameTime
    local screen_width, screen_height = ScrW, ScrH
    local set_draw_color, draw_rect = surface.SetDrawColor, surface.DrawRect
    local set_font, get_text_size = surface.SetFont, surface.GetTextSize
    local set_text_pos, set_text_color, draw_text = surface.SetTextPos, surface.SetTextColor, surface.DrawText

    --hook.Add("Think", "dumb_idea", function() --Draws in the console
    --    if frame_progress >= frame_time then
    --        if update_rt then
    --            update_rt()
    --            draw_data = canvas:get_draw_data()
--
--
    --            local canvas_width, canvas_height = canvas:get_size()
    --            for row = 1, canvas_height do
    --                local row_data = draw_data[row]
--
    --                for col = 1, canvas_width * 2, 2 do
    --                    MsgC(row_data[col], row_data[col + 1])
    --                end
    --                Msg("\n")
    --            end
    --        end
    --        frame_progress = 0
    --    end
--
    --    frame_progress = frame_progress + get_frame_time()
    --end)

    hook.Add("HUDPaint", "dumb_idea", function() --Draws in the center of the screen
        set_draw_color(0, 0, 0, 255)
        draw_rect(0, 0, screen_width(), screen_height())

        if frame_progress >= frame_time then
            if update_rt then
                update_rt()
                draw_data = canvas:get_draw_data()
            end
            frame_progress = 0
        end

        frame_progress = frame_progress + get_frame_time()

        local canvas_width, canvas_height = canvas:get_size()

        set_font(font)
        local _, char_size = get_text_size(space_char)

        local origin_x = (screen_width() * .5) - (canvas_width * char_size) *  .25
        local origin_y = (screen_height() * .5) - (canvas_height * char_size * .75) *  .5

        char_size = char_size * .75

        for row = 1, canvas_height do
            local row_data = draw_data[row]

            set_text_pos(origin_x, origin_y)
            origin_y = origin_y + char_size

            for col = 1, canvas_width * 2 do
                local data = row_data[col]
                if is_string(data) then
                    draw_text(data)
                else
                    set_text_color(data)
                end
            end
        end
    end)
end