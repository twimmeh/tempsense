--todo: add SNTP and RTC to add timestamps to measurements
--todo: sleep modes. put into light sleep for 1 min. On wake, connect to wifi, take sample and push.

-- Includes
require("queue")
require("peedub")

-- Config
local function Initialise()

    print("Initialising\n")

    --configure wifi
    print("Configuring WiFi\n")
    wifi.setmode(wifi.STATION)
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
    
    -- initialize to sleep mode
    bme280.setup(nil, nil, nil, 0) 

    -- salso:
    -- As per datasheet "weather monitoring configuration" 1 x oversampling, forced mode. 1000ms standby. IIR off
    --bme280.setup(1,1,1,1,5,0)

    --config uart (not necessary)
    --uart.setup(0,115200,8,uart.PARITY_NONE,uart.STOPBITS_1,1);
    --print (uart.getconfig(0))
end

Initialise()

-- Create queue
queue = Queue.new()

-- Every 60s get temp and humidity and push to in-memory queue
local bmePolling_ms = 10000
tmr.alarm(0, bmePolling_ms, tmr.ALARM_AUTO, function ()
    bme280.startreadout(0, function ()
        T, P, H = bme280.read()
        local Tsgn = (T < 0 and -1 or 1); T = Tsgn*T
        --print(string.format("T=%s%d.%02d", Tsgn<0 and "-" or "", T/100, T%100))
        --print(string.format("Humidity=%d.%03d%%", H/1000, H%1000))

        -- last-known good time.
        tepoch = rtctime.get()
        
        if(tepoch == 0) then
            print("Warning: RTC not set up. Skipping sample")
            -- todo: last-known good + sample interval?
            return
        end

        sample = {
            temp = T/100.0,
            humidity = H/1000.0,
            timestamp = tepoch
        }

        
        print("New sample pushed to queue: ", sample.temp)
        --tm = rtctime.epoch2cal(tepoch)
        --print(string.format("Sample recorded at %04d/%02d/%02d %02d:%02d:%02d", tm["year"], tm["mon"], tm["day"], tm["hour"], tm["min"], tm["sec"]))
        Queue.pushleft(queue,s)
    end)    
end)


--poll queue
tmr.alarm(1, 6000, tmr.ALARM_AUTO, function ()
    
    -- check wifi connectivity before trying to pop. 
    
    --pop from queue
    local item = Queue.popright(queue)
    if(item == nil) then
        return
    end
    
    print("Popped item from queue.")
    print ("Temp: ", item.temp)
    print ("Humidity: ", item.humidity)
    print ("Timestamp: ", item.timestamp)
    
    --todo: post somewhere. if failed then put back on the queue
    --todo: post to powerbi + docdb + somewhere on local network?

    --if failed, push back onto queue
end)    

--something about wifi suspend if the op is going to take more than 15ms??
