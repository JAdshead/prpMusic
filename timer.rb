require_relative 'music.rb'

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
    @midi.play(0,84,0.1,Time.now.to_f + 0.2)

  end

end


m = Metronome.new(160)
sleep(10)






