--todo: add SNTP and RTC to add timestamps to measurements
--todo: sleep modes. put into light sleep for 1 min. On wake, connect to wifi, take sample and push.
--todo: using file to store stuff

-- Includes
require("queue")
require("peedub")
require("deviceconf")

-- Config
local function Initialise()

    print("Initialising\n")

    --configure wifi
    print("Configuring WiFi\n")
    wifi.setmode(wifi.STATION)
    wifi.sta.sethostname(deviceConf.wifi_hostname)
    local station_cfg = {}
    station_cfg.ssid = creds.wifi_ap
    station_cfg.pwd = creds.wifi_pw
    station_cfg.save=true
    wifi.sta.config(station_cfg) --will auto-connect
     wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, function(T)
        print("Got IP:",T.IP)
        print("Kicking off SNTP")
        sntp.sync(nil, nil, nil, 1)
     end)

    -- Setup BME 
    print("Configuring BME280 i2c interface\n")
    
    local sda, scl = 3, 4
    i2c.setup(0, sda, scl, i2c.SLOW) -- call i2c.setup() only once
    
    bme280.setup() 

    -- salso:
    -- As per datasheet "weather monitoring configuration" 1 x oversampling, forced mode. 1000ms standby. IIR off
    --bme280.setup(1,1,1,1,5,0)

    --config uart (not necessary)
    --uart.setup(0,115200,8,uart.PARITY_NONE,uart.STOPBITS_1,1);
    --print (uart.getconfig(0))

    -- turn LED on
    --local pin=4
    --gpio.mode(pin,gpio.OUTPUT)  
    --gpio.write(pin,gpio.LOW)
end

Initialise()

-- Create queue
queue = Queue.new()

-- Every 60s get temp and humidity and push to in-memory queue
local bmePolling_ms = 60000
tmr.alarm(0, bmePolling_ms, tmr.ALARM_AUTO, function ()

        --local H, T = bme280.humi()
        --todo: validation
        
        --local Tsgn = (T < 0 and -1 or 1); T = Tsgn*T
        --print(string.format("T=%s%d.%02d", Tsgn<0 and "-" or "", T/100, T%100))
        --print(string.format("Humidity=%d.%03d%%", H/1000, H%1000))

        -- last-known good time.
        local T, _, H, _= bme280.read()
        local tepoch = rtctime.get()
        
        if(tepoch == 0) then
            print("Warning: RTC not set up. Skipping sample")
            -- todo: last-known good + sample interval?
            return
        end

        if H ~= nil then
            H = H / 1000.0
        end
        
        sample = {
            temp = T/100.0;
            humidity = H,
            timestamp = tepoch
        }
        --print("New sample pushed to queue: ", sample.temp)
        --tm = rtctime.epoch2cal(tepoch)
        --print(string.format("Sample recorded at %04d/%02d/%02d %02d:%02d:%02d", tm["year"], tm["mon"], tm["day"], tm["hour"], tm["min"], tm["sec"]))
        Queue.pushleft(queue, sample)
end)


--poll queue
tmr.alarm(1, 9000, tmr.ALARM_AUTO, function ()
    
    -- check wifi connectivity before trying to pop. 
    local status = wifi.sta.status()
    if(status ~= wifi.STA_GOTIP) then
        --should be trying to auto-connect. Wait until next iteration.
        print("Wifi not connected. StatusCode: ", status)
        return
    end

    --pop from queue
    local item = Queue.popright(queue)
    if(item == nil) then
        return --empty
    end
    
    print(string.format("Popped item from queue. T %02d",item.temp))

    ---- post to powerbi
    local tm = rtctime.epoch2cal(item.timestamp)
    local timestamp = string.format("%04d-%02d-%02dT%02d:%02d:%02dZ", tm["year"], tm["mon"], tm["day"], tm["hour"], tm["min"], tm["sec"])
    local postBody = {
        timestamp = timestamp,
        temperature = item.temp,
        location = deviceConf.location,
        notes = deviceConf.notes,
        sensorId = deviceConf.sensorId,
        humidity = item.humidity
    }
    
    local ok,body = pcall(sjson.encode,postBody)
    body = "[".. body.. "]"
    if ok then
        print("Posting to PowerBI")
        http.post(creds.powerbi_url, 
            'Content-Type: application/json\r\n',
             body,
             function(code, data)
                if (code < 0) then
                  print("HTTP request failed")
                else
                  print(code, data)
                end
            end)
    else
        print("sjson encode failed")
    end

    --todo: if failed then put back on the queue
    --todo: post to docdb +/- somewhere on local network?
    
end)    

--something about wifi suspend if the op is going to take more than 15ms??
