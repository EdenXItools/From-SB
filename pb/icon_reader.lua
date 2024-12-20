local icon_reader = { };

local cooked_dict = { };

icon_reader['Folder'] = string.format('%s\\..\\FINAL FANTASY XI\\%s', ashita.file.get_install_dir(), 'ROM\\119');
icon_reader['File'] =  '57.DAT';

-- https://en.wikipedia.org/wiki/BMP_file_format

-- file size is 4096 (32 by 32 with a bit depth of 32) + header size (122) = 4218
-- 4218 in hex = 0x0000107A (4 bytes)
local file_size = string.char(0x7A, 0x10, 0x00, 0x00)
local reserved1 = string.char(0x00, 0x00);
local reserved2 = string.char(0x00, 0x00);
-- actual image data starts at byte 122, which is the header size
local start = string.char(0x7A, 0x00, 0x00, 0x00);
-- BITMAPV4HEADER
local dib_header_size = string.char(0x6C, 0x00, 0x00, 0x00);
-- size will always be 32x32
local bitmap_width = string.char(0x20, 0x00, 0x00, 0x00);
local bitmap_height = bitmap_width;
-- planes must be 1
local bitmap_planes = string.char(0x01, 0x00);
-- bits per pixel, always 32
local bitmap_bpp = string.char(0x20, 0x00);
-- BI_BITFIELDS
local compression_type = string.char(0x03, 0x00, 0x00, 0x00);
local raw_image_size = string.char(0x00, 0x10, 0x00, 0x00);
local vertical_resolution = string.char(0x00, 0x00, 0x00, 0x00);
local horizontal_resolution = string.char(0x00, 0x00, 0x00, 0x00);
local number_colors = string.char(0x00, 0x00, 0x00, 0x00);
local important_colors = string.char(0x00, 0x00, 0x00, 0x00);
-- color masks
local red_mask = string.char(0x00, 0x00, 0xFF, 0x00);
local green_mask = string.char(0x00, 0xFF, 0x00, 0x00);
local blue_mask = string.char(0xFF, 0x00, 0x00, 0x00);
local alpha_mask = string.char(0x00, 0x00, 0x00, 0xFF);
local color_space = 'sRGB';
-- CIEXYZTRIPLE Color Space endpoints Unused for LCS "Win " or "sRGB"
local endpoints = string.rep(string.char(0x00), 0x24);
-- gammas Unused for LCS "Win " or "sRGB"
local red_gamma = string.char(0x00, 0x00, 0x00, 0x00);
local green_gamma = string.char(0x00, 0x00, 0x00, 0x00);
local blue_gamma = string.char(0x00, 0x00, 0x00, 0x00);

local bitmap_header = 'BM' .. file_size .. reserved1 .. reserved2 .. start .. dib_header_size .. bitmap_width .. bitmap_height .. bitmap_planes .. bitmap_bpp .. compression_type .. raw_image_size .. horizontal_resolution .. vertical_resolution .. number_colors .. important_colors .. red_mask .. green_mask .. blue_mask .. alpha_mask .. color_space .. endpoints .. red_gamma .. green_gamma .. blue_gamma;

function icon_reader.flush()
    for key, value in pairs(cooked_dict) do
        value:Release();
        cooked_dict[key] = nil;
    end

    cooked_dict = { };
end

function icon_reader.get_status_icon(status_icon_id, width, height)
    local key = string.format('%d-%d-%d', status_icon_id, width, height);
    if (cooked_dict[key] ~= nil) then
        return cooked_dict[key];
    end

    local file_path = string.format('%s\\%s', icon_reader['Folder'], icon_reader['File']);
    local file = io.open(file_path, 'rb');
    if (file ~= nil) then
        file:seek('set', status_icon_id * 0x1800);
        local data = file:read(0x1800);

        if (data ~= nil) then
            local length = string.byte(data, 0x282);

            if (length == 4) then
                data = string.sub(data, 0x2BE, 0x12BD);
            elseif (length == 8) then
                local palette = string.sub(data, 0x2BE, 0x6BD);
                palette = string.gsub(palette, '(...)\x80', '%1\xFF');

                local colors = { };
                local index = 0x00;
                for x = 1, 0x400, 0x04 do
                    colors[string.char(index)] = string.sub(palette, x, x + 3);
                    index = index + 1;
                end

                data = string.gsub(string.sub(data, 0x6BE, 0xABD), '(.)', function(x) return colors[x] end);
            elseif (length == 16) then
                data = string.sub(data, 0x2BE, 0x12BD);
                data = string.gsub(data, '(...)\x80', '%1\xFF')
            end
        end

        file:close();

        if (data ~= nil) then
            cooked_dict[key] = icon_reader.create_texture_from_bitmap(bitmap_header .. data, width, height);

            return cooked_dict[key]; 
        end
    end

    return nil;
end

function icon_reader.create_texture_from_bitmap(data, width, height)
    if (data ~= nil) then
        local ptr = ashita.memory.alloc(4096 + 122);
        if (ptr == 0) then
            ashita.logging.error('PartyBuffs::IconReader::CreateTextureFromBitmap', '[Error] Failed to allocate memory to load an item icon.');
            return nil;
        end

        local bmp = { };
        for x = 1, string.len(data) do
            bmp[x] = struct.unpack('B', data, x);
        end

        ashita.memory.write_array(ptr, bmp);
        local res, _, _, texture = ashita.d3dx.CreateTextureFromFileInMemoryEx(ptr, 4096 + 122, width, height, 1, 0, D3DFMT_A8R8G8B8, 1, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF000000);
        ashita.memory.dealloc(ptr);

        if (res == 0) then
            return texture;
        else
            local _, err = ashita.d3dx.GetErrorStringA(res);
            ashita.logging.error('PartyBuffs::IconReader::CreateTextureFromBitmap', string.format('[Error] %s', err));
        end
    end

    return nil;
end

function icon_reader.create_texture_from_file(status_icon_id, width, height)
    local key = string.format('%d-%d-%d', status_icon_id, width, height)
    if (cooked_dict[key] ~= nil) then
        return cooked_dict[key];
    end

    local file_path = string.format('%s\\%d.png', icon_reader['Folder'], status_icon_id);
    if (ashita.file.file_exists(file_path)) then
        local res, _, _, texture = ashita.d3dx.CreateTextureFromFileExA(file_path, width, height, 1, 0, D3DFMT_A8R8G8B8, 1, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF000000);

        if (res == 0) then
            cooked_dict[key] = texture

            return cooked_dict[key];
        else
            local _, err = ashita.d3dx.GetErrorStringA(res);
            ashita.logging.error('PartyBuffs::IconReader::CreateTextureFromFile', string.format('[Error] %s', err));
        end
    end

    return nil;
end

return icon_reader;