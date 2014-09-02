require 'dl/import'

class LiveMIDI

  ON  = 0x90
  OFF = 0x80
  PC  = 0xC0

  def initialize
    open
  end

  def note_on(channel, note, velocity=64)
    message(ON | channel, note, velocity)
  end

  def note_off(channel, note, velocity=64)
    message(OFF | channel, note, velocity)
  end

  def program_change(channel, preset)
    message(PC | channel, preset)
  end

end

if RUBY_PLATFORM.include?('mswin')
  
  class LiveMIDI
    # windows code here
    module C
      extend DL::Importer
      dlload 'winmm'

      extern "int midiOutOpen(HMIDIOUT*,  int, int, int, int)"
      extern "int midiOutClose(int)"
      extern "int midiOutShortMsg(int, int)"
    end

    def open
      @device = DL.malloc(DL.sizeof('I'))
      c.midiOutOpen(@device, -1,0,0,0)
    end

    def close
      c.midiOutClose(@device,ptr.to_i)
    end

    def message(one, two=0, three=0)
      message = one + (two<<8) + (three << 16)
      c.midiOutShortMsg(@device.ptr.to_i, message)
    end
  end

elsif RUBY_PLATFORM.include?('darwin')
  class LiveMIDI
    # Mac code here
    extend DL::Importer
    dlload '/System/Library/Frameworks/CoreMIDI.Framework/Versions/Current/CoreMIDI'

    extern "int MIDIClientCreate(void *, void *, void *, void *)"
    extern "int MIDIClientDispose(void *)"
    extern "int MIDIGetNumberOfDestinations()"
    extern "void * MIDIGetDestination(int)"
    extern "int MIDIOutputPortCreate(void *, void *, void *)"
    extern "void * MIDIPacketListInit(void *)"
    extern "void * MIDIPacketListAdd(void *, int, void *, int, int, int, void *)"
    extern "int MIDISend(void *, void *, void *)"

    module CF
      extend DL::Importer
      dlload '/System/Library/Frameworks/CoreFoundation.framework/Versions/Current/CoreFoundation'
      extern "void * CFStringCreateWithCString (void *, char *, int)"
    end
  end
  class NoMIDIDestinations < Exception; end
  class LiveMIDI

    def open
      client_name = CF.cFStringCreateWithCString(nil, "RubyMIDI", 0)
      @client = DL::PtrData.new(nil)
      C.mIDIClientCreate(client_name, nil, nil, @client.ref);

      port_name = CF.cFStringCreateWithCString(nil, "Output", 0)
      @outport = DL::PtrData.new(nil)
      C.mIDIOutputPortCreate(@client, port_name, @outport.ref);

      num = C.mIDIGetNumberOfDestinations()
      raise NoMIDIDestinations if num < 1
      @destination = C.mIDIGetDestination(0)
    end

    def close
      C.mIDIClientDispose(@client)
    end

    def message(*args)
      format = "C" * args.size
      bytes = args.pack(format).to_ptr
      packet_list = DL.malloc(256)
      packet_ptr  = C.mIDIPacketLIstInit(packet_list)
      # Pass in two 32 but 0s for the 64 bit time
      packet_ptr  = C.mIDIPacketListAdd(packet_list, 256, packet_ptr, 0, 0, args.size, bytes) 
      C.mIDISend(@outport, @destination, packet_list)
    end

  end
elseif RUBY_PLATFORM.include?('linux')
  class LiveMIDI
    #Linux code here
  end
else
  raise "Could't find a liveMIDI implementation for your platform"
end




midi = LiveMIDI.new
midi.note_on(0, 60,100)
sleep(1)
midi.note_off(0,60)
sleep(1)
midi.program_change(1,40)
midi.note_on(1,60,100)
sleep(1)
midi.note_off(1,60)














