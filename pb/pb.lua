_addon.author   = 'Project Tako';
_addon.name     = 'Party Buffs';
_addon.version  = '1.0';

require('common');
require('d3d8');
require('logging');
require('ffxi.targets');
local icon_reader = require('icon_reader');
local status_effect_reader = require('status_effect_reader');

local icon_packs =
{
    [1] =
    {
        ['Name'] = 'Default',
        ['Type'] = 'DAT',
        ['Path'] = nil
    }
};

local options =
{
    ['ShowOwnBuffs'] = true,
    ['ShowDistance'] = true,
    ['DistancePosition'] = 0,
    ['Window'] =
    {
        ['X'] = 800,
        ['Y'] = 600
    },
    ['Menu'] =
    {
        ['X'] = 0,
        ['Y'] = 0
    },
    ['Scale'] =
    {
        ['X'] = 0.0,
        ['Y'] = 0.0
    },
    ['Offsets'] =
    {
        ['X'] = 162,
        ['Y'] = 42
    },
    ['Size'] = 20,
    ['IconPack'] = 1
};

local imgui_variables =
{
    ['var_ShowPartyBuffsWindow'] = { nil, ImGuiVar_BOOLCPP, true },
    ['var_IconPack_Combo'] = { nil, ImGuiVar_INT32, 0 },
    ['var_ShowOwnBufs_Checkbox'] = { nil, ImGuiVar_BOOLCPP, true },
    ['var_ShowDistance_Checkbox'] = { nil, ImGuiVar_BOOLCPP, true },
    ['var_DistancePosition_Combo'] = { nil, ImGuiVar_INT32, 0 },
    ['var_OffsetX_SliderInt'] = { nil, ImGuiVar_INT32, 162 },
    ['var_OffsetY_SliderInt'] = { nil, ImGuiVar_INT32, 42 },
    ['var_Size_SliderInt'] = { nil, ImGuiVar_INT32, 20 },
    ['var_BuffName_Input'] = { nil, ImGuiVar_CDSTRING, 20, '' }
};

local background_sprite = nil;
local status_effects = { };
local party_data = { };
local excluded_buffs = { };
---------------------------------------------------------------------------------------------------
-- func: load
-- desc: First called when our addon is loaded.
---------------------------------------------------------------------------------------------------
ashita.register_event('load', function()
    options = ashita.settings.load_merged(_addon.path .. '/settings/settings.json', options) or { };
    excluded_buffs = ashita.settings.load_merged(_addon.path .. '/settings/excluded_buffs.json', excluded_buffs) or { };

    options['Window']['X'] =  AshitaCore:GetConfigurationManager():get_int32('boot_config', 'window_x', options['Window']['X']);
    options['Window']['Y'] =  AshitaCore:GetConfigurationManager():get_int32('boot_config', 'window_y', options['Window']['Y']);
    options['Menu']['X'] = AshitaCore:GetConfigurationManager():get_int32('boot_config', 'menu_x', options['Menu']['X']);
    options['Menu']['Y'] = AshitaCore:GetConfigurationManager():get_int32('boot_config', 'menu_y', options['Menu']['Y']);

    options['Menu']['X'] = options['Menu']['X'] > 0 and options['Menu']['X'] or options['Window']['X'];
    options['Menu']['Y'] = options['Menu']['Y'] > 0 and options['Menu']['Y'] or options['Window']['Y'];

    options['Scale']['X'] =  options['Window']['X'] / options['Menu']['X'];
    options['Scale']['Y'] =  options['Window']['Y'] / options['Menu']['Y'];

    imgui_variables['var_IconPack_Combo'][3] = options['IconPack'] - 1;
    imgui_variables['var_ShowOwnBufs_Checkbox'][3] = options['ShowOwnBuffs'];
    imgui_variables['var_ShowDistance_Checkbox'][3] = options['ShowDistance'];
    imgui_variables['var_DistancePosition_Combo'][3] = options['DistancePosition'];

    local result, sprite = ashita.d3dx.CreateSprite();

    if (result == 0) then
        background_sprite = sprite;
    else
        local _, error = ashita.d3dx.GetErrorStringA(result);
        print(string.format('[Error] Failed to create sprite. - Error: (%08X) %s', result, error));
        ashita.logging.error('PartyBuffs::Load', string.format('[Error] Failed to create sprite. - Error: (%08X) %s', result, error));
    end

    for x = 0, 5, 1 do
        local server_id = AshitaCore:GetDataManager():GetParty():GetMemberServerId(x);
        party_data[x] =
        {
            ['ServerId'] = server_id,
            ['Buffs'] = { }
        };

        local font_object = AshitaCore:GetFontManager():Create(string.format('__party_buffs_addon_%d', x));
        font_object:SetColor(0xFFFFFFFF);
        font_object:SetFontFamily('Comic Sans MS');
        font_object:SetFontHeight(8 * options['Scale']['Y']);
        font_object:SetBold(true);
        font_object:SetLocked(true);
        font_object:SetRightJustified(true);
        font_object:SetVisibility(false);
    end

    for key, value in pairs(imgui_variables) do
        if (type(value) == 'table') then
            if (value[2] >= ImGuiVar_CDSTRING) then
				value[1] = imgui.CreateVar(value[2], value[3]);
			else
				value[1] = imgui.CreateVar(value[2]);
			end

            if (#value > 2 and value[2] < ImGuiVar_CDSTRING) then
				imgui.SetVarValue(value[1], value[3]);
			elseif (#value > 3 and value[2] == ImGuiVar_CDSTRING) then
				imgui.SetVarValue(value[1], value[4]);
			end

        end
    end

    status_effects = status_effect_reader.get_status_effects() or { };

    local icon_packs_path = string.format('%s/icons/', _addon.path);
    if (ashita.file.dir_exists(icon_packs_path)) then
        local icon_directories = ashita.file.get_dir(icon_packs_path) or { };
        local index = #icon_packs + 1;
        for _, value in pairs(icon_directories) do
            local path = string.format('%s/icons/%s', _addon.path, value);
            local icon_files = ashita.file.get_dir(path, '*.DAT', false) or { };
            if (icon_files[1] ~= nil and string.lower(icon_files[1]) == '57.dat') then
                icon_packs[index] =
                {
                    ['Name'] = value,
                    ['Type'] = 'DAT',
                    ['Path'] = path
                };

                index = index + 1;
            else
                icon_files = ashita.file.get_dir(path, '*.png', false) or { };
                if (icon_files[1] ~= nil and string.lower(icon_files[1]) == '0.png') then
                    icon_packs[index] =
                    {
                        ['Name'] = value,
                        ['Type'] = 'PNG',
                        ['Path'] = path
                    };

                    index = index + 1;
                end
            end
        end
    end

    icon_reader['Folder'] = icon_packs[options['IconPack']]['Path'] or string.format('%s\\..\\FINAL FANTASY XI\\%s', ashita.file.get_install_dir(), 'ROM\\119');

    imgui.SetNextWindowSize(400, 300, ImGuiSetCond_FirstUseEver);
end);

---------------------------------------------------------------------------------------------------
-- func: command
-- desc: Called when our addon receives a command.
---------------------------------------------------------------------------------------------------
ashita.register_event('command', function(cmd, nType)
	-- get command args
	local args = cmd:args();

	if (args[1] ~= 'partybuffs' and args[1] ~= '/pb') then
		return false;
	end

    if (#args < 2) then
        return false;
    end

    if (args[2] == 'show' or args[2] == 'options') then
        imgui.SetVarValue(imgui_variables['var_ShowPartyBuffsWindow'][1], true);
    elseif (args[2] == 'hide') then
        imgui.SetVarValue(imgui_variables['var_ShowPartyBuffsWindow'][1], false);
    elseif (args[2] == 'toggle') then
        imgui.SetVarValue(imgui_variables['var_ShowPartyBuffsWindow'][1], not imgui.GetVarValue(imgui_variables['var_ShowPartyBuffsWindow'][1]));
    end

	return false;
end);

---------------------------------------------------------------------------------------------------
-- func: incoming_text
-- desc: Called when the game client has begun to add a new line of text to the chat box.
---------------------------------------------------------------------------------------------------
ashita.register_event('incoming_text', function(mode, message, modifiedmode, modifiedmessage, blocked)
    return false;
end);

---------------------------------------------------------------------------------------------------
-- func: outgoing_text
-- desc: Called when the game client is sending text to the server.
--       (This gets called when a command, chat, etc. is not handled by the client and is being sent to the server.)
---------------------------------------------------------------------------------------------------
ashita.register_event('outgoing_text', function(mode, message, modifiedmode, modifiedmessage, blocked)
    return false;
end);

---------------------------------------------------------------------------------------------------
-- func: incoming_packet
-- desc: Called when our addon receives an incoming packet.
---------------------------------------------------------------------------------------------------
ashita.register_event('incoming_packet', function(id, size, packet)
    if (id == 0x063) then
        if (struct.unpack('H', packet, 0x04 + 1) == 0x09) then
            party_data[0]['Buffs'] = { };
            if (options['ShowOwnBuffs']) then
                for buffIndex = 0, 31, 1 do
                    local buffId = struct.unpack('H', packet, 0x08 + (0x02 * buffIndex) + 1);
                    if (buffId ~= nil and buffId > 0 and buffId ~= 255) then
                        party_data[0]['Buffs'][buffIndex] = { };
                        party_data[0]['Buffs'][buffIndex]['BuffId'] = buffId;

                        local current_pack = icon_packs[options['IconPack']];
                        if (current_pack ~= nil) then
                            if (current_pack['Type'] == 'DAT') then
                                party_data[0]['Buffs'][buffIndex]['BuffTexture'] = icon_reader.get_status_icon(party_data[0]['Buffs'][buffIndex]['BuffId'], options['Size'], options['Size']);
                            elseif (current_pack['Type'] == 'PNG') then
                                party_data[0]['Buffs'][buffIndex]['BuffTexture'] = icon_reader.create_texture_from_file(party_data[0]['Buffs'][buffIndex]['BuffId'], options['Size'], options['Size']);
                            end
                        end
                    end
                end
            end
        end
    elseif (id == 0x076) then
        for x = 0, 4, 1 do
            local server_id = struct.unpack('I', packet, x * 0x30 + 0x04 + 1);
            local member_index = -1;
            for i = 1, 5, 1 do
                if (AshitaCore:GetDataManager():GetParty():GetMemberServerId(i) == server_id) then
                    member_index = i;
                    break;
                end
            end

            if (member_index == -1) then return false; end

            party_data[member_index] =
            {
                ['Buffs'] = { }
            };

            for buffIndex = 0, 31, 1 do
                local mask = bit.band(bit.rshift(struct.unpack('b', packet, bit.rshift(buffIndex, 2) + (x * 0x30 + 0x0C) + 1), 2 * (buffIndex % 4)), 3);
                if (struct.unpack('b', packet, (x * 0x30 + 0x14) + buffIndex + 1) ~= -1 or mask > 0) then
                    local buffId = bit.bor(struct.unpack('B', packet, (x * 0x30 + 0x14) + buffIndex + 1), bit.lshift(mask, 8));
                    if (buffId ~= nil and buffId > 0 and buffId ~= 255) then
                        party_data[member_index]['Buffs'][buffIndex] = { };
                        party_data[member_index]['Buffs'][buffIndex]['BuffId'] = buffId;

                        local current_pack = icon_packs[options['IconPack']];
                        if (current_pack ~= nil) then
                            if (current_pack['Type'] == 'DAT') then
                                party_data[member_index]['Buffs'][buffIndex]['BuffTexture'] = icon_reader.get_status_icon(party_data[member_index]['Buffs'][buffIndex]['BuffId'], options['Size'], options['Size']);
                            elseif (current_pack['Type'] == 'PNG') then
                                party_data[member_index]['Buffs'][buffIndex]['BuffTexture'] = icon_reader.create_texture_from_file(party_data[member_index]['Buffs'][buffIndex]['BuffId'], options['Size'], options['Size']);
                            end
                        end
                    end
                end
            end
        end
    end

	return false;
end);

---------------------------------------------------------------------------------------------------
-- func: outgoing_packet
-- desc: Called when our addon receives an outgoing packet.
---------------------------------------------------------------------------------------------------
ashita.register_event('outgoing_packet', function(id, size, packet)
    if (id == 0x00D) then
        for x = 0, 5 do
            party_data[x] =
            {
                ['ServerId'] = 0,
                ['Buffs'] = { }
            };

            AshitaCore:GetFontManager():Get(string.format('__party_buffs_addon_%d', x)):SetVisibility(false);
        end
    end
	return false;
end);

---------------------------------------------------------------------------------------------------
-- func: prerender
-- desc: Called before our addon is about to render.
---------------------------------------------------------------------------------------------------
ashita.register_event('prerender', function()

end);

---------------------------------------------------------------------------------------------------
-- func: render
-- desc: Called when our addon is being rendered.
---------------------------------------------------------------------------------------------------
ashita.register_event('render', function()
    -- don't render if objects are being hidden
    if (AshitaCore:GetFontManager():GetHideObjects()) then return; end

    if (imgui.GetVarValue(imgui_variables['var_ShowPartyBuffsWindow'][1])) then
        if (imgui.Begin('Party Buffs', imgui_variables['var_ShowPartyBuffsWindow'][1], imgui.bor(ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_AlwaysAutoResize))) then
            imgui.PushItemWidth(150);
            imgui.Text('Icon Pack');
            imgui.Separator();

            imgui.Indent(5.0);
            local combo_text = '';
            for _, value in pairs(icon_packs) do
                if (type(value) == 'table') then
                    if (value['Name'] ~= nil) then
                        combo_text = combo_text .. value['Name'] .. '\0';
                    end
                end
            end

            if (imgui.Combo('##label', imgui_variables['var_IconPack_Combo'][1], combo_text .. '\0s')) then
                options['IconPack'] = imgui.GetVarValue(imgui_variables['var_IconPack_Combo'][1]) + 1;
                icon_reader['Folder'] = icon_packs[options['IconPack']]['Path'] or string.format('%s\\..\\FINAL FANTASY XI\\%s', ashita.file.get_install_dir(), 'ROM\\119');
                icon_reader.flush();

                for member_index, member_data in pairs(party_data) do
                    if (member_data['Buffs'] ~= nil and type(member_data['Buffs']) == 'table') then
                        for buff_index, buff_data in pairs(member_data['Buffs']) do
                            if (buff_data['BuffTexture'] ~= nil) then
                                local current_pack = icon_packs[options['IconPack']];
                                if (current_pack ~= nil) then
                                    buff_data['BuffTexture']:Release();
                                    if (current_pack['Type'] == 'DAT') then
                                        buff_data['BuffTexture'] = icon_reader.get_status_icon(buff_data['BuffId'], options['Size'], options['Size']);
                                    elseif (current_pack['Type'] == 'PNG') then
                                        buff_data['BuffTexture'] = icon_reader.create_texture_from_file(buff_data['BuffId'], options['Size'], options['Size']);
                                    end
                                end
                            end
                        end
                    end
                end
            end

            imgui.Unindent(5.0);
            imgui.NewLine();

            imgui.Text('Options');
            imgui.Separator();

            imgui.Indent(5.0);
            if (imgui.Checkbox('Show Own Buffs', imgui_variables['var_ShowOwnBufs_Checkbox'][1])) then
                options['ShowOwnBuffs'] = imgui.GetVarValue(imgui_variables['var_ShowOwnBufs_Checkbox'][1]);

                if (not options['ShowOwnBuffs']) then
                    party_data[0]['Buffs'] = { };
                end
            end

            if (imgui.Checkbox('Show Distance', imgui_variables['var_ShowDistance_Checkbox'][1])) then
                options['ShowDistance'] = imgui.GetVarValue(imgui_variables['var_ShowDistance_Checkbox'][1]);
            end

            if (options['ShowDistance']) then
                if (imgui.Combo('Position', imgui_variables['var_DistancePosition_Combo'][1], 'Left\0Right\0\0')) then
                    options['DistancePosition'] = imgui.GetVarValue(imgui_variables['var_DistancePosition_Combo'][1]);
                end
            end

            imgui.Unindent(5.0);
            imgui.NewLine();

            imgui.Text('Position');
            imgui.Separator();

            imgui.Indent(5.0);

            if (imgui.SliderInt('Offset X', imgui_variables['var_OffsetX_SliderInt'][1], 0, options['Window']['X'])) then
                options['Offsets']['X'] = imgui.GetVarValue(imgui_variables['var_OffsetX_SliderInt'][1]);
            end

            if (imgui.SliderInt('Offset Y', imgui_variables['var_OffsetY_SliderInt'][1], 0, options['Window']['Y'])) then
                options['Offsets']['Y'] = imgui.GetVarValue(imgui_variables['var_OffsetY_SliderInt'][1]);
            end

            if (imgui.SliderInt('Icon Size', imgui_variables['var_Size_SliderInt'][1], 10, 32)) then
                options['Size'] = imgui.GetVarValue(imgui_variables['var_Size_SliderInt'][1]);
                icon_reader.flush();

                for member_index, member_data in pairs(party_data) do
                    if (member_data['Buffs'] ~= nil and type(member_data['Buffs']) == 'table') then
                        for buff_index, buff_data in pairs(member_data['Buffs']) do
                            if (buff_data['BuffTexture'] ~= nil) then
                                local current_pack = icon_packs[options['IconPack']];
                                if (current_pack ~= nil) then
                                    buff_data['BuffTexture']:Release();
                                    if (current_pack['Type'] == 'DAT') then
                                        buff_data['BuffTexture'] = icon_reader.get_status_icon(buff_data['BuffId'], options['Size'], options['Size']);
                                    elseif (current_pack['Type'] == 'PNG') then
                                        buff_data['BuffTexture'] = icon_reader.create_texture_from_file(buff_data['BuffId'], options['Size'], options['Size']);
                                    end
                                end
                            end
                        end
                    end
                end
            end

            imgui.Unindent(5.0);

            imgui.NewLine();

            imgui.Text('Exclusions');
            imgui.Separator();

            if (imgui.InputText('Buff Name', imgui_variables['var_BuffName_Input'][1], imgui_variables['var_BuffName_Input'][3], ImGuiInputTextFlags_EnterReturnsTrue)) then
                local buff_name = imgui.GetVarValue(imgui_variables['var_BuffName_Input'][1]);
                if (buff_name ~= nil and buff_name ~= '') then
                    for buff_id, buff_strings in pairs(status_effects) do
                        if (type(buff_strings) == 'table') then
                            if (buff_strings[1] ~= nil) then
                                if (string.lower(buff_name) == string.lower(buff_strings[1])) then
                                    excluded_buffs[buff_id] = buff_strings[1];

                                    imgui.SetVarValue(imgui_variables['var_BuffName_Input'][1], imgui_variables['var_BuffName_Input'][4]);
                                end
                            end
                        end
                    end
                end
            end

            if (imgui.ListBoxHeader('##label', 150, imgui.GetTextLineHeight() * 5)) then
                for key, value in pairs(excluded_buffs) do
                    local imgui_key = string.format('var_%d_%s_Selectable', key, value);
                    if (imgui_variables[imgui_key] == nil) then
                        imgui_variables[imgui_key] = { nil, ImGuiVar_BOOLCPP, false };
                        imgui_variables[imgui_key][1] = imgui.CreateVar(imgui_variables[imgui_key][2], imgui_variables[imgui_key][3]);
                    end

                    if (imgui.Selectable(string.format('%s [%d]', value, key), imgui_variables[imgui_key][1], ImGuiSelectableFlags_AllowDoubleClick)) then
                        if (imgui.IsMouseDoubleClicked(0)) then
                            excluded_buffs[key] = nil;
                        end
                    end
                end

                imgui.ListBoxFooter();
            end

            imgui.Indent(5.0);
            imgui.Unindent(5.0);

            imgui.PopItemWidth();
        end

        imgui.End();
    end

    if (AshitaCore:GetDataManager():GetParty():GetAllianceParty0MemberCount() > 1) then
        if (background_sprite == nil) then return; end

        -- calculate our start position
        local position_y = options['Window']['Y'] - (options['Offsets']['Y'] * options['Scale']['Y']);
        -- for offsetting later
        local party_count = AshitaCore:GetDataManager():GetParty():GetAllianceParty0MemberCount();

        background_sprite:Begin();

        if (party_data ~= nil) then
            for x = 0, 5, 1 do
                if (party_data[x] ~= nil) then
                    local f = AshitaCore:GetFontManager():Get(string.format('__party_buffs_addon_%d', x));
                    -- check to see if party member exists, is in the same zone, and active
                    if (AshitaCore:GetDataManager():GetParty():GetMemberServerId(x) ~= 0 and AshitaCore:GetDataManager():GetParty():GetMemberZone(0) == AshitaCore:GetDataManager():GetParty():GetMemberZone(x) and AshitaCore:GetDataManager():GetParty():GetMemberActive(x) == 1) then
                        local position_x = options['Window']['X'] - (options['Offsets']['X'] * options['Scale']['X']);
                        if (party_data[x]['Buffs'] ~= nil) then
                            local next_x_position = position_x;
                            for _, buff_data in pairs(party_data[x]['Buffs']) do
                                if (not table.haskey(excluded_buffs, buff_data['BuffId'])) then
                                    if (buff_data['BuffTexture'] ~= nil) then
                                        local color = math.d3dcolor(255, 255, 255, 255);
                                        local rect = RECT();
                                        rect.left = 0;
                                        rect.top = 0;
                                        rect.right = options['Size'];
                                        rect.bottom = options['Size'];

                                        -- calculate position and draw
                                        local posx = next_x_position - ((options['ShowDistance'] and options['DistancePosition'] == 1) and options['Size'] + 12.5 or 0);
                                        local posy = position_y - ((party_count - 1 - x) * (20 * options['Scale']['Y']));

                                        background_sprite:Draw(buff_data['BuffTexture']:Get(), rect, nil, nil, 0.0, D3DXVECTOR2(posx, posy), color);
                                        next_x_position = next_x_position - options['Size'];
                                    end
                                end
                            end

                            if (options['DistancePosition'] == 0) then
                                position_x = next_x_position;
                            end
                        end

                        if (f ~= nil) then
                            if (options['ShowDistance']) then
                                local distance = 0.0;
                                if (x == 0) then
                                    local target = ashita.ffxi.targets.get_target('t');
                                    if (target ~= nil) then
                                        distance = AshitaCore:GetDataManager():GetEntity():GetDistance(target['TargetIndex']);
                                    end
                                else
                                    distance = AshitaCore:GetDataManager():GetEntity():GetDistance(AshitaCore:GetDataManager():GetParty():GetMemberTargetIndex(x));
                                end
                                f:SetPositionX(position_x + 15);
                                f:SetPositionY(position_y - (party_count - x - 1) * (20 * options['Scale']['Y']));
                                f:SetText(string.format(string.format('%.1f', math.sqrt(distance))));
                                f:SetVisibility(true);
                            else
                                f:SetVisibility(false);
                            end
                        end
                    else
                        f:SetVisibility(false);
                    end
                end
            end
        end

        background_sprite:End();
    else
        for x = 0, 5 do
            local f = AshitaCore:GetFontManager():Get(string.format('__party_buffs_addon_%d', x));
            f:SetVisibility(false);
        end
    end
end);

---------------------------------------------------------------------------------------------------
-- func: timer_pulse
-- desc: Called when our addon is rendering it's scene.
---------------------------------------------------------------------------------------------------
ashita.register_event('timer_pulse', function()

end);

---------------------------------------------------------------------------------------------------
-- func: unload
-- desc: Called when our addon is unloaded.
---------------------------------------------------------------------------------------------------
ashita.register_event('unload', function()
    for x = 0, 5, 1 do
		AshitaCore:GetFontManager():Delete(string.format('__party_buffs_addon_%d', x));
	end
    if (background_sprite ~= nil) then
        background_sprite:Release();
    end

    ashita.settings.save(_addon.path .. '/settings/settings.json', options);
    ashita.settings.save(_addon.path .. '/settings/excluded_buffs.json', excluded_buffs);
end);