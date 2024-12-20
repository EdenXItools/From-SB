local status_effect_reader = { };

status_effect_reader['dat_file'] = 'ROM\\180\\102.DAT';

function status_effect_reader.get_status_effects()
    local file_path = string.format('%s\\..\\FINAL FANTASY XI\\%s', ashita.file.get_install_dir(), status_effect_reader['dat_file']);
    local file = io.open(file_path, 'rb');
    if (file ~= nil) then
        local status_effects = { };
        local data = file:read(0x40);
        local header = struct.unpack('I', data, 0x18 + 1);
        if (header ~= 0x40) then return nil; end

        local bytes_per_entry = struct.unpack('i', data, 0x1C + 1);
        if (bytes_per_entry < 0) then return nil; end

        local data_bytes = struct.unpack('I', data, 0x24 + 1);
        local entry_count = struct.unpack('I', data, 0x28 + 1);
        if (bytes_per_entry ~= entry_count * 8) then return nil; end

        for x = 0, entry_count - 1, 1 do
            file:seek('set', header + x * 8);

            data = file:read(0x08);
            local offset = bit.bnot(struct.unpack('i', data, 0x00 + 1));
            local count = bit.bnot(struct.unpack('i', data, 0x04 + 1));

            if (offset < 0 or count < 0 or offset + count > data_bytes) then return nil; end

            file:seek('set', header + bytes_per_entry + offset);

            data = file:read(count);

            status_effects[x] = status_effect_reader.read_block(data);
        end

        return status_effects;
    end

    return nil;
end

function status_effect_reader.read_block(data)
    local count = struct.unpack('i', data, 0x00 + 1);
    local flip = false;

    if (count < 0 or count > 100) then
        count = bit.bnot(count);
        flip = true;
    end

    local offsets = { };
    local flags = { };

    for x = 0, count, 1 do
        offsets[x] = bit.bxor(struct.unpack('I', data, 0x04 + (0x08 * x) + 1), (flip and 0xFFFFFFFF or 0x00000000));
        flags[x] = bit.bxor(struct.unpack('I', data, 0x08 + (0x08 * x) + 1), (flip and 0xFFFFFFFF or 0x00000000));
    end

    local entries = { };

    for x = 0, count, 1 do
        local range = { };
        local offset = 0x1C + offsets[x];

        while true do
            local b0, b1, b2, b3 = struct.unpack('BBBB', data, offset + 1);
            if (flip) then
                b0 = bit.bxor(b0, 0xFF);
                b1 = bit.bxor(b1, 0xFF);
                b2 = bit.bxor(b2, 0xFF);
                b3 = bit.bxor(b3, 0xFF);
            end

            table.insert(range, b0);
            table.insert(range, b1);
            table.insert(range, b2);
            table.insert(range, b3);

            if (b3 == 0x00) then break; end

            offset = offset + 4;
        end

        local text = string.trim(string.char(unpack(range)), '\0');
        table.insert(entries, text)
    end

    return entries;
end

return status_effect_reader;