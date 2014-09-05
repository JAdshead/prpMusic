require 'fiddle'
require 'fiddle/import'

require_relative '../my-ruby-methods'


class LiveMIDI
  ON  = 0x90
  OFF = 0x80
  PC  = 0xC0

  attr_reader :interval
  def initialize (bpm = 120)
    @interval = 60.0 / bpm
    @timer = Timer.get(@interval/10)
    open 
  end

  def play(channel, note, duration, velocity=100, time=nil)
    on_time = time || Time.now.to_f
    @timer.at(on_time) {note_on(channel, note, velocity)}

    off_time = on_time + duration
    @timer.at(off_time) { note_off(channel, note, velocity)}
  end



  def note_on(channel, note, velocity=64)
    puts "tick - #{note}"
    # message(ON | 1, 62, velocity)
  end

  def note_off(channel, note, velocity=64)
    puts "tock - #{note}"
    # message(OFF | 1, 62, velocity)
  end

  def program_change(channel, preset)
    message(PC | channel, preset)
  end
end

class NoMIDIDestinations < Exception; end

if RUBY_PLATFORM.include?('mswin')

  class LiveMIDI
    module C
      extend Fiddle::Importer
      dlload 'winmm'

      extern "int midiOutOpen(HMIDIOUT*, int, int, int, int)"
      extern "int midiOutClose(int)"
      extern "int midiOutShortMsg(int, int)"
    end

    def open
      @device = Fiddle.malloc(Fiddle.sizeof('I'))
      C.midiOutOpen(@device, -1, 0, 0, 0)
    end

    def close
      C.midiOutClose(@device.ptr.to_i)
    end

    def message(one, two=0, three=0)
      message = one + (two << 8) + (three << 16)
      C.midiOutShortMsg(@device.ptr.to_i, message)
    end
  end

elsif RUBY_PLATFORM.include?('darwin')

  class LiveMIDI
    module C
      extend Fiddle::Importer
      dlload '/System/Library/Frameworks/CoreMIDI.framework/Versions/Current/CoreMIDI'

      extern "int MIDIClientCreate(void *, void *, void *, void *)"
      extern "int MIDIClientDispose(void *)"
      extern "int MIDIGetNumberOfDestinations()"
      extern "void * MIDIGetDestination(int)"
      extern "int MIDIOutputPortCreate(void *, void *, void *)"
      extern "void * MIDIPacketListInit(void *)"
      extern "void * MIDIPacketListAdd(void *, int, void *, int, int, int, void *)"
      extern "int MIDISend(void *, void *, void *)"
    end

    module CF
      extend Fiddle::Importer
      dlload '/System/Library/Frameworks/CoreFoundation.framework/Versions/Current/CoreFoundation'

      extern "void * CFStringCreateWithCString (void *, char *, int)"
    end

    def open
      client_name = CF.CFStringCreateWithCString(nil, "RubyMIDI", 0)
      @client = Fiddle::Pointer.new(0)
      C.MIDIClientCreate(client_name, nil, nil, @client.ref);

      port_name = CF.CFStringCreateWithCString(nil, "Output", 0)
      @outport = Fiddle::Pointer.new(0)
      C.MIDIOutputPortCreate(@client, port_name, @outport.ref);

      num = C.MIDIGetNumberOfDestinations()
      raise NoMIDIDestinations if num < 1
      @destination = C.MIDIGetDestination(0)
    end

    def close
      C.mIDIClientDispose(@client)
    end

    def message(*args)
      format = "C" * args.size
      bytes = args.pack(format).to_ptr
      packet_list = Fiddle.malloc(256)
      packet_ptr  = C.MIDIPacketListInit(packet_list)
      # Pass in two 32 bit 0s for the 64 bit time
      packet_ptr  = C.MIDIPacketListAdd(packet_list, 256, packet_ptr, 0, 0, args.size, bytes)
      C.MIDISend(@outport, @destination, packet_list)
    end
  end

elsif RUBY_PLATFORM.include?('linux')
  class LiveMIDI
    # Linux code here
  end
else
  raise "Couldn't find a LiveMIDI implementation for your platform"
end


class Timer
  def initialize(resolution)
    @resolution = resolution
    @queue = []

    Thread.new do
      while true
        dispatch
        sleep(@resolution)
      end
    end
  end

  def self.get(interval)
    @timers ||={}
    return @timers[interval] if @timers[interval]
    return @timers[interval] = self.new(interval)
  end


  private
  def dispatch
    now = Time.now.to_f
    ready, @queue = @queue.partition{|time,proc| time <= now }
    ready.each {|time, proc| proc.call(time) }
  end

  public
  def at(time, &block)
    time = time.to_f if time.kind_of?(Time)
    @queue.push [time, block]
  end
end

class Metronome
  def initialize(bpm)
    @midi = LiveMIDI.new
    @interval = 60.0 / bpm
    @timer = Timer.get(@interval / 10)
    now = Time.now.to_f
    register_next_bang(now)
  end

  def register_next_bang(time)
    @timer.at(time) do |this_time|
      register_next_bang(this_time + @interval)
      bang 
    end
  end

  def bang
    @midi.play(1,84,0.1,Time.now.to_f + 0.2)

  end

end

class Pattern
  def initialize(base, string)
    @base = base
    @seq = parse(string)
  end

  def [](index)
    value, duration = @seq[index % @seq.size]
    return value, duration if value.nil?
    return @base + value, duration
  end

  def size
    return @seq.size
  end

  private
  def parse(string)
    characters = string.split(//)
    no_spaces = characters.grep(/\S/)
    return build(no_spaces)
  end

  def build(list)
    return [] if list.empty?
    duration = 1 + run_length(list.rest)
    value = case list.first
      when /-|=/ then nil
      when /\D/ then 0
      else list.first.to_i
    end
    return [[value, duration]] + build(list.rest)
  end

  def run_length(list)
    return 0 if list.empty?
    return 0 if list.first != "="
    return 1 + run_length(list.rest)
  end

end

class SongPlayer 

  def initialize(player,bpm, pattern)
    @player = player
    @interval = 60.0 / bpm
    @pattern = Pattern.new(60, pattern )
    @timer = Timer.new(@interval / 10)
    @count = 0
    play(Time.now.to_f)
  end

  def play(time)
    note, duration = @pattern[@count]
    @count += 1
    return if @count >= @pattern.size
    length = @interval * duration - (@interval * 0.10)
    @player.play(0, note, length) unless note.nil?
    @timer.at(time + @interval) {|at| play(at) }
  end

end

bpm = 120
midi = LiveMIDI.new(bpm)
SongPlayer.new(midi, bpm, "4202 444= 222= 477=")
sleep(10)



























