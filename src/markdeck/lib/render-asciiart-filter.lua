--
-- blatantly copied from https://stackoverflow.com/a/28665686
--

function shlex(text)
    local result = {}
    local e = 0
    while true do
        local b = e+1
        b = text:find("%S",b)
        if b==nil then
            break
        end
        if text:sub(b,b)=="'" then
            e = text:find("'",b+1)
            b = b+1
        elseif text:sub(b,b)=='"' then
            e = text:find('"',b+1)
            b = b+1
        else
            e = text:find("%s",b+1)
        end
        if e==nil then
            e=#text+1
        end
        -- print("["..text:sub(b,e-1).."]")
        table.insert(result, text:sub(b, e-1))
    end
    return result
end

-- for _, token in pairs(shlex("aha 'foo bar' egg")) do
    -- print(token)
-- end
CONFIGFILE=os.getenv("ASCIIART_CONFIG") or "render-asciiart-filter.config"
local config = {}
local configfile,err = loadfile(CONFIGFILE, "t", config)
if configfile then
   configfile() -- load the config
else
   io.stderr:write(err)
end

local outputdir=io.open("rendered","r")
if outputdir~=nil then
    io.close(outputdir)
else
    os.execute("mkdir rendered")
end

LIBDIR=os.getenv("ASCIIART_LIBDIR") or "lib"

local renderer = {
    render_ditaa = function(text, attrs)
        if attrs[1] then
            attrs = attrs[1][2]
        else
            attrs = config.ditaa.defaultargs or ""
        end
        params = {"-jar", LIBDIR .. "/ditaa.jar"}
        for _, w in pairs(shlex(attrs)) do
            table.insert(params, w)
        end
        table.insert(params, "-")
        table.insert(params, "-")
        return {"java", params, text}, "png"
    end,
    render_plantuml = function(text, attrs)
        if attrs[1] then
            attrs = attrs[1][2]
        else
            attrs = config.plantuml.defaultargs or ""
        end
        params = {"-jar", LIBDIR .. "/plantuml.jar", "-tsvg", "-p", "-Sbackgroundcolor=transparent"}
        for w in attrs:gmatch("%S+") do
            table.insert(params, w)
        end
        return {"java", params, text}, "svg"
    end,
    render_dot = function(text, attrs)
        if attrs[1] then
            attrs = attrs[1][2]
        else
            attrs = config.dot.defaultargs or ""
        end
        params = {"-Tsvg"}
        for w in attrs:gmatch("%S+") do
            table.insert(params, w)
        end
        return {"dot", params, text}, "svg"
    end,
    render_qr = function(text, attrs)
        if attrs[1] then
            attrs = attrs[1][2]
        else
            attrs = config.qr.defaultargs or ""
        end
        params = {"-o", "-"}
        for w in attrs:gmatch("%S+") do
            table.insert(params, w)
        end
        return {"qrencode", params, text}, "png"
    end,
    render_vegalite = function(text, attrs)
        return {"vl2svg", {}, text}, "svg"
    end,
}

-- vegalite_spots_nr = 0
-- local js_renderer = {
--     render_vegalite = function(text, attrs)
--         -- io.stderr:write("vegalite text\n" .. text .. "\n")
--         local nr = vegalite_spots_nr
--         vegalite_spots_nr = vegalite_spots_nr + 1
--         return {
--                     pandoc.Div({
--                         pandoc.Para{pandoc.Str("")}
--                     }, pandoc.Attr("vegalite_spot_" .. nr)),
--                     pandoc.Plain{pandoc.RawInline("html", "<script>vegalite_spots.push(" .. text .. ")</script>")},
--                }
--     end,
-- }


images = {}

function Cleanup(doc)
    local pfile = io.popen('ls -a rendered/*.png rendered/*.svg 2> /dev/null')
    for fname in pfile:lines() do
        if not images[fname] then
            io.stderr:write("removing obsolete '" .. fname .. "'\n")
            os.remove(fname)
        end
    end
    pfile:close()

    return nil
end


function Render(elem, attr)
    for format, render_cmd in pairs(renderer) do
        if elem.classes[1] == format then
            local cmd, filetype = render_cmd(elem.text, elem.attributes or {})
            local mimetype = "image/" .. filetype
            local fname = "rendered/" .. format .. "-" .. pandoc.sha1(cmd[1] .. table.concat(cmd[2], " ") .. cmd[3]) .. "." .. filetype
            local data = nil

            local f=io.open(fname,"rb")
            if f~=nil then
                io.stderr:write("cached " .. format .. " found\n")
                data = f:read("*all")
                f:close()
            else
                io.stderr:write("call " .. format .. "\n")
                data = pandoc.pipe(cmd[1], cmd[2], cmd[3])
                local f=io.open(fname, "wb")
                f:write(data)
                f:close()
            end
            images[fname] = true
            pandoc.mediabag.insert(fname, mimetype, data)
            return pandoc.Para{ pandoc.Image({pandoc.Str("")}, fname) }
        end
    end
end

return {{CodeBlock=Render}, {Pandoc=Cleanup}}