require "helper"
require "fluent/plugin/in_windows_evtx.rb"

class WindowsEvtxInputTest < Test::Unit::TestCase
  setup do
    Fluent::Test.setup
  end

  test "failure" do
    create_driver('a')
  end

  private

  def create_driver(conf)
    Fluent::Test::Driver::Input.new(Fluent::Plugin::WindowsEvtxInput).configure(conf)
  end
end
