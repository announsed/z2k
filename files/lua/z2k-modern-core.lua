-- z2k-modern-core.lua
-- Core-level desync extensions for z2k:
-- 1) custom 3-fragment IP fragmenters (with optional overlap)
-- 2) TLS ClientHello extension-order morphing (fingerprint drift)

local function z2k_num(v, fallback)
    local n = tonumber(v)
    if n == nil then return fallback end
    return n
end

local function z2k_align8(v)
    local n = math.floor(z2k_num(v, 0))
    if n < 0 then n = 0 end
    return bitand(n, NOT7)
end

local function z2k_frag_idx(exthdr)
    if exthdr then
        local first_destopts
        for i = 1, #exthdr do
            if exthdr[i].type == IPPROTO_DSTOPTS then
                first_destopts = i
                break
            end
        end
        for i = #exthdr, 1, -1 do
            if exthdr[i].type == IPPROTO_HOPOPTS or
               exthdr[i].type == IPPROTO_ROUTING or
               (exthdr[i].type == IPPROTO_DSTOPTS and i == first_destopts) then
                return i + 1
            end
        end
    end
    return 1
end

local function z2k_ipfrag3_params(dis, ipfrag_options, totalfrag)
    local pos1
    if dis.tcp then
        pos1 = z2k_num(ipfrag_options.ipfrag_pos_tcp, 32)
    elseif dis.udp then
        pos1 = z2k_num(ipfrag_options.ipfrag_pos_udp, 8)
    elseif dis.icmp then
        pos1 = z2k_num(ipfrag_options.ipfrag_pos_icmp, 8)
    else
        pos1 = z2k_num(ipfrag_options.ipfrag_pos, 32)
    end

    local span = z2k_num(ipfrag_options.ipfrag_span, 24)
    local pos2 = z2k_num(ipfrag_options.ipfrag_pos2, pos1 + span)
    local ov12 = z2k_num(ipfrag_options.ipfrag_overlap12, 0)
    local ov23 = z2k_num(ipfrag_options.ipfrag_overlap23, 0)

    pos1 = z2k_align8(pos1)
    pos2 = z2k_align8(pos2)
    ov12 = z2k_align8(ov12)
    ov23 = z2k_align8(ov23)

    if pos1 < 8 then pos1 = 8 end
    if pos2 <= pos1 then pos2 = pos1 + 8 end
    if pos2 >= totalfrag then pos2 = z2k_align8(totalfrag - 8) end
    if pos2 <= pos1 then return nil end

    if ov12 > (pos1 - 8) then ov12 = pos1 - 8 end
    if ov23 > (pos2 - 8) then ov23 = pos2 - 8 end

    local off2 = pos1 - ov12
    local off3 = pos2 - ov23

    if off2 < 0 then off2 = 0 end
    if off3 <= off2 then off3 = off2 + 8 end
    if off3 >= totalfrag then off3 = z2k_align8(totalfrag - 8) end
    if off3 <= off2 or off3 >= totalfrag then return nil end

    local len1 = pos1
    local len2 = pos2 - off2
    local len3 = totalfrag - off3
    if len1 <= 0 or len2 <= 0 or len3 <= 0 then return nil end

    return len1, off2, len2, off3, len3
end

-- option : ipfrag_pos_tcp / ipfrag_pos_udp / ipfrag_pos_icmp / ipfrag_pos
-- option : ipfrag_pos2 - second split position (bytes, multiple of 8)
-- option : ipfrag_span - used when ipfrag_pos2 is omitted (default 24)
-- option : ipfrag_overlap12 - overlap between fragment 1 and 2 (bytes, multiple of 8)
-- option : ipfrag_overlap23 - overlap between fragment 2 and 3 (bytes, multiple of 8)
-- option : ipfrag_next2 / ipfrag_next3 - IPv6 "next" field override for fragment #2/#3
function z2k_ipfrag3(dis, ipfrag_options)
    DLOG("z2k_ipfrag3")
    if not dis or not (dis.ip or dis.ip6) then
        return nil
    end

    ipfrag_options = ipfrag_options or {}
    local l3 = l3_len(dis)
    local plen = l3 + l4_len(dis) + #dis.payload
    local totalfrag = plen - l3
    if totalfrag <= 24 then
        DLOG("z2k_ipfrag3: packet too short for 3 fragments")
        return nil
    end

    local len1, off2, len2, off3, len3 = z2k_ipfrag3_params(dis, ipfrag_options, totalfrag)
    if not len1 then
        DLOG("z2k_ipfrag3: invalid split params")
        return nil
    end

    if dis.ip then
        local ip_id = dis.ip.ip_id == 0 and math.random(1, 0xFFFF) or dis.ip.ip_id

        local d1 = deepcopy(dis)
        d1.ip.ip_len = l3 + len1
        d1.ip.ip_off = IP_MF
        d1.ip.ip_id = ip_id

        local d2 = deepcopy(dis)
        d2.ip.ip_len = l3 + len2
        d2.ip.ip_off = bitor(bitrshift(off2, 3), IP_MF)
        d2.ip.ip_id = ip_id

        local d3 = deepcopy(dis)
        d3.ip.ip_len = l3 + len3
        d3.ip.ip_off = bitrshift(off3, 3)
        d3.ip.ip_id = ip_id

        return { d1, d2, d3 }
    end

    if dis.ip6 then
        local idxfrag = z2k_frag_idx(dis.ip6.exthdr)
        local l3extra_before_frag = l3_extra_len(dis, idxfrag - 1)
        local l3_local = l3_base_len(dis) + l3extra_before_frag
        local totalfrag6 = plen - l3_local
        if totalfrag6 <= 24 then
            DLOG("z2k_ipfrag3: ipv6 packet too short for 3 fragments")
            return nil
        end

        local p1, p2, p3, p4, p5 = z2k_ipfrag3_params(dis, ipfrag_options, totalfrag6)
        if not p1 then
            DLOG("z2k_ipfrag3: invalid ipv6 split params")
            return nil
        end
        len1, off2, len2, off3, len3 = p1, p2, p3, p4, p5

        local l3extra_with_frag = l3extra_before_frag + 8
        local ident = math.random(1, 0xFFFFFFFF)

        local d1 = deepcopy(dis)
        insert_ip6_exthdr(d1.ip6, idxfrag, IPPROTO_FRAGMENT, bu16(IP6F_MORE_FRAG) .. bu32(ident))
        d1.ip6.ip6_plen = l3extra_with_frag + len1

        local d2 = deepcopy(dis)
        insert_ip6_exthdr(d2.ip6, idxfrag, IPPROTO_FRAGMENT, bu16(bitor(off2, IP6F_MORE_FRAG)) .. bu32(ident))
        if ipfrag_options.ipfrag_next2 then
            d2.ip6.exthdr[idxfrag].next = tonumber(ipfrag_options.ipfrag_next2)
        end
        d2.ip6.ip6_plen = l3extra_with_frag + len2

        local d3 = deepcopy(dis)
        insert_ip6_exthdr(d3.ip6, idxfrag, IPPROTO_FRAGMENT, bu16(off3) .. bu32(ident))
        if ipfrag_options.ipfrag_next3 then
            d3.ip6.exthdr[idxfrag].next = tonumber(ipfrag_options.ipfrag_next3)
        end
        d3.ip6.ip6_plen = l3extra_with_frag + len3

        return { d1, d2, d3 }
    end

    return nil
end

-- Tiny overlap profile for z2k_ipfrag3.
function z2k_ipfrag3_tiny(dis, ipfrag_options)
    local opts = deepcopy(ipfrag_options or {})
    if opts.ipfrag_overlap12 == nil then opts.ipfrag_overlap12 = 8 end
    if opts.ipfrag_overlap23 == nil then opts.ipfrag_overlap23 = 8 end
    if opts.ipfrag_pos2 == nil then
        local p1
        if dis.tcp then
            p1 = z2k_num(opts.ipfrag_pos_tcp, 32)
        elseif dis.udp then
            p1 = z2k_num(opts.ipfrag_pos_udp, 8)
        elseif dis.icmp then
            p1 = z2k_num(opts.ipfrag_pos_icmp, 8)
        else
            p1 = z2k_num(opts.ipfrag_pos, 32)
        end
        opts.ipfrag_pos2 = p1 + 24
    end
    return z2k_ipfrag3(dis, opts)
end

local function z2k_tls_ext_is_fixed(ext)
    if not ext or ext.type == nil then return true end
    if TLS_EXT_SERVER_NAME and ext.type == TLS_EXT_SERVER_NAME then return true end
    if TLS_EXT_PRE_SHARED_KEY and ext.type == TLS_EXT_PRE_SHARED_KEY then return true end
    return false
end

local function z2k_shuffle(tbl)
    for i = #tbl, 2, -1 do
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
end

-- Reorder non-critical TLS ClientHello extensions in-place.
-- Intended to blur stable JA3/JA4-style extension-order fingerprints.
function z2k_tls_extshuffle(ctx, desync)
    if not desync or not desync.dis or not desync.dis.tcp then
        if desync and desync.dis and not desync.dis.icmp then
            instance_cutoff_shim(ctx, desync)
        end
        return
    end

    direction_cutoff_opposite(ctx, desync, "out")
    if not direction_check(desync, "out") then return end
    if not payload_check(desync, "tls_client_hello") then return end

    local tdis = tls_dissect(desync.dis.payload)
    if not tdis or not tdis.handshake or not tdis.handshake[TLS_HANDSHAKE_TYPE_CLIENT] then
        return
    end

    local ch = tdis.handshake[TLS_HANDSHAKE_TYPE_CLIENT].dis
    if not ch or type(ch.ext) ~= "table" or #ch.ext < 4 then
        return
    end

    local movable_idx = {}
    local movable_ext = {}
    for i = 1, #ch.ext do
        if not z2k_tls_ext_is_fixed(ch.ext[i]) then
            table.insert(movable_idx, i)
            table.insert(movable_ext, ch.ext[i])
        end
    end

    if #movable_ext < 2 then
        return
    end

    z2k_shuffle(movable_ext)
    for i = 1, #movable_idx do
        ch.ext[movable_idx[i]] = movable_ext[i]
    end

    local tls_new = tls_reconstruct(tdis)
    if not tls_new then
        DLOG_ERR("z2k_tls_extshuffle: reconstruct error")
        return
    end

    desync.dis.payload = tls_new
    return VERDICT_MODIFY
end
