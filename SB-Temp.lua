--[[

----------------------------------------------------------------------------

   SB-Temp Display -- makes a Telemetry Window for Carsten Groen's SB-Temp sensor

   Implements one fullscreen telemetry windows and one menu for editing parms
   or settable items

   Borrows some display code from Daniel's excellent CTU.lua program

   Requires transmitter firmware 4.22 or higher.
   ADDED 16-11-2020  
    
----------------------------------------------------------------------------

   Released under MIT-license

   Copyright (c) 2019 DFM

   Permission is hereby granted, free of charge, to any person
   obtaining a copy of this software and associated documentation
   files (the "Software"), to deal in the Software without
   restriction, including without limitation the rights to use, copy,
   modify, merge, publish, distribute, sublicense, and/or sell copies
   of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:
   
   The above copyright notice and this permission notice shall be
   included in all copies or substantial portions of the Software.
   
   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
   BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
   ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
   CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE.

--]]

----------------------------------------------------------------------------

local appShort   = "SB-Temp"
local appName    = "SB-Temp Display"
local appAuthor  = "DFM"
local appVersion = "1.03"
local appDir = "Apps/digitechSBT/"
local transFile  = appDir .. "Trans.jsn"
local pcallOK, emulator

local SBTDeviceID=16819270 -- 0x100A446

----------------------------------------------------------------------------

local ren = lcd.renderer()
local screens={}
local arcFile = {}
local screenConfig={}
local screenIdx
local builtIn
local maxBuiltIn
local backGndImage
local jsnFileName

local SBT_Telem = {
   T1={SeId=0,SePa=0,value=0,unit=" "},
   T2={SeId=0,SePa=0,value=0,unit=" "},
   T3={SeId=0,SePa=0,value=0,unit=" "},
   T4={SeId=0,SePa=0,value=0,unit=" "},
   T5={SeId=0,SePa=0,value=0,unit=" "},
   T6={SeId=0,SePa=0,value=0,unit=" "},
   T7={SeId=0,SePa=0,value=0,unit=" "},
   T8={SeId=0,SePa=0,value=0,unit=" "},
}

local needle_poly_small = {
   {-2,12},
   {-1,26},
   {1,26},
   {2,12}
}

local function readSensors()
   local text
   local sensors = system.getSensors()
   --print("sensors:", sensors)
   
   for _, sensor in ipairs(sensors) do
      if (sensor.label ~= "") then
	 if sensor.id == SBTDeviceID and sensor.param ~= 0 then
	    SBT_Telem[sensor.label].SeId = sensor.id
	    SBT_Telem[sensor.label].SePa = sensor.param
	    SBT_Telem[sensor.label].unit = sensor.unit
	 end
      end
   end
end

local function drawShape(col, row, shape, rotation, clr)
   local sinShape, cosShape

   sinShape = math.sin(rotation)
   cosShape = math.cos(rotation)
   ren:reset()
   for index, point in pairs(shape) do
      ren:addPoint(
	 col + (point[1] * cosShape - point[2] * sinShape + 0.5),
	 row + (point[1] * sinShape + point[2] * cosShape + 0.5)
      ) 
   end
   lcd.setColor(clr.r,clr.g,clr.b)
   ren:renderPolygon()
   lcd.setColor(0, 0, 0)
end

local function drawTextCenter(font, txt, ox, oy)
    lcd.drawText(ox - lcd.getTextWidth(font, txt) / 2, oy, txt, font)
end

local function drawHistogram(label, min, mid, max, temp, unit, ox, oy)

   local color={}
   local hgt
   
   if temp <= mid then
      color.r=255*(temp-min)/(mid-min)
      color.g=255
      color.b=0
   else
      color.r=255
      color.g=255*(1-(temp-mid)/(max-mid))
      color.b=0
   end
   
   drawTextCenter(FONT_MINI, label, ox+15, oy+0)
   lcd.setColor(0,0,255)
   drawTextCenter(FONT_BOLD, string.format("%d", temp), ox+15, oy+16)
   
   lcd.setColor(120,120,120)
   if min ~= 0 then
      drawTextCenter(FONT_MINI,
		     string.format("%d", min) .. " - " .. string.format("%d", max) .. unit,
		     ox + 25, oy+48)
   else
      drawTextCenter(FONT_MINI,
		     string.format("%d", max) .. unit,
		     ox + 25, oy+48)
   end
   
   lcd.setColor(0,0,0)
   
   temp = math.min(max, math.max(temp, min))
   
   hgt = 50* ( (temp - min) / (max - min) )


   lcd.setColor(color.r, color.g, color.b)
   lcd.drawRectangle(ox+35, oy-5, 10, 50)
   lcd.drawRectangle(ox+34, oy-6, 12, 52)   
   lcd.drawFilledRectangle(ox+35, oy+25-hgt+20, 10, hgt)

   lcd.setColor(0,0,0)
   
end

local function drawGauge(label, min, mid, max, temp, unit, ox, oy)
   
   local color={}
   local theta
   
   if temp <= mid then
      color.r=255*(temp-min)/(mid-min)
      color.g=255
      color.b=0
   else
      color.r=255
      color.g=255*(1-(temp-mid)/(max-mid))
      color.b=0
   end
   
   drawTextCenter(FONT_MINI, label, ox+25, oy+38)
   lcd.setColor(0,0,255)
   drawTextCenter(FONT_BOLD, string.format("%d", temp), ox+25, oy+16)
   lcd.setColor(120,120,120)
   if min ~= 0 then
      drawTextCenter(FONT_MINI,
		     string.format("%d", min) .. " - " .. string.format("%d", max) .. unit,
		     ox + 25, oy+52)
   else
      drawTextCenter(FONT_MINI,
		     string.format("%d", max) .. unit,
		     ox + 25, oy+52)
   end
   
   lcd.setColor(0,0,0)
   
   temp = math.min(max, math.max(temp, min))
   theta = math.pi - math.rad(135 - 2 * 135 * (temp - min) / (max - min) )
   
   if arcFile ~= nil then
      lcd.drawImage(ox, oy, arcFile)
      drawShape(ox+25, oy+26, needle_poly_small, theta, color)
   end
end

local function screenInit()
   local text
   if screenIdx <= maxBuiltIn then
      print("builtin")
      builtIn = true
      jsnFileName = appDir.."BuiltInScreens/"..
	 string.sub(screens[screenIdx], 2)..".jsn"
      print("jsnFileName:", jsnFileName)
      text = io.readall(jsnFileName)
      print("readall:", text)
      screenConfig = json.decode(text)
   else
      print("image", #screens, maxBuiltIn, screenIdx)
      if #screens > maxBuiltIn then
	 builtIn = false
	 jsnFileName = appDir.."ImageScreens/"..screens[screenIdx]..".jsn"
	 print("jsnFileName:", jsnFileName)
	 text = io.readall(jsnFileName)
	 print("readall:", text)
	 screenConfig = json.decode(text)
	 backGndImage = lcd.loadImage(appDir.."ImageScreens/"..screenConfig.Image)
      else
	 system.messageBox("No Image Screens Available", 3)
      end
   end
end


local function screenIdxChanged(value)
   screenIdx = value
   system.pSave("screenIdx", value)
   screenInit()
   form.reinit()
end

local function jsnWrite()
   local fp
   local text
   
   fp = io.open(jsnFileName, "w")
   text=json.encode(screenConfig)
   text = string.gsub(text, "%[", "\r\n[\r\n")
   text = string.gsub(text, "},", "},\r\n")
   text = string.gsub(text, "}%]", "}\r\n]\r\n")
   text = string.gsub(text, "%]\r\n,", "],\r\n")
   text = string.gsub(text, "\r\n,", ",\r\n")
   io.write(fp, text)
   io.close(fp)
end

local function jsnChanged(value, k, elem)
   screenConfig.Probes[k][elem] = value
   jsnWrite()
end

local function initForm(subForm)
   SForm = subForm
   if subForm == 1 then
      form.setTitle("appName")
      form.addRow(2)
      form.addLabel({label="Select Display Screen", width=200})
      form.addSelectbox(screens, screenIdx, true, screenIdxChanged)

      for j=1,8,1 do
	 form.addRow(2)
	 form.addLink((function() form.reinit(j+1) end),
	    {label="Probe "..j.." ("..screenConfig.Probes[j].Name ..") >>"})
      end
      form.addRow(1)
      form.addLabel({label=appShort,font=FONT_MINI, alignRight=true})      
   else
      local k=subForm-1

      form.setTitle("Editing Probe#"..k)
      form.addLink((function() form.reinit(1) end), {label="<< Back"})

      form.addRow(2)
      form.addLabel({label="Probe name", width=220})
      form.addTextbox(screenConfig.Probes[k].Name, 6, 
		      (function(x) return jsnChanged(x, k, "Name") end))
      form.addRow(2)
      form.addLabel({label="Temperature limit Green", width=220})
      form.addIntbox(screenConfig.Probes[k].Green,0,1000,1,0,1,
		     (function(x) return jsnChanged(x, k, "Green") end))      

      form.addRow(2)
      form.addLabel({label="Temperature limit Yellow", width=220})
      form.addIntbox(screenConfig.Probes[k].Yellow,0,1000,1,0,1,
		     (function(x) return jsnChanged(x, k, "Yellow") end))
		     
      form.addRow(2)
      form.addLabel({label="Temperature limit Red", width=220})
      form.addIntbox(screenConfig.Probes[k].Red,0,1000,1,0,1,
		     (function(x) return jsnChanged(x, k, "Red") end))

      form.addRow(1)
      form.addLabel({label=appShort.."SF",font=FONT_MINI, alignRight=true})
   end
end

local function loop()
   local sensor
   for k,v in pairs(SBT_Telem) do
      if v.SeId and v.SeId ~= 0 then
	 sensor = system.getSensorByID(v.SeId, v.SePa)
      end
      if sensor and sensor.valid then
	 v.value = sensor.value
      end
   end
end


local function teleBuiltIn()
   local x0=12
   local y0=12
   local idx
   local k

   if screens[screenIdx] == "#Gauge" then
      for i=1,4,1 do
	 for j=1,2,1 do
	    idx = i+4*(j-1)	 
	    k="T"..idx
	    drawGauge(screenConfig.Probes[idx].Name,
		      screenConfig.Probes[idx].Green,
		      screenConfig.Probes[idx].Yellow,
		      screenConfig.Probes[idx].Red,
		      SBT_Telem[k].value or 0,
		      SBT_Telem[k].unit or "",
		      x0+(i-1)*80, y0+(j-1)*80)
	 end
      end
   elseif screens[screenIdx] == "#Histogram" then
      for i=1,4,1 do
	 for j=1,2,1 do
	    idx = i+4*(j-1)	 
	    k="T"..idx
	    drawHistogram(screenConfig.Probes[idx].Name,
		      screenConfig.Probes[idx].Green,
		      screenConfig.Probes[idx].Yellow,
		      screenConfig.Probes[idx].Red,
		      SBT_Telem[k].value or 0,
		      SBT_Telem[k].unit or "",
		      x0+(i-1)*80, y0+(j-1)*80)
	 end
      end
   end
   
end

local function teleImage()
   local midW=160
   local midH=80
   local maxH=159
   local x,y
   local xp, yp
   local xt, yt
   local dx1, dx2 = 0, 0
   local r,g,b
   local text
   
   lcd.drawImage( (310-backGndImage.width)/2+2+60, 10, backGndImage)

   for k = 1, #screenConfig.Probes do
      x=screenConfig.Probes[k].XP
      y=screenConfig.Probes[k].YP
      x = x + midW
      y = y + midH
      y=maxH-y
      y=y-15
      x=x-2+60
      
      kk = "T"..k
      if SBT_Telem[kk].value < screenConfig.Probes[k].Green then
	 r,g,b = 0,0,255
	 lcd.setColor(r,g,b)
      elseif SBT_Telem[kk].value >= screenConfig.Probes[k].Green and
      SBT_Telem[kk].value < screenConfig.Probes[k].Yellow then
	 r,g,b = 25,255,45
	 lcd.setColor(r,g,b)
      elseif SBT_Telem[kk].value >= screenConfig.Probes[k].Yellow and
      SBT_Telem[kk].value < screenConfig.Probes[k].Red then
	 r,g,b = 245,210,50
	 lcd.setColor(r,g,b)
      elseif SBT_Telem[kk].value >= screenConfig.Probes[k].Red then
	 r,g,b = 255,0,0
	 lcd.setColor(r,g,b)
      end

      xp = x - lcd.getTextWidth(FONT_NORMAL, screenConfig.Probes[k].Name)/2
      yp = y + lcd.getTextHeight(FONT_NORMAL)/2
      lcd.drawText(xp,yp, screenConfig.Probes[k].Name)

      lcd.setColor(0,0,0)
      
      xt=screenConfig.Probes[k].XT
      yt=screenConfig.Probes[k].YT
      text = screenConfig.Probes[k].Name.."("..kk.."): "
      dx1 = math.max(dx1,lcd.getTextWidth(FONT_NORMAL, text))
      lcd.drawText(xt, yt, text)
      lcd.setColor(r,g,b)
      text = string.format("%.1f", SBT_Telem[kk].value)
      lcd.drawText(xt+dx1, yt, text)
      lcd.setColor(0,0,0)
      dx2 = math.max(dx2, lcd.getTextWidth(FONT_NORMAL, text))
      lcd.drawText(xt+dx1+dx2+3, yt, SBT_Telem[kk].unit)
      
   end
end

local function tele()
   if builtIn then teleBuiltIn() else teleImage() end
end


local function init()

   local imgName
   local dev
   local emFlag
   local prefix
   local sf
   
   dev, emFlag = system.getDeviceType()   

   screenIdx = system.pLoad("screenIdx", 1)
   
   pcallOK, emulator = pcall(require, "sensorEmulator")
   --if not pcallOK then print("pcall error: ", emulator) end
   if pcallOK and emulator then emulator.init("digitechSBT") end

   readSensors()

   imgName = appDir.."c-000.png"
   arcFile = lcd.loadImage(imgName)

   system.registerForm(1, MENU_APPS, appName, initForm)
   system.registerTelemetry(1,appShort, 4, tele)

   if emFlag == 1 then prefix = "" else prefix="/" end

   for name, filetype, size in dir(prefix..appDir.."BuiltInScreens") do
      sf = string.find(name, ".jsn")
      if filetype == "file" and sf then
	 table.insert(screens, "#"..string.sub(name,1, sf-1))
      end
   end

   maxBuiltIn = #screens
   
   for name, filetype, size in dir(prefix..appDir.."ImageScreens") do
      --print("name:", name)
      sf = string.find(name, ".jsn")      
      if filetype == "file" and string.find(name, ".jsn") then
	 table.insert(screens, string.sub(name,1, sf-1))
      end
   end

   screenInit()
end

--------------------------------------------------------------------------------

return {init=init, loop=loop, name=appName, author=appAuthor, version=appVersion}
