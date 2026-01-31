local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local Device = require("device")
local logger = require("logger")
local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("json")
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local InputDialog = require("ui/widget/inputdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")

local LektrSync = WidgetContainer:extend{
    name = "lektr_sync",
    is_doc_only = false,
}

function LektrSync:init()
    self:loadSettings()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function LektrSync:loadSettings()
    local settings_file = DataStorage:getSettingsDir() .. "/lektr_sync.lua"
    self.settings = LuaSettings:open(settings_file)
    self.api_url = self.settings:readSetting("api_url") or "http://YOUR_SERVER_IP:3000/api/v1/import"
    self.auth_token = self.settings:readSetting("auth_token") or ""
end

function LektrSync:saveSettings()
    self.settings:saveSetting("api_url", self.api_url)
    self.settings:saveSetting("auth_token", self.auth_token)
    self.settings:saveSetting("auto_sync", self.auto_sync)
    self.settings:flush()
end

function LektrSync:addToMainMenu(menu_items)
    menu_items.lektr_sync = {
        text = "Lektr Sync",
        sub_item_table = {
            {
                text = "Sync Current Book",
                callback = function()
                    self:syncCurrentBook()
                end,
            },
            {
                text = "Sync All History",
                callback = function()
                    self:syncAllHistory()
                end,
            },
            {
                text = "Settings",
                sub_item_table = {
                    {
                        text = "Login",
                        callback = function()
                            self:login()
                        end,
                    },
                    {
                        text = "Set API URL",
                        callback = function()
                            self:setApiUrl()
                        end,
                    },
                    {
                        text = "Set Auth Token (Manual)",
                        callback = function()
                            self:setAuthToken()
                        end,
                    },
                    {
                        text = "Auto-Sync on Open/Close",
                        checked_func = function() 
                            return self.settings:readSetting("auto_sync") 
                        end,
                        callback = function()
                            local current = self.settings:readSetting("auto_sync") or false
                            self.settings:saveSetting("auto_sync", not current)
                            self.settings:flush()
                        end,
                    },
                    {
                        text = "Upload Exported JSON",
                        callback = function()
                            self:uploadExportedJson()
                        end,
                        help_text = "Upload a JSON file created by KOReader's Export Highlights feature. This includes proper page numbers.",
                    },
                }
            }
        }
    }
end

function LektrSync:onReaderReady()
    if self.settings:readSetting("auto_sync") then
        UIManager:scheduleIn(3, function()
            self:syncCurrentBook(true)
        end)
    end
end

function LektrSync:onCloseDocument()
    if self.settings:readSetting("auto_sync") then
        self:syncCurrentBook(true)
    end
end

function LektrSync:syncAllHistory()
    if not NetworkMgr:isConnected() then
        NetworkMgr:turnOnWifi(function()
            self:syncAllHistory()
        end)
        return
    end

    UIManager:show(ConfirmBox:new{
        text = "This will scan your reading history and sync all books with highlights.\n\nThis might take a while. Proceed?",
        ok_text = "Start Sync",
        cancel_text = "Cancel",
        ok_callback = function()
            self:performBulkSync()
        end,
    })
end

function LektrSync:performBulkSync()
    UIManager:show(InfoMessage:new{
        text = "Starting Bulk Sync...",
        timeout = 2,
    })
    
    local ReadHistory = require("readhistory")
    local DocSettings = require("docsettings")
    local history_items = ReadHistory.hist or {}
    
    local count = 0
    local success = 0
    local failed = 0
    local books_data = {}
    
    for _, item in ipairs(history_items) do
        local file_path = item.file
        if file_path then
            local doc_settings = DocSettings:open(file_path)
            if doc_settings then
                local props = doc_settings:readSetting("doc_props") or {}
                local title = props.title or item.text or "Untitled"
                local author = props.authors or props.author or nil
                
                local h_list = {}
                
                -- Get highlights from multiple sources
                
                -- 1. bookmarks table
                local bookmarks = doc_settings:readSetting("bookmarks") or {}
                for _, b in ipairs(bookmarks) do
                    if b.text and b.text ~= "" then
                        -- In bookmarks, 'page' is often XPath, 'pageno' might have number
                        local page_num = nil
                        if type(b.pageno) == "number" then
                            page_num = b.pageno
                        elseif type(b.page) == "number" then
                            page_num = b.page
                        end
                        
                        table.insert(h_list, {
                            text = b.text,
                            notes = b.notes,
                            chapter = b.chapter,
                            page = page_num,
                            datetime = b.datetime,
                        })
                    end
                end
                
                -- 2. annotations table (newer format)
                local annotations = doc_settings:readSetting("annotations") or {}
                for _, a in ipairs(annotations) do
                    if a.text and a.text ~= "" then
                        local page_num = nil
                        if type(a.pageno) == "number" then
                            page_num = a.pageno
                        elseif type(a.page) == "number" then
                            page_num = a.page
                        end
                        
                        table.insert(h_list, {
                            text = a.text,
                            notes = a.note,
                            chapter = a.chapter,
                            page = page_num,
                            datetime = a.datetime,
                        })
                    end
                end
                
                -- 3. highlight table (page-keyed)
                local highlight = doc_settings:readSetting("highlight") or {}
                for page_key, page_highlights in pairs(highlight) do
                    if type(page_highlights) == "table" then
                        for _, hl in ipairs(page_highlights) do
                            if hl.text and hl.text ~= "" then
                                local page_num = nil
                                if type(hl.pageno) == "number" then
                                    page_num = hl.pageno
                                elseif type(hl.page) == "number" then
                                    page_num = hl.page
                                end
                                
                                table.insert(h_list, {
                                    text = hl.text,
                                    notes = hl.note,
                                    chapter = hl.chapter,
                                    page = page_num,
                                    datetime = hl.datetime,
                                })
                            end
                        end
                    end
                end
                
                if #h_list > 0 then
                    local payload = {
                        source = "koreader",
                        data = {
                            title = title,
                            author = author,
                            entries = h_list,
                            file = file_path,
                            md5sum = doc_settings:readSetting("partial_md5_checksum")
                        }
                    }
                    
                    local json_str = json.encode(payload)
                    if json_str and self:sendJson(json_str) then
                        success = success + 1
                    else
                        failed = failed + 1
                    end
                    count = count + 1
                end
                
                doc_settings:close()
            end
        end
    end
    
    UIManager:show(InfoMessage:new{
        text = string.format("Bulk Sync Complete!\n\n%d books with highlights\n%d success, %d failed", count, success, failed),
    })
end

function LektrSync:uploadExportedJson()
    if not NetworkMgr:isConnected() then
        NetworkMgr:turnOnWifi(function()
            self:uploadExportedJson()
        end)
        return
    end
    
    local PathChooser = require("ui/widget/pathchooser")
    local home_dir = require("apps/filemanager/filemanagerutil").getDefaultDir()
    
    local path_chooser = PathChooser:new{
        title = "Select Exported JSON File",
        path = home_dir,
        select_directory = false,
        select_file = true,
        file_filter = function(filename)
            return filename:match("%.json$")
        end,
        onConfirm = function(file_path)
            self:processExportedJson(file_path)
        end,
    }
    UIManager:show(path_chooser)
end

function LektrSync:processExportedJson(file_path)
    local f = io.open(file_path, "r")
    if not f then
        UIManager:show(InfoMessage:new{
            text = "Failed to open file: " .. file_path,
        })
        return
    end
    
    local content = f:read("*a")
    f:close()
    
    local data = json.decode(content)
    if not data then
        UIManager:show(InfoMessage:new{
            text = "Failed to parse JSON file",
        })
        return
    end
    
    -- Handle the wrapped format from KOReader export
    local documents = data.documents or { data }
    
    local success = 0
    local failed = 0
    
    for _, doc in ipairs(documents) do
        local payload = {
            source = "koreader",
            data = {
                title = doc.title,
                author = doc.author,
                entries = doc.entries or {},
                md5sum = doc.md5sum,
                file = doc.file,
            }
        }
        
        local json_str = json.encode(payload)
        if json_str and self:sendJson(json_str) then
            success = success + 1
        else
            failed = failed + 1
        end
    end
    
    UIManager:show(InfoMessage:new{
        text = string.format("Upload Complete!\n\n%d books uploaded\n%d success, %d failed", #documents, success, failed),
    })
end

function LektrSync:sendJson(json_body)
    local response_body = {}
    local res, code, headers = http.request{
        url = self.api_url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#json_body),
            ["Cookie"] = "token=" .. (self.auth_token or "")
        },
        source = ltn12.source.string(json_body),
        sink = ltn12.sink.table(response_body)
    }
    return code == 200 or code == 201
end

function LektrSync:login()
    local email_dialog
    email_dialog = InputDialog:new{
        title = "Login: Email",
        input = "",
        input_type = "email",
        buttons = {{
            {
                text = "Cancel",
                id = "close",
                callback = function()
                    UIManager:close(email_dialog)
                end,
            },
            {
                text = "Next",
                is_enter_default = true,
                callback = function()
                    local email = email_dialog:getInputText()
                    UIManager:close(email_dialog)
                    if email and email ~= "" then
                        self:askPassword(email)
                    end
                end,
            },
        }},
    }
    UIManager:show(email_dialog)
    email_dialog:onShowKeyboard()
end

function LektrSync:askPassword(email)
    local pass_dialog
    pass_dialog = InputDialog:new{
        title = "Login: Password",
        input = "",
        text_type = "password",
        buttons = {{
            {
                text = "Cancel",
                id = "close",
                callback = function()
                    UIManager:close(pass_dialog)
                end,
            },
            {
                text = "Login",
                is_enter_default = true,
                callback = function()
                    local password = pass_dialog:getInputText()
                    UIManager:close(pass_dialog)
                    if password and password ~= "" then
                        self:performLogin(email, password)
                    end
                end,
            },
        }},
    }
    UIManager:show(pass_dialog)
    pass_dialog:onShowKeyboard()
end

function LektrSync:performLogin(email, password)
    if not NetworkMgr:isConnected() then
        NetworkMgr:turnOnWifi(function()
            self:performLogin(email, password)
        end)
        return
    end

    UIManager:show(InfoMessage:new{
        text = "Logging in...",
        timeout = 1,
    })

    -- Construct login URL from import URL
    -- Handle various URL formats:
    -- http://server:3000/api/v1/import -> http://server:3000/api/v1/auth/login
    -- http://server:3000/api/v1 -> http://server:3000/api/v1/auth/login
    -- http://server:3000 -> http://server:3000/api/v1/auth/login
    local login_url = self.api_url
    login_url = login_url:gsub("/import$", "")  -- Remove /import if present
    login_url = login_url:gsub("/+$", "")        -- Remove trailing slashes
    
    -- If URL doesn't end with /api/v1, add it
    if not login_url:match("/api/v1$") then
        if login_url:match("/api$") then
            login_url = login_url .. "/v1"
        else
            login_url = login_url .. "/api/v1"
        end
    end
    login_url = login_url .. "/auth/login"
    
    logger.info("LektrSync: Login URL:", login_url)
    
    local payload = {
        email = email,
        password = password
    }
    local json_body = json.encode(payload)
    local response_body = {}
    
    local res, code, headers = http.request{
        url = login_url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#json_body)
        },
        source = ltn12.source.string(json_body),
        sink = ltn12.sink.table(response_body)
    }

    if code == 200 or code == 201 then
        local set_cookie = headers and (headers["set-cookie"] or headers["Set-Cookie"])
        
        if set_cookie then
            local token = set_cookie:match("token=([^;]+)")
            if token then
                self.auth_token = token
                self:saveSettings()
                UIManager:show(InfoMessage:new{
                    text = "Login Successful!",
                    timeout = 2,
                })
                return
            end
        end
        UIManager:show(InfoMessage:new{
            text = "Login succeeded but token not found in response.",
        })
    else
        UIManager:show(InfoMessage:new{
            text = "Login Failed: HTTP " .. tostring(code),
        })
    end
end

function LektrSync:setApiUrl()
    local dialog
    dialog = InputDialog:new{
        title = "Lektr API URL",
        input = self.api_url,
        input_hint = "http://192.168.1.100:3000/api/v1/import",
        buttons = {{
            {
                text = "Cancel",
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = "Save",
                is_enter_default = true,
                callback = function()
                    local url = dialog:getInputText()
                    if url and url ~= "" then
                        self.api_url = url
                        self:saveSettings()
                        UIManager:show(InfoMessage:new{
                            text = "API URL Saved!",
                            timeout = 2,
                        })
                    end
                    UIManager:close(dialog)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function LektrSync:setAuthToken()
    local dialog
    dialog = InputDialog:new{
        title = "Auth Token",
        description = "Enter your session token (from browser cookies)",
        input = self.auth_token,
        buttons = {{
            {
                text = "Cancel",
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = "Save",
                is_enter_default = true,
                callback = function()
                    local token = dialog:getInputText()
                    self.auth_token = token or ""
                    self:saveSettings()
                    UIManager:show(InfoMessage:new{
                        text = "Token Saved!",
                        timeout = 2,
                    })
                    UIManager:close(dialog)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function LektrSync:syncCurrentBook(is_auto)
    if not NetworkMgr:isConnected() then
        if is_auto then return end
        NetworkMgr:turnOnWifi(function()
            self:syncCurrentBook()
        end)
        return
    end

    -- Check if we have a document open
    if not self.ui or not self.ui.document then
        if not is_auto then
            UIManager:show(InfoMessage:new{
                text = "Please open a book first!",
                timeout = 2,
            })
        end
        return
    end

    if not is_auto then
        UIManager:show(InfoMessage:new{
            text = "Syncing to Lektr...",
            timeout = 1,
        })
    end

    local doc = self.ui.document
    local props = doc:getProps() or {}
    local title = props.title or "Untitled"
    local author = props.authors or props.author or "Unknown"
    
    -- Get the file path for DocSettings
    local file_path = self.ui.document.file
    local DocSettings = require("docsettings")
    
    -- Get highlights/bookmarks from document settings file (not in-memory)
    local h_list = {}
    local doc_settings = DocSettings:open(file_path)
    
    if doc_settings then
        -- Try multiple locations where KOReader stores highlights
        
        -- 1. Check "bookmarks" (includes highlights in newer KOReader)
        local bookmarks = doc_settings:readSetting("bookmarks") or {}
        logger.info("LektrSync: Found", #bookmarks, "items in bookmarks")
        for i, b in ipairs(bookmarks) do
            -- KOReader 2025+: highlighted text is in "notes", "text" is user comment
            -- Older versions: might use "text" for highlighted content
            local highlight_content = b.notes or b.text or b.highlighted_text
            
            if highlight_content and highlight_content ~= "" then
                -- Debug: log what fields are available (first item only)
                if i == 1 then
                    local fields = {}
                    for k, v in pairs(b) do
                        local val_preview = type(v) == "string" and (v:sub(1,30) .. "...") or type(v)
                        table.insert(fields, k .. "=" .. val_preview)
                    end
                    logger.info("LektrSync: Bookmark fields:", table.concat(fields, ", "))
                end
                
                -- Try to get page number
                local page_num = nil
                if type(b.page) == "number" then
                    page_num = b.page
                elseif b.pageno then
                    page_num = b.pageno
                elseif self.ui and self.ui.document and b.page then
                    -- b.page contains XPath - try to convert to page number
                    local doc = self.ui.document
                    if doc.getPageFromXPointer then
                        local ok, page = pcall(doc.getPageFromXPointer, doc, b.page)
                        if ok and page then page_num = page end
                    end
                end
                
                -- User's annotation/comment (opposite field from highlight_content)
                local user_note = nil
                if b.notes and b.notes ~= "" and b.notes ~= highlight_content then
                    user_note = nil  -- notes is the highlight, text might be comment
                    if b.text and b.text ~= "" and b.text ~= highlight_content then
                        user_note = b.text
                    end
                elseif b.text and b.text ~= "" and b.text ~= highlight_content then
                    user_note = b.text
                end
                
                table.insert(h_list, {
                    text = highlight_content,
                    notes = user_note,
                    chapter = b.chapter,
                    page = page_num,
                    datetime = b.datetime,
                    sort = "highlight"
                })
            end
        end
        
        -- 2. Check "annotations" (newer KOReader versions)
        local annotations = doc_settings:readSetting("annotations") or {}
        logger.info("LektrSync: Found", #annotations, "items in annotations")
        for _, a in ipairs(annotations) do
            local ann_content = a.notes or a.text or a.highlighted_text
            if ann_content and ann_content ~= "" then
                table.insert(h_list, {
                    text = ann_content,
                    notes = a.note,
                    chapter = a.chapter,
                    page = a.page,
                    datetime = a.datetime,
                    sort = "highlight"
                })
            end
        end
        
        -- 3. Check "highlight" table (page-indexed highlights)
        local highlight = doc_settings:readSetting("highlight") or {}
        local highlight_count = 0
        for page_key, page_highlights in pairs(highlight) do
            if type(page_highlights) == "table" then
                for _, hl in ipairs(page_highlights) do
                    local hl_content = hl.notes or hl.text or hl.highlighted_text
                    if hl_content and hl_content ~= "" then
                        highlight_count = highlight_count + 1
                        
                        -- Try to get numeric page from multiple sources
                        local page_num = nil
                        if type(hl.page) == "number" then
                            page_num = hl.page
                        elseif hl.pageno then
                            page_num = hl.pageno
                        elseif self.ui and self.ui.document then
                            local doc = self.ui.document
                            if doc.getPageFromXPointer and hl.pos0 then
                                local ok, page = pcall(doc.getPageFromXPointer, doc, hl.pos0)
                                if ok and page then
                                    page_num = page
                                end
                            end
                        end
                        
                        table.insert(h_list, {
                            text = hl_content,
                            notes = hl.note,
                            chapter = hl.chapter,
                            page = page_num,
                            datetime = hl.datetime,
                            sort = "highlight"
                        })
                    end
                end
            end
        end
        logger.info("LektrSync: Found", highlight_count, "items in highlight table")
    end
    
    logger.info("LektrSync: Total highlights to sync:", #h_list)
    
    local payload = {
        source = "koreader",
        data = {
            title = title,
            author = author,
            entries = h_list
        }
    }
    
    local json_body = json.encode(payload)
    if not json_body then
        logger.warn("LektrSync: Failed to encode JSON")
        return
    end
    
    local response_body = {}
    local res, code, response_headers = http.request{
        url = self.api_url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#json_body),
            ["Cookie"] = "token=" .. (self.auth_token or "")
        },
        source = ltn12.source.string(json_body),
        sink = ltn12.sink.table(response_body)
    }

    if code == 200 or code == 201 then
        if not is_auto then
            UIManager:show(InfoMessage:new{
                text = "Sync Successful!",
                timeout = 2,
            })
        end
    else
        if not is_auto then
            UIManager:show(InfoMessage:new{
                text = "Sync Failed: HTTP " .. tostring(code),
            })
        end
        logger.warn("LektrSync Failed:", code, table.concat(response_body or {}))
    end
end

return LektrSync
