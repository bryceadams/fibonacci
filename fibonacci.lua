-- fibonacci
-- 0.1 @obi
-- based on awake 2.6.0 @tehn
--
-- HOME
-- K2 pauses/plays
-- K3 resets number
--
-- SETTINGS
-- E1 change page
-- K2/K3 toggle settings
-- E2 change first setting
-- E3 change second setting
--
-- LOOP (NOT YET)
-- E2/E3 loop length
-- K2 reset position
-- K3 jump position

engine.name = 'PolyPerc'

local hs = include('lib/halfsecond')

local MusicUtil = require "musicutil"

local options = {}
options.OUT = {"audio", "midi", "audio + midi", "crow out 1+2", "crow ii JF"}

local running = true

local mode = 1
local mode_names = {"", "PATTERN","SOUND"}

local numbers = {0, 1, 1}
local numbers_built = false
local current_number = 3
local current_number_part = 1

local midi_devices
local midi_device
local midi_channel

local scale_names = {}
local notes = {}
local active_notes = {}
local octave_level = 0

local main_sel = 1
local main_names = {"bpm","mult","root","scale","note length","probability"}
local main_params = {"clock_tempo","step_div","root_note","scale_mode", "random_note_lengths", "probability"}
local NUM_MAIN_PARAMS = #main_params

local snd_sel = 1
local snd_names = {"cut","gain","pw","rel","fb","rate", "pan", "delay_pan"}
local snd_params = {"cutoff","gain","pw","release", "delay_feedback","delay_rate", "pan", "delay_pan"}
local NUM_SND_PARAMS = #snd_params

local notes_off_metro = metro.init()

function build_scale()
  notes = MusicUtil.generate_scale_of_length(params:get("root_note"), params:get("scale_mode"), 16)
  local num_to_add = 16 - #notes
  for i = 1, num_to_add do
    table.insert(notes, notes[16 - num_to_add])
  end
end

function all_notes_off()
  if (params:get("out") == 2 or params:get("out") == 3) then
    for _, a in pairs(active_notes) do
      midi_device:note_off(a, nil, midi_channel)
    end
  end
  active_notes = {}
end

-- dynamic might be better but can't figure out yet
function build_numbers()
    repeat
        local new_number = numbers[#numbers - 1] + numbers[#numbers]
        table.insert(numbers, new_number)
    until(string.len(new_number) >= 18)

    numbers_built = true
end

function step()
  while true do

    clock.sync(1/params:get("step_div"))
    if running and numbers_built then
        all_notes_off()

        -- check end of number and tick if need to
        if current_number_part == string.len(numbers[current_number]) then
            current_number = current_number + 1
            current_number_part = 1
        else
            current_number_part = current_number_part + 1
        end

        -- end of the line? reset (@todo reverse mode?)
        if current_number > #numbers then
            reset()
        end

        -- if 0 set to 10
        local number_to_play = tonumber(string.sub(numbers[current_number], current_number_part, current_number_part))

        local blank_note = false
        -- zero behaviour
        local zb = params:get("zero_behaviour")
        if zb == 1 or zb == 2 then
          if number_to_play == 0 then
            number_to_play = 10

            if zb == 2 then
              blank_note = true
            end
          end
        elseif zb == 3 then
          -- not yet
          print('octave level: '.. octave_level)

          local octave_direction = octave_level == 1 and -1 or 1
          octave_level = octave_level + octave_direction
          number_to_play = number_to_play + (octave_direction * 12)
          print(number_to_play)
        end

        local note_num = notes[number_to_play]
        local freq = MusicUtil.note_num_to_freq(note_num)

        -- Blank note and Trig Probablility
        if not blank_note and math.random(100) <= params:get("probability") then
            -- Audio engine out
            if params:get("out") == 1 or params:get("out") == 3 then
              if params:get('random_note_lengths') then
                -- use the golden ratio to determine if different length or not - use base attack for main one
                if Math.random(100, 200) / 100 > (8/5) then
                  --engine.release(math.random(2, 30) / 10)
                end
              end

                engine.hz(freq)
            elseif params:get("out") == 4 then
                crow.output[1].volts = (note_num-60)/12
                crow.output[2].execute()
            elseif params:get("out") == 5 then
                crow.ii.jf.play_note((note_num-60)/12,5)
            end

            -- MIDI out
            if (params:get("out") == 2 or params:get("out") == 3) then
                midi_device:note_on(note_num, 96, midi_channel)
                table.insert(active_notes, note_num)

                --local note_off_time =
                -- Note off timeout
                if params:get("midi_note_length") < 4 then
                    notes_off_metro:start((60 / params:get("clock_tempo") / params:get("step_div")) * params:get("midi_note_length") * 0.25, 1)
                end
            end
        end
      redraw()
    else
    end
  end
end

function stop()
  running = false
  all_notes_off()
end

function start()
  running = true
end

function reset()
  current_number = 3
  current_number_part = 1
end

function clock.transport.start()
  start()
end

function clock.transport.stop()
  stop()
end

function clock.transport.reset()
  reset()
end

function midi_event(data)
  msg = midi.to_msg(data)
  if msg.type == "start" then
      clock.transport.reset()
      clock.transport.start()
  elseif msg.type == "continue" then
    if running then
      clock.transport.stop()
    else
      clock.transport.start()
    end
  end
  if msg.type == "stop" then
    clock.transport.stop()
  end
end

function build_midi_device_list()
  midi_devices = {}
  for i = 1,#midi.vports do
    local long_name = midi.vports[i].name
    local short_name = string.len(long_name) > 15 and util.acronym(long_name) or long_name
    table.insert(midi_devices,i..": "..short_name)
  end
end

function init()
  for i = 1, #MusicUtil.SCALES do
    table.insert(scale_names, string.lower(MusicUtil.SCALES[i].name))
  end

  -- start clock tempo
  params:set("clock_tempo", 100)

  build_midi_device_list()
  build_numbers()

  notes_off_metro.event = all_notes_off

  params:add_separator("fibonacci")

  params:add_group("outs",3)
  params:add{type = "option", id = "out", name = "out",
    options = options.OUT,
    action = function(value)
      all_notes_off()
      if value == 4 then crow.output[2].action = "{to(5,0),to(0,0.25)}"
      elseif value == 5 then
        crow.ii.pullup(true)
        crow.ii.jf.mode(1)
      end
    end}
  params:add{type = "option", id = "midi_device", name = "midi out device",
    options = midi_devices, default = 1,
    action = function(value) midi_device = midi.connect(value) end}

  params:add{type = "number", id = "midi_out_channel", name = "midi out channel",
    min = 1, max = 16, default = 1,
    action = function(value)
      all_notes_off()
      midi_channel = value
    end}

  params:add_group("step",8)

  -- @todo
  params:add{type = "option", id = "zero_behaviour", name = "zero behaviour",
    options = {"play ten", "blank note"}, -- "octave shift"},
    default = 1}

  params:add{type = "number", id = "step_div", name = "step division", min = 1, max = 16, default = 2}

  params:add{type = "number", id = "random_note_lengths", name = "random note length",
    min = 0, max = 4,
    default = 0}

  params:add{type = "option", id = "midi_note_length", name = "midi note length",
    options = {"25%", "50%", "75%", "100%"},
    default = 4}

  params:add{type = "option", id = "scale_mode", name = "scale mode",
    options = scale_names, default = 5,
    action = function() build_scale() end}
  params:add{type = "number", id = "root_note", name = "root note",
    min = 0, max = 127, default = 60, formatter = function(param) return MusicUtil.note_num_to_name(param:get(), true) end,
    action = function() build_scale() end}
  params:add{type = "number", id = "probability", name = "probability",
    min = 0, max = 100, default = 100}
  params:add{type = "trigger", id = "stop", name = "stop",
    action = function() stop() reset() end}
  params:add{type = "trigger", id = "start", name = "start",
    action = function() start() end}
  params:add{type = "trigger", id = "reset", name = "reset",
    action = function() reset() end}


  params:add_group("synth",5)

  params:add{type = "number", id = "loop_start", name = "loop start",
    min = 0, max = #numbers, default = 0,
    formatter = function(param)
      return 0 and '-' or numbers[param]
    end
  }

  params:add{type = "number", id = "loop_size", name = "loop size",
    min = 1, max = 16, default = 8}

  params:add_group("synth",6)
  cs_AMP = controlspec.new(0,1,'lin',0,0.5,'')
  params:add{type="control",id="amp",controlspec=cs_AMP,
    action=function(x) engine.amp(x) end}

  cs_PW = controlspec.new(0,100,'lin',0,50,'%')
  params:add{type="control",id="pw",controlspec=cs_PW,
    action=function(x) engine.pw(x/100) end}

  cs_REL = controlspec.new(0.1,3.2,'lin',0,1.2,'s')
  params:add{type="control",id="release",controlspec=cs_REL,
    action=function(x) engine.release(x) end}

  cs_CUT = controlspec.new(50,5000,'exp',0,800,'hz')
  params:add{type="control",id="cutoff",controlspec=cs_CUT,
    action=function(x) engine.cutoff(x) end}

  cs_GAIN = controlspec.new(0,4,'lin',0,1,'')
  params:add{type="control",id="gain",controlspec=cs_GAIN,
    action=function(x) engine.gain(x) end}

  cs_PAN = controlspec.new(-1,1, 'lin',0,0,'')
  params:add{type="control",id="pan",controlspec=cs_PAN,
    action=function(x) engine.pan(x) end}

  hs.init()

  params:default()
  midi_device.event = midi_event

  clock.run(step)

  norns.enc.sens(1,8)
end

function enc(n, delta)
  if n==1 then
    -- change mode for pattern/sound
    mode = util.clamp(mode+delta,1,3)
  elseif mode == 2 then --step
    if n==2 then
      params:delta(main_params[main_sel], delta)
    elseif n==3 then
      params:delta(main_params[main_sel+1], delta)
    end
  elseif mode == 3 then --loop
    if n==2 then
      params:delta(snd_params[snd_sel], delta)
    elseif n==3 then
      params:delta(snd_params[snd_sel+1], delta)
    end
  end
  redraw()
end

function key(n,z)
    if z==1 then
        if mode == 1 then
          if n==2 then
            running = not running
          elseif n==3 then
            reset()
          end
        elseif mode == 2 then
            if n==2 then
                main_sel = util.clamp(main_sel - 2,1,NUM_MAIN_PARAMS-1)
            elseif n==3 then
                main_sel = util.clamp(main_sel + 2,1,NUM_MAIN_PARAMS-1)
            end
        elseif mode == 3 then
            if n==2 then
                snd_sel = util.clamp(snd_sel - 2,1,NUM_SND_PARAMS-1)
            elseif n==3 then
                snd_sel = util.clamp(snd_sel + 2,1,NUM_SND_PARAMS-1)
            end
        end
    end

    redraw()
end

function redraw()
  screen.clear()
  screen.line_width(1)
  screen.aa(0)

  -- defaults
  screen.font_size(8)
  screen.font_face(1)
  screen.level(4)
  screen.move(0,10)
  screen.text(mode_names[mode])

  if mode==2 then
    -- settings status dots
    screen.move(0, 20)
    screen.level(main_sel == 1 and 15 or 2)
    screen.text('.')
    screen.level(main_sel == 3 and 15 or 2)
    screen.text('.')
    screen.level(main_sel == 5 and 15 or 2)
    screen.text('.')

    screen.level(1)
    screen.move(0,30)
    screen.text(main_names[main_sel])
    screen.level(15)
    screen.move(0,40)
    screen.text(params:string(main_params[main_sel]))
    screen.level(1)
    screen.move(0,50)
    screen.text(main_names[main_sel+1])
    screen.level(15)
    screen.move(0,60)
    screen.text(params:string(main_params[main_sel+1]))
  elseif mode==3 then
    -- settings status dots
    screen.move(0, 20)
    screen.level(snd_sel == 1 and 15 or 2)
    screen.text('.')
    screen.level(snd_sel == 3 and 15 or 2)
    screen.text('.')
    screen.level(snd_sel == 5 and 15 or 2)
    screen.text('.')
    screen.level(snd_sel == 7 and 15 or 2)
    screen.text('.')

    screen.level(1)
    screen.move(0,30)
    screen.text(snd_names[snd_sel])
    screen.level(15)
    screen.move(0,40)
    screen.text(params:string(snd_params[snd_sel]))
    screen.level(1)
    screen.move(0,50)
    screen.text(snd_names[snd_sel+1])
    screen.level(15)
    screen.move(0,60)
    screen.text(params:string(snd_params[snd_sel+1]))
  end

  -- previous numbers
  if mode == 1 then
    screen.font_size(7)
    screen.font_face(15)
    screen.level(2)
    screen.move(0,24)
    screen.text(numbers[current_number - 2])
    screen.level(15)
    screen.move_rel(1, 0)
    screen.text('+')

    screen.move(0,34)
    screen.level(2)
    screen.text(numbers[current_number - 1])

    -- current number
    screen.move(0, 46)
    screen.font_size(9)
    screen.font_face(15)

    local number_playing = numbers[current_number]

    for i=1,string.len(number_playing) do
      local number_part_playing = tonumber(string.sub(number_playing, i, i))
      if i == current_number_part then
          screen.level(15)
          --screen.font_face(7) -- bold
      else
          screen.level(1)
          --screen.font_face(5) -- normal
      end
      screen.text(number_part_playing)

      if i < #numbers then
        screen.move_rel(1, 0)
      end

      -- new line?
      if i == 9 then
          --screen.move(50, 42)
      end
    end
  end

  for i=1,10 do
    local number_to_play = tonumber(string.sub(numbers[current_number], current_number_part, current_number_part))
    number_to_play = number_to_play == 0 and 10 or number_to_play
    local light = number_to_play == i and 15 or 2
    draw_cube(100 + (i > 5 and 10 or 0), 0+((i > 5 and i - 5 or i)*10), light)
  end
  screen.update()
end

function draw_cube(m, n, light)
  screen.rect(m, n, 6, 6) -- (x,y,width,height)
  screen.level(light)
  screen.stroke()
end

function cleanup()
end