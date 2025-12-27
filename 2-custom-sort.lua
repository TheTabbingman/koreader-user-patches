local BookList = require("ui/widget/booklist")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

--[[
    SMART SERIES SORT (v2)
    
    Fixes: Now ignores KOReader's internal ".sdr" metadata folders when 
    checking if a directory has subfolders.
--]]

-- 1. Define Status Priority
local status_priority = {
    reading = 1,
    new = 2,
    abandoned = 3,
    complete = 4,
}

-- Cache to store whether a specific folder path has "real" subdirectories
local folder_content_cache = {}

-- Helper to check if a directory contains subdirectories (IGNORING .sdr folders)
local function directory_has_real_subfolders(dir_path)
    if folder_content_cache[dir_path] ~= nil then
        return folder_content_cache[dir_path]
    end

    local has_subdir = false
    -- Iterate the directory
    for file in lfs.dir(dir_path) do
        if file ~= "." and file ~= ".." then
            local fpath = dir_path .. "/" .. file
            local mode = lfs.attributes(fpath, "mode")
            
            -- CHECK: Is it a directory? AND is it NOT a hidden .sdr folder?
            if mode == "directory" and not file:match("%.sdr$") then
                has_subdir = true
                break
            end
        end
    end

    folder_content_cache[dir_path] = has_subdir
    return has_subdir
end

-- 2. The Comparison Function
local function smart_sort(x, y)
    local a = x.sort_item
    local b = y.sort_item

    -- CONDITION A: If the folder has REAL subfolders, IGNORE everything and sort by Name
    if a.parent_has_subdirs then
        return ffiUtil.strcoll(x.text, y.text)
    end

    -- CONDITION B: Files-only folder. Apply the custom logic.

    -- 1. Sort by Status Priority
    if a.status_num ~= b.status_num then
        return a.status_num < b.status_num
    end

    -- 2. Sort by Series Name
    -- If one has series and other doesn't, put Series first
    if a.series and not b.series then return true end
    if not a.series and b.series then return false end

    local both_completed = (a.status_num == 4 and b.status_num == 4)

    if a.series and b.series then
        if a.series ~= b.series then
            return ffiUtil.strcoll(a.series, b.series)
        end 
        
        -- 3. Sort by Series Index (Number)
        -- Only if Series Names are identical
        if a.series_index ~= b.series_index then
            local cmp = a.series_index < b.series_index
            -- If completed, REVERSE the index order (newest books first)
            if both_completed then
                return not cmp  -- 10, 9, 8... for Completed
            else
                return cmp      -- 1, 2, 3... for others
            end
        end
    end

    -- 4. Final Fallback: Sort by Title/Name
    return ffiUtil.strcoll(x.text, y.text)
end

-- 3. Register the Sort Method
BookList.collates.smart_series_sort = {
    text = _("Smart Series & Status"),
    menu_order = 100,
    can_collate_mixed = true,
    
    init_sort_func = function(cache)
        folder_content_cache = {} 
        return smart_sort, cache
    end,
    
    item_func = function(item, ui)
        -- A. Determine Book Info (Metadata)
        if item.attr.mode == "file" then
            local book_info = BookList.getBookInfo(item.path)
            
            item.status = book_info.status or "new"
            item.status_num = status_priority[item.status] or 99
            
        if ui and ui.bookinfo then
            local doc_props = ui.bookinfo:getDocProps(item.path)
            item.series = doc_props.series or "\u{FFFF}" -- Force no-series to bottom
            item.series_index = tonumber(doc_props.series_index) or 0
        else
            -- Fallback if database is not ready
            item.series = "\u{FFFF}"
            item.series_index = 0
        end
            
            item.sort_item = item
        else
            -- Directory items
            item.status_num = 0
            item.series_index = 0
            item.sort_item = item
        end

        -- B. Detect Context
        -- If the item displayed in the list IS a visible directory, the folder is mixed.
        if item.attr.mode == "directory" then
            item.parent_has_subdirs = true
        else
            -- If it's a file, scan the disk, but ignore .sdr folders
            local parent_path = ffiUtil.dirname(item.path)
            item.parent_has_subdirs = directory_has_real_subfolders(parent_path)
        end

        return item
    end,
}