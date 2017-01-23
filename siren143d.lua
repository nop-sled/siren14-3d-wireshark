do
    local bit = require("bit")
    
    local FLAG_FIELDS = {
        FlagAudioOnly = {"Audio Only", 0x1},
        FlagSpeakerPosition = {"Speaker Position", 0x2},
        FlagListenerPosition = {"Listener Position", 0x4},
        FlagListenerOrientation = {"Listener Orientation", 0x10},
        FlagSilenceFrame = {"Silence Frame", 0x20},
        FlagRosterUpdate = {"Roster Update", 0x40},
        FlagEncapsulatedMedia = {"Encapsulated Media", 0x80},
        FlagMediaControl = {"Media Control", 0x100}
    }
    
    -- Maybe? IDK lol.
    local PARTICIPANT_UPDATE_TYPES = {
        [3] = "Added",
        [2] = "Updated",
        [1] = "Removed"
    }

    local siren14_3d = Proto("siren14_3d", "RTP / SIREN14-3D")
    local F = siren14_3d.fields
    
    function def_flag_attr(fields_base, name)
        local attrs = FLAG_FIELDS[name]
        fields_base[name] = ProtoField.uint32("siren14_3d." .. name, attrs[1], base.DEC, nil, attrs[2])
    end
    
    function def_vec_component(fields_base, name, component)
        fields_base[name .. component] = ProtoField.int32("siren14_3d." .. name .. "." .. component, name .. component, base.DEC, nil)
    end
    
    function def_3d_vec_attr(fields_base, name)
        def_vec_component(fields_base, name, "X")
        def_vec_component(fields_base, name, "Y")
        def_vec_component(fields_base, name, "Z")
    end
    
    function dissect_flag_attr(tree_base, name, flags)
        local attrs = FLAG_FIELDS[name]
        if  bit.band(attrs[2], flags:uint()) > 0 then
            tree_base:append_text(attrs[1] .. ", ")
        end
        tree_base:add(F[name], flags)
    end
    
    function dissect_vector_component(tree_base, base_name, name, buf)
        tree_base:append_text(tostring(buf:int()))
        tree_base:add(F[base_name .. name], buf)
    end
    
    function dissect_3d_vector(tree_base, base_name, buf)
        tree_base:set_text(base_name .. ": <")
        dissect_vector_component(tree_base, base_name, "X", buf(0, 4))
        tree_base:append_text(", ")
        dissect_vector_component(tree_base, base_name, "Y", buf(4, 4))
        tree_base:append_text(", ")
        dissect_vector_component(tree_base, base_name, "Z", buf(8, 4))
        tree_base:append_text(">")
    end
    
    function dissect_participant(tree_base, buf)
        
        local participant = tree_base:add(F.Participant)
        local update_type = buf(4, 1):uint()
        -- I have no idea if this really _is_ and update type field
        participant:add(F.ParticipantUpdateType, buf(4, 1))
        participant:add(F.ParticipantUnknown1, buf(5, 1))
        participant:add(F.ParticipantUnknown2, buf(6, 1))
        participant:add(F.ParticipantUnknown3, buf(7, 1))
        participant:add(F.ParticipantSID, buf(8, 4))
        participant:add(F.ParticipantUID, buf(12, 4))
        participant:add(F.ParticipantName, buf(16, 25))
        
        local unknown_num_width = 0
        
        local offset = 41
        if update_type == 3 then
            local display_name_len = buf(41, 2):uint()
            participant:add(F.ParticipantDisplayName, buf(43, display_name_len))
            participant:set_text(buf(43, display_name_len):string())
            offset = offset + 2 + display_name_len
            unknown_num_width = 1
        else
            participant:set_text(buf(16, 25):string())
            -- seems this might be ParticipantUnknown2 actually is?
            unknown_num_width = 2
        end
        
        local unknown_num_len = buf(offset, unknown_num_width):uint()
        participant:add(F.ParticipantUnknownNumStr, buf(offset + unknown_num_width, unknown_num_len))
        offset = offset + unknown_num_width + unknown_num_len
        
        if update_type == 3 then
            participant:add(F.ParticipantUnknown4, buf(offset, 4))
        end
    end
    
    function dissect_participants(tree_base, buf)
        local offset = 0
        while offset < buf:len() do
            local var_len = buf(offset, 4):uint()
            local participant_len = 16 + var_len
            dissect_participant(tree_base, buf(offset, participant_len))
            offset = offset + participant_len
        end
    end

    F.SIREN143DFrame = ProtoField.none("siren14_32.Frame", "SIREN14-3D Frame")

    F.UID = ProtoField.uint32("siren14_3d.UserID","User ID",base.DEC,nil)
    F.SID = ProtoField.uint32("siren14_3d.SessionID","Session ID",base.DEC,nil)
    F.Energy = ProtoField.uint32("siren14_3d.Energy","Energy",base.DEC,nil)
    F.Flags = ProtoField.uint32("siren14_3d.Flags","Flags",base.HEX,nil)
    F.Position = ProtoField.none("siren14_3d.Position", "Position", base.DEC, nil)
    
    def_flag_attr(F, "FlagAudioOnly")
    def_flag_attr(F, "FlagSpeakerPosition")
    def_flag_attr(F, "FlagListenerPosition")
    def_flag_attr(F, "FlagListenerOrientation")
    def_flag_attr(F, "FlagSilenceFrame")
    def_flag_attr(F, "FlagRosterUpdate")
    def_flag_attr(F, "FlagEncapsulatedMedia")
    def_flag_attr(F, "FlagMediaControl")
    
    def_3d_vec_attr(F, "Position")
    
    F.AudioData = ProtoField.bytes("siren14_3d.AudioData", "AudioData")
    
    F.Participants = ProtoField.none("siren14_3d.Participants", "Participants", base.DEC, nil)
    F.Participant = ProtoField.none("siren14_3d.Participant", "Participant", base.DEC, nil)
    
    F.ParticipantUpdateType = ProtoField.uint8("siren14_3d.Participant.UpdateType", "Update Type", base.DEC, PARTICIPANT_UPDATE_TYPES)
    F.ParticipantUnknown1 = ProtoField.uint8("siren14_3d.Participant.Unknown1", "Unknown1", base.DEC, nil)
    F.ParticipantUnknown2 = ProtoField.uint8("siren14_3d.Participant.Unknown2", "Unknown2", base.DEC, nil)
    F.ParticipantUnknown3 = ProtoField.uint8("siren14_3d.Participant.Unknown3", "Unknown3", base.DEC, nil)
    F.ParticipantSID = ProtoField.uint32("siren14_3d.Participant.SID", "Session ID", base.DEC, nil)
    F.ParticipantUID = ProtoField.uint32("siren14_3d.Participant.UID", "User ID", base.DEC, nil)
    F.ParticipantName = ProtoField.string("siren14_3d.Participant.Name", "Name")
    F.ParticipantDisplayName = ProtoField.string("siren14_3d.Participant.DisplayName", "DisplayName")
    F.ParticipantUnknownNumStr = ProtoField.string("siren14_3d.Participant.UnknownNumStr", "UnknownNumStr")
    F.ParticipantUnknown4 = ProtoField.uint32("siren14_3d.Participant.Unknown4", "Unknown4", base.DEC, nil)

    function dissect_siren14_3d_frame(base_tree, tvb)
        local subtree = base_tree:add(F.SIREN143DFrame, tvb)
        subtree:add(F.UID, tvb(0,4))
        subtree:add(F.SID, tvb(4,4))
        subtree:add(F.Energy, tvb(8,4))
        
        local flags = tvb(12,4)
        local flags_int = flags:uint()
        local flags_tree = subtree:add(F.Flags, flags)
        flags_tree:append_text(": ")
        dissect_flag_attr(flags_tree, "FlagAudioOnly", flags)
        dissect_flag_attr(flags_tree, "FlagSpeakerPosition", flags)
        dissect_flag_attr(flags_tree, "FlagListenerPosition", flags)
        dissect_flag_attr(flags_tree, "FlagListenerOrientation", flags)
        dissect_flag_attr(flags_tree, "FlagSilenceFrame", flags)
        dissect_flag_attr(flags_tree, "FlagRosterUpdate", flags)
        dissect_flag_attr(flags_tree, "FlagEncapsulatedMedia", flags)
        dissect_flag_attr(flags_tree, "FlagMediaControl", flags)
        
        local payload_offset = 16
        
        -- If any this is any of the "position" packets then the audio
        -- data will follow after 12 bytes of positional data.
        if bit.band(flags_int, 0x16) > 0 then
            payload_offset = 28
            local pos_buf = tvb(16, 12)
            local pos_tree = subtree:add(F.Position, pos_buf)
            dissect_3d_vector(pos_tree, "Position", pos_buf)
        end
        
        local frame_len = 0
        if bit.band(flags_int, FLAG_FIELDS["FlagRosterUpdate"][2]) > 0 then
            dissect_participants(subtree:add(F.Participants), tvb(payload_offset, -1))
            -- Roster updates always appear to be on the end and don't have an
            -- obvious terminator. Assume we consumed the entire buffer.
            frame_len = tvb:len()
        else
            subtree:add(F.AudioData, tvb(payload_offset, 80))
            frame_len = payload_offset + 80
        end
        subtree:set_len(frame_len)
        return frame_len
    end

    function siren14_3d.dissector(tvb, pinfo, tree)
        pinfo.cols.protocol = "RTP / SIREN14-3D"
        local offset = 0
        while offset < tvb:len() do
            offset = offset + dissect_siren14_3d_frame(tree, tvb(offset, -1))
        end
    end

    -- register dissector to RTP payload type
    local payload_type_table = DissectorTable.get("rtp.pt")
    payload_type_table:add(111, siren14_3d)
end
