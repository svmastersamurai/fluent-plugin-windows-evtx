require 'helper'
require 'fluent/test'
require 'fluent/test/driver/input'
require 'fluent/test/helpers'
require 'fluent/plugin/in_windows_evtx'

class WindowsEvtxInputTest < Test::Unit::TestCase
  CONFIG = config_element("ROOT", "", {"tag" => "fluent.evtxlog",
                                       'read_interval' => 0.5,
                                       'file_path' => '/home/dansedlacek/work/Microsoft-Windows-WLAN-AutoConfig%4Operational.evtx'}, [
                            config_element("storage", "", {
                                             '@type' => 'local',
                                             'persistent' => false
                                           }),
                          ])
  setup do
    Fluent::Test.setup
  end

  def create_driver(conf = CONFIG)
    Fluent::Test::Driver::Input.new(Fluent::Plugin::WindowsEvtxInput).configure(conf)
  end

  test "should output parseable JSON" do
    d = create_driver
    d.run(expect_emits: 87) #, timeout: 1.0)

    d.events.each do |evt|
      assert_nothing_raised do
        JSON.parse(evt[2])
      end
    end
  end
end
